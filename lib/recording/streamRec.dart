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
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
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

  late AudioRecorder _audioRecorder;
  String? _filepath;
  int sampleRate = 48000;
  int bitDepth = 16;
  int get bitRate => sampleRate * bitDepth;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    counter = 0;
    logger.i("Foreground task started at \$timestamp");
    _audioRecorder = AudioRecorder();
    if (!await _audioRecorder.hasPermission()) {
      await _audioRecorder.hasPermission();
    }
    final dir = await getApplicationDocumentsDirectory();
    _filepath = p.join(dir.path, 'audio_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _audioRecorder.start(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: sampleRate,
        bitRate: bitRate,
      ),
      path: _filepath!,
    );
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
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _audioRecorder.stop();
    logger.i("Foreground task destroyed at \$timestamp (isTimeout: \$isTimeout)");
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
  DateTime? _lastRouteUpdateTime;
  final List<String> segmentPaths = [];
  StreamSubscription? _locationSub;
  late LocationService _locService;
  bool recording = false;
  bool _hasMicPermission = false;

  bool _isProcessingRecording = false;

  @override
  void initState() {
    super.initState();
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
    try {
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
      // Check and request location permission before recording
      LocationPermission locationPerm = await Geolocator.checkPermission();
      if (locationPerm != LocationPermission.whileInUse && locationPerm != LocationPermission.always) {
        locationPerm = await Geolocator.requestPermission();
      }
      if (locationPerm != LocationPermission.whileInUse && locationPerm != LocationPermission.always) {
        _showMessage(context, 'Pro zahájení nahrávání musíte povolit přístup k poloze');
        return;
      }
      if (_recordState == RecordState.record) {
        _pause();
      } else if (_recordState == RecordState.pause) {
        _resume();
      } else {
        _start();
      }
    } catch (e, stackTrace) {
      logger.e("Error toggling recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    } finally {
      setState(() {
        _isProcessingRecording = false;
      });
    }
  }

  Future<void> _stop() async {
    // Ensure we have a valid file path; if empty, pick the most recent WAV in documents
    if (filepath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.wav'))
          .cast<File>()
          .toList();
      if (files.isEmpty) {
        _showMessage(context, 'Nenalezena žádná nahrávka k uložení');
        return;
      }
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      filepath = files.first.path;
    }
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
    // Always fetch the latest location for segment end
          try {
            final loc = await _locService.getCurrentLocation();
            recordedPart!.gpsLatitudeEnd = loc.latitude;
            recordedPart!.gpsLongitudeEnd = loc.longitude;
          } catch (e, stackTrace) {
            logger.e('Error fetching location on stop: $e', error: e, stackTrace: stackTrace);
          }
      Uint8List data = await File(filepath).readAsBytes();
      final dataWithHeader =
          createWavHeader(data.length, sampleRate, bitRate) + data;

      await File(filepath).delete();
      File newFile = await File(filepath).create();
      await newFile.writeAsBytes(dataWithHeader);
      if (recordedPart != null) {
        recordedPart!.path = filepath;
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

    // Determine button colors, border, and shadow based on recording state.
    IconData iconData = Icons.mic;
    Color fillColor = primaryRed;
    Color iconColor = Colors.white;
    Border? border;
    List<BoxShadow> boxShadows = [];

    if (_recordState == RecordState.stop) {
      // Stop state: filled red circle with white mic icon.
      iconData = Icons.mic;
      fillColor = primaryRed;
      iconColor = Colors.white;
      border = null;
      boxShadows = [];
    } else if (_recordState == RecordState.record) {
      // Recording (pause button visible): white circle, thicker red border, red icon + glow.
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
      // Paused (play button visible): white circle, thicker red border, red icon + glow.
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

    // Create the scaffold widget.
    final scaffoldWidget = Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = MediaQuery.of(context).size.height;
          final content = ConstrainedBox(
            constraints: BoxConstraints(minHeight: screenHeight),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenHeight = MediaQuery.of(context).size.height;
                      final imageHeight = screenHeight * 0.25; // 25% of screen height
                      return SizedBox(
                        height: imageHeight,
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
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  // Recording button with vertical padding.
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Opacity(
                      opacity: _hasMicPermission ? 1.0 : 0.5,
                      child: AbsorbPointer(
                        absorbing: _isProcessingRecording,
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
                  // Timer with a round border (red when recording, gray otherwise).
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _recordState == RecordState.record ? primaryRed : Colors.grey,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
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
                  // Status text.
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
                  const SizedBox(height: 10),
                  // Finish button visible when recording or paused.
                  if (_recordState == RecordState.record || _recordState == RecordState.pause)
                    Semantics(
                      label: "Finish and continue",
                      button: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
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
                  // Discard recording button.
                  if (_recordState == RecordState.record || _recordState == RecordState.pause)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
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
          );
          return content;
        },
      ),
      bottomNavigationBar: ReusableBottomAppBar(
          currentPage: BottomBarItem.recorder, changeConfirmation: changeConfirmation),
    );

    // Return the PopScope widget with an onPopInvokedWithResult callback that completes without returning any widget.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        _discardRecording();
      },
      child: scaffoldWidget,
    );
  }

  Future<bool> changeConfirmation() async {
    if (_recordState == RecordState.record || _recordState == RecordState.pause) {
      bool discard = false;
      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Potvrdit'),
            content: const Text('Opravdu chcete opustit nahrávání?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Zpět k nahrávání'),
              ),
              TextButton(
                onPressed: () {
                  clear();
                  discard = true;
                  Navigator.of(context).pop();
                },
                child: const Text('Opustit nahrávání'),
              ),
            ],
          );
        },
      );
      return discard;
    }
    return true;
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

  void _discardRecording() async{
    _pause();
    bool discard = await changeConfirmation();
    if(discard){
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
          settings: const RouteSettings(name: '/Recorder'),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    }
  }

  Future<void> _start() async {
    // Request location permission for recording
    await getLocationPermission(context);
    // Initialize location service and start listening for location updates
    _locService = LocationService();
    _locService.init();
    _locService.getCurrentLocation().then((loc) {
      setState(() {
        currentPosition = loc;
        _liveRoute.add(loc);
      });
    }).catchError((e, stackTrace) {
      logger.e('Error fetching initial location: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    });
    _locationSub = _locService.positionStream.listen((position) {
      final now = DateTime.now();
      if (_lastRouteUpdateTime == null ||
          now.difference(_lastRouteUpdateTime!) >= Duration(seconds: 5)) {
        setState(() {
          currentPosition = LatLng(position.latitude, position.longitude);
          _liveRoute.add(LatLng(position.latitude, position.longitude));
          _lastRouteUpdateTime = now;
        });
      }
    });
    final running = await FlutterForegroundTask.isRunningService;
    if (!running) {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Strnadi',
        notificationText: 'Aplikace Strnadi nahrává',
        callback: startRecordingCallback,
        serviceTypes: [ForegroundServiceTypes.microphone],
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Strnadi',
        notificationText: 'Aplikace Strnadi nahrává',
      );
    }
    try {
      logger.i('Started recording');
      // Prepare new file path and start local AudioRecorder
      filepath = await _getPath();
      segmentPaths.add(filepath);
      await WakelockPlus.enable();

      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: sampleRate,
        bitRate: bitRate,
      );
      await _audioRecorder.start(config, path: filepath);

      if (_locService.lastKnownPosition == null) {
        await _locService.getCurrentLocation();
      }
      overallStartTime = DateTime.now();
      logger.i('Overall start time: $overallStartTime');
      // Create a new segment metadata object
      recordedPart = RecordingPartUnready(
        path: null,
        gpsLongitudeStart: _locService.lastKnownPosition?.longitude,
        gpsLatitudeStart: _locService.lastKnownPosition?.latitude,
        startTime: DateTime.now(),
      );
      logger.i('Recorded part start time: ${recordedPart!.startTime}');
      _elapsedTimer.reset();
      _elapsedTimer.start();
      setState(() {
        recording = true;
        _recordState = RecordState.record;
      });
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
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Strnadi',
      notificationText: 'Nahrávání pozastaveno',
    );
    int segmentDuration = _recordDuration.inSeconds;
    _totalRecordedTime += _recordDuration;
    recordingPartsTimeList.add(segmentDuration);
    recordedPart!.endTime = DateTime.now();
    logger.i('Recorded part end time: ${recordedPart!.endTime}');
    // Always fetch the latest location for segment end
        try {
          final loc = await _locService.getCurrentLocation();
          recordedPart!.gpsLongitudeEnd = loc.longitude;
          recordedPart!.gpsLatitudeEnd = loc.latitude;
        } catch (e, stackTrace) {
          logger.e('Error fetching location on pause: $e', error: e, stackTrace: stackTrace);
        }
    Uint8List data = await File(filepath).readAsBytes();
    final dataWithHeader = createWavHeader(data.length, sampleRate, bitRate) + data;
    await File(filepath).delete();
    File newFile = await File(filepath).create();
    await newFile.writeAsBytes(dataWithHeader);
    recordedPart!.path = filepath;
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
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Strnadi',
      notificationText: 'Aplikace Strnadi nahrává',
    );
    segmentPaths.add(path);
    await WakelockPlus.enable();
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: 1,
      sampleRate: sampleRate,
      bitRate: bitRate,
    );
    await _audioRecorder.start(config, path: filepath);
    // Start a new segment.
    recordedPart = RecordingPartUnready(
      path: null,
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