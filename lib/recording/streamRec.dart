/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
/*
 * streamRec.dart
 */

import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:record/record.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../bottomBar.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/recording/waw.dart'; // Contains createWavHeader & concatWavFiles
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

final logger = Logger();

class RecordingTaskHandler extends TaskHandler {
  int counter = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    counter = 0;
    logger.i("Foreground task started at \$timestamp");
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {
    counter++;
    // Update the notification to reflect the elapsed recording time
    FlutterForegroundTask.updateService(
      notificationTitle: 'Recording in progress',
      notificationText: 'Recording for ' + counter.toString() + ' seconds',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    logger.i("Foreground task destroyed at \$timestamp");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    logger.i("Repeat event at \$timestamp");
  }
}

void startRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class ElapsedTimer {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final ValueChanged<Duration> onTick;

  ElapsedTimer({required this.onTick});

  void start() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void pause() {
    _stopwatch.stop();
    _ticker?.cancel();
  }

  void resume() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void reset() {
    _stopwatch.reset();
    _ticker?.cancel();
    onTick(_stopwatch.elapsed);
  }

  Duration get elapsed => _stopwatch.elapsed;

  void dispose() {
    _stopwatch.stop();
    _ticker?.cancel();
  }
}

class LiveRec extends StatefulWidget {
  const LiveRec({super.key});

  @override
  State<LiveRec> createState() => _LiveRecState();
}

int calcBitRate(int sampleRate, int bitDepth) {
  return sampleRate * bitDepth;
}

void _showMessage(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Informace'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

void exitApp(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Informace'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => SystemNavigator.pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> getLocationPermission(BuildContext context) async {
  LocationPermission permission = await Geolocator.requestPermission();
  logger.i("Location permission: $permission");
  while (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    _showMessage(context, "Pro správné fungování aplikace je potřeba povolit lokaci");
    permission = await Geolocator.requestPermission();
    logger.i("Location permission: $permission");
    if (permission == LocationPermission.deniedForever) {
      exitApp(context, "Pro správné fungování aplikace je potřeba povolit lokaci");
    }
  }
}

class _LiveRecState extends State<LiveRec> {
  Duration _recordDuration = Duration.zero;
  Duration _totalRecordedTime = Duration.zero;
  String filepath = "";
  late final ElapsedTimer _elapsedTimer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  int sampleRate = 0;
  int bitRate = 0;
  final recordingPartsTimeList = <int>[];
  List<RecordingPartUnready> recordingPartsList = [];
  RecordingPartUnready? recordedPart;
  DateTime? overallStartTime;
  DateTime? segmentStartTime;
  String? recordedFilePath;
  LatLng? currentPosition;
  final List<LatLng> _liveRoute = [];
  final List<String> segmentPaths = [];
  StreamSubscription? _locationSub;
  late LocationService _locService;
  bool recording = false;
  bool _hasMicPermission = false;

  bool _isProcessingRecording = false;

  @override
  void initState() {
    super.initState();

    getLocationPermission(context);
    _initAudioSettings();
    _audioRecorder = AudioRecorder();
    _audioRecorder.hasPermission().then((allowed) {
      setState(() {
        _hasMicPermission = allowed;
      });
    });
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    _locService = LocationService();
    _locationSub = _locService.positionStream.listen((position) {
      setState(() {
        currentPosition = LatLng(position.latitude, position.longitude);
        _liveRoute.add(LatLng(position.latitude, position.longitude));
      });
    });
    _elapsedTimer = ElapsedTimer(onTick: (elapsed) {
      setState(() {
        _recordDuration = elapsed;
      });
    });
  }

  static const MethodChannel _platform = MethodChannel('com.delta.strnadi/audio');

  Future<void> _initAudioSettings() async {
    try {
      final Map<dynamic, dynamic>? settings =
      await _platform.invokeMethod('getBestAudioSettings');
      if (settings != null) {
        setState(() {
          sampleRate = settings['sampleRate'] ?? 48000;
          int depth = 16; // assuming 16-bit depth
          bitRate = calcBitRate(sampleRate, depth);
        });
        logger.i('Audio settings: sampleRate=$sampleRate, bitRate=$bitRate');
      }
    } catch (e, stackTrace) {
      logger.e('Failed to get audio settings, using defaults: $e',
          error: e, stackTrace: stackTrace);
      setState(() {
        sampleRate = 48000;
        bitRate = calcBitRate(48000, 16);
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_isProcessingRecording) return; // Prevent reentry

    setState(() {
      _isProcessingRecording = true;
    });
    try{
      if (!_hasMicPermission) {
        // Request microphone permission
        var status = await Permission.microphone.request();
        if (status.isGranted) {
          setState(() {
            _hasMicPermission = true;
          });
        } else {
          _showMessage(context, 'Pro správné fungování aplikace je potřeba povolit mikrofon');
          return;
        }
      }
      if (_recordState == RecordState.record) {
        _pause();
      } else if (_recordState == RecordState.pause) {
        _resume();
      } else {
        _start();
      }
    }
    catch(e, stackTrace){
      logger.e("Error toggling recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
    finally {
      setState(() {
        _isProcessingRecording = false;
      });
    }
  }

  Future<void> _stop() async {
    if (_recordState == RecordState.record) {
      try {
        await _audioRecorder.stop();
        WakelockPlus.disable();
        _elapsedTimer.pause();
      } catch (e, stackTrace) {
        logger.e("Error stopping recorder: $e", error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        return;
      }
      int segmentDuration = _recordDuration.inSeconds;
      setState(() {
        _totalRecordedTime += _recordDuration;
        _recordDuration = Duration.zero;
        recording = false;
      });
      recordingPartsTimeList.add(segmentDuration);
      recordedPart!.endTime = DateTime.now();
      logger.i('Segment end time: ${recordedPart!.endTime}');
      Uint8List data = await File(filepath).readAsBytes();
      final dataWithHeader =
          createWavHeader(data.length, sampleRate, bitRate) + data;
      if (recordedPart != null) {
        recordedPart!.dataBase64 = base64Encode(dataWithHeader);
      }
      await File(filepath).delete();
      File newFile = await File(filepath).create();
      await newFile.writeAsBytes(dataWithHeader);
      if (_locService.lastKnownPosition == null) {
        await _locService.getCurrentLocation();
      }
      if (recordedPart != null) {
        recordedPart!.gpsLatitudeEnd = _locService.lastKnownPosition?.latitude;
        recordedPart!.gpsLongitudeEnd = _locService.lastKnownPosition?.longitude;
      }
      recordingPartsList.add(recordedPart!);
    } else if (_recordState == RecordState.pause) {
      setState(() {
        recording = false;
      });
    }
    List<String> paths = segmentPaths;
    final String outputPath = await _getPath();
    try {
      await concatWavFiles(paths, outputPath, sampleRate, bitRate);
      recordedFilePath = outputPath;
      logger.i('Final recording saved to: $outputPath');
    } catch (e, stackTrace) {
      logger.e("Error concatenating files: $e",
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return;
    }
    await FlutterForegroundTask.stopService();
    if (overallStartTime == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: RecordingForm(
            filepath: recordedFilePath!,
            startTime: overallStartTime!,
            currentPosition: currentPosition,
            recordingParts: recordingPartsList,
            recordingPartsTimeList: recordingPartsTimeList,
            route: _liveRoute,
          ),
        ),
      ),
    );
  }

  Future<String> _getPath() async {
    final dir = await getApplicationDocumentsDirectory();
    String path = p.join(
      dir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    logger.i('Generated file path: $path');
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final totalTime = _totalRecordedTime + _recordDuration;

    // Define custom colors to match your design.
    final Color primaryRed = const Color(0xFFFF3B3B);
    final Color secondaryRed = const Color(0xFFFFEDED);

    // Rework the recording button based on state.
    IconData iconData = Icons.mic;
    Color fillColor = primaryRed;
    Color iconColor = Colors.white;
    Border? border = null;
    List<BoxShadow> boxShadows = [];

    if (_recordState == RecordState.stop) {
      // Stop state: filled red circle with white mic icon.
      iconData = Icons.mic;
      fillColor = primaryRed;
      iconColor = Colors.white;
      border = null;
      boxShadows = [];
    } else if (_recordState == RecordState.record) {
      // Recording (pause button visible): white circle, thicker red border, red icon + glow
      iconData = Icons.pause;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withOpacity(0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    } else if (_recordState == RecordState.pause) {
      // Paused (play button visible): white circle, thicker red border, red icon + glow
      iconData = Icons.play_arrow;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withOpacity(0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        // Always forbid the Android back button by doing nothing
      },
      child: ScaffoldWithBottomBar(
        content: SingleChildScrollView(
          child: ConstrainedBox(constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height,
          ),
          child: Column(
            mainAxisAlignment: _recordState == RecordState.stop ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              SizedBox(height: 64),
              if (_recordState == RecordState.stop) ...[
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20.0),
                            child: Image.asset(
                              'assets/images/bird_example.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                      ),
                      Positioned(
                        bottom: 12,
                        left: 32,
                        child: Container(
                          color: Colors.black54,
                          padding: const EdgeInsets.all(4),
                          child: const Text(
                            'Foto: Tomáš Bělka',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              // Recording button with vertical padding
              Padding(
                padding: _recordState == RecordState.stop? const EdgeInsets.only(top: 20) : const EdgeInsets.only(top: 240),
                child: Opacity(
                  opacity: _hasMicPermission ? 1.0 : 0.5,
                  child: AbsorbPointer(
                    absorbing: _isProcessingRecording, // disable when processing
                    child: Semantics(
                      label: _recordState == RecordState.stop
                          ? "Start recording"
                          : _recordState == RecordState.record
                          ? "Pause recording"
                          : "Resume recording",
                      button: true,
                      child: GestureDetector(
                        onTap: _toggleRecording,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: fillColor,
                            border: border,
                            boxShadow: boxShadows,
                          ),
                          child: _recordState == RecordState.pause
                              ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_arrow,
                                size: 40,
                                color: iconColor,
                              ),
                              Icon(
                                Icons.mic,
                                size: 20,
                                color: iconColor,
                              ),
                            ],
                          )
                              : Icon(
                            iconData,
                            color: iconColor,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Timer with a round border (red when recording, gray otherwise)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _recordState == RecordState.record ? primaryRed : Colors.grey,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(
                  _formatTime(totalTime),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    fontFamily: 'Bricolage Grotesque',
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Status text
              if (_recordState == RecordState.stop) ...[
                Text(
                  "Stisknutím zahájíte nahrávání",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontFamily: 'Bricolage Grotesque',
                  ),
                ),
              ] else if (_recordState == RecordState.record) ...[
                Text(
                  "Nahrává se…",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontFamily: 'Bricolage Grotesque',
                  ),
                ),
              ] else if (_recordState == RecordState.pause) ...[
                Text(
                  "Nahrávání pozastaveno – klepněte pro obnovení",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontFamily: 'Bricolage Grotesque',
                  ),
                ),
              ],
              const SizedBox(height: 40),

              // Finish button is visible when recording or paused
              if (_recordState == RecordState.record || _recordState == RecordState.pause)
                Semantics(
                  label: "Finish and continue",
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _stop,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: secondaryRed,
                          foregroundColor: primaryRed,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Bricolage Grotesque',
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.stop, color: primaryRed),
                            const SizedBox(width: 8),
                            const Text(
                              "Dokončit a pokračovat",
                              style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Inserted discard recording button moved to bottom of UI
              if (_recordState == RecordState.record || _recordState == RecordState.pause)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _discardRecording,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Bricolage Grotesque',
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text(
                            "Zahodit nahrávání",
                            style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
          ),
        ),
      )
    );
  }

  void clear() {
    setState(() {
      _recordDuration = Duration.zero;
      _totalRecordedTime = Duration.zero;
      segmentPaths.clear();
      recordingPartsList.clear();
      recordingPartsTimeList.clear();
      recordedFilePath = null;
      _recordState = RecordState.stop;
    });
    if (filepath.isNotEmpty) {
      File(filepath).delete();
    }
  }

  void _discardRecording() {
    _pause();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Potvrdit zahození'),
          content: const Text('Opravdu chcete zahodit aktuální nahrávání?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zrušit'),
            ),
            TextButton(
              onPressed: () {
                clear();
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LiveRec()),
                );
              },
              child: const Text('Zahodit'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _start() async {
    WakelockPlus.enable();
    await FlutterForegroundTask.startService(
      notificationTitle: 'Strnadi',
      notificationText: 'Aplikace Strnadi nahrává',
      callback: startRecordingCallback,
    );
    try {
      logger.i('Started recording');
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;
        if (!await _isEncoderSupported(encoder)) return;
        final config = RecordConfig(
          encoder: encoder,
          numChannels: 1,
          sampleRate: sampleRate,
          bitRate: bitRate,
        );
        filepath = await _getPath();
        logger.i('Recording file path: $filepath');
        if (_locService.lastKnownPosition == null) {
          await _locService.getCurrentLocation();
        }
        overallStartTime = DateTime.now();
        logger.i('Overall start time: $overallStartTime');
        // Create a new segment.
        recordedPart = RecordingPartUnready(
          gpsLongitudeStart: _locService.lastKnownPosition?.longitude,
          gpsLatitudeStart: _locService.lastKnownPosition?.latitude,
          startTime: overallStartTime,
        );
        logger.i('Recorded part start time: ${recordedPart!.startTime}');
        _elapsedTimer.reset();
        _elapsedTimer.start();
        segmentPaths.add(filepath);
        recordStream(_audioRecorder, config, filepath);
        setState(() {
          recording = true;
          _recordState = RecordState.record;
        });
      } else {
        _showMessage(context, 'Pro správné fungování aplikace je potřeba povolit mikrofon');
        return;
      }
    } catch (e, stackTrace) {
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final hundredths = ((duration.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds,$hundredths';
  }

  Future<String> recordStream(
      AudioRecorder recorder, RecordConfig config, String filepath) async {
    final file = File(filepath);
    final stream = await recorder.startStream(config);
    final completer = Completer<String>();
    stream.listen(
          (data) {
        file.writeAsBytes(data, mode: FileMode.append);
      },
      onDone: () {
        logger.i('End of stream. File written to $filepath.');
        completer.complete(filepath);
      },
      onError: (error) {
        completer.completeError(error);
      },
    );
    return completer.future;
  }

  Future<void> _pause() async {
    await _audioRecorder.stop();
    _elapsedTimer.pause();
    int segmentDuration = _recordDuration.inSeconds;
    _totalRecordedTime += _recordDuration;
    recordingPartsTimeList.add(segmentDuration);
    recordedPart!.endTime = DateTime.now();
    logger.i('Recorded part end time: ${recordedPart!.endTime}');
    if (_locService.lastKnownPosition == null) {
      await _locService.getCurrentLocation();
    }
    recordedPart!.gpsLongitudeEnd = _locService.lastKnownPosition?.longitude;
    recordedPart!.gpsLatitudeEnd = _locService.lastKnownPosition?.latitude;
    Uint8List data = await File(filepath).readAsBytes();
    final dataWithHeader = createWavHeader(data.length, sampleRate, bitRate) + data;
    recordedPart!.dataBase64 = base64Encode(dataWithHeader);
    await File(filepath).delete();
    File newFile = await File(filepath).create();
    await newFile.writeAsBytes(dataWithHeader);
    recordingPartsList.add(recordedPart!);
    setState(() {
      _recordDuration = Duration.zero;
      _recordState = RecordState.pause; // show resume button
    });
  }

  Future<void> _resume() async {
    var path = await _getPath();
    setState(() {
      filepath = path;
      _recordState = RecordState.record; // back to recording
    });
    _elapsedTimer.reset();
    _elapsedTimer.start();
    segmentPaths.add(path);
    const encoder = AudioEncoder.pcm16bits;
    if (!await _isEncoderSupported(encoder)) return;
    final config = RecordConfig(
      encoder: encoder,
      numChannels: 1,
      sampleRate: sampleRate,
      bitRate: bitRate,
    );
    recordStream(_audioRecorder, config, filepath);
    // Start a new segment.
    recordedPart = RecordingPartUnready(
      dataBase64: null,
      gpsLongitudeStart: _locService.lastKnownPosition?.longitude,
      gpsLatitudeStart: _locService.lastKnownPosition?.latitude,
      startTime: DateTime.now(),
    );
    logger.i('New segment start time: ${recordedPart!.startTime}');
    if (recordedPart!.gpsLongitudeStart == null ||
        recordedPart!.gpsLatitudeStart == null) {
      await _locService.getCurrentLocation();
      recordedPart!.gpsLongitudeStart = _locService.lastKnownPosition?.longitude;
      recordedPart!.gpsLatitudeStart = _locService.lastKnownPosition?.latitude;
    }
  }

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);
    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');
      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${e.name}');
        }
      }
    }
    return isSupported;
  }

  @override
  void dispose() {
    _elapsedTimer.dispose();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    _locationSub?.cancel();
    super.dispose();
  }
}