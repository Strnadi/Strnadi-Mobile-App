/*
 * streamRec.dart
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:record/record.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/archived/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../bottomBar.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/recording/waw.dart'; // Contains createWavHeader & concatWavFiles

final logger = Logger();

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
      title: const Text('Info'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK')),
      ],
    ),
  );
}

void exitApp(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Info'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('OK')),
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
  int sampleRate = 44100;
  int bitRate = calcBitRate(44100, 16);
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

  @override
  void initState() {
    super.initState();
    getLocationPermission(context);
    _audioRecorder = AudioRecorder();
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    _amplitudeSub = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
      // Optionally update spectrogram data.
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

  void _toggleRecording() {
    if (_recordState == RecordState.record) {
      _pause();
    } else if (_recordState == RecordState.pause) {
      _resume();
    } else {
      _start();
    }
  }

  Future<void> _stop() async {
    if (_recordState == RecordState.record) {
      try {
        await _audioRecorder.stop();
        _elapsedTimer.pause();
        setState(() {
          recording = false;
        });
      } catch (e, stackTrace) {
        logger.e("Error stopping recorder: $e", error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        return;
      }
      int segmentDuration = _recordDuration.inSeconds;
      _totalRecordedTime += _recordDuration;
      recordingPartsTimeList.add(segmentDuration);

      // Set end time for current segment.
      recordedPart!.endTime = DateTime.now();
      logger.i('Segment end time: ${recordedPart!.endTime}');

      // Process the recorded file.
      Uint8List data = await File(filepath).readAsBytes();
      final dataWithHeader = createWavHeader(data.length, sampleRate, bitRate) + data;
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
      logger.e("Error concatenating files: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return;
    }
    if (overallStartTime == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Recording Form"), automaticallyImplyLeading: false,),
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
    String path = p.join(dir.path, 'audio_${DateTime.now().millisecondsSinceEpoch}.wav');
    logger.i('Generated file path: $path');
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final halfScreen = MediaQuery.of(context).size.width * 0.15;
    final totalTime = _totalRecordedTime + _recordDuration;
    return ScaffoldWithBottomBar(
      appBarTitle: "Nahrávání",
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Expanded(
            child: Container(
              color: Colors.grey,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            _formatTime(totalTime),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black),
              child: Icon(
                _recordState == RecordState.record ? Icons.pause : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text("Stisknutím zahájíte nebo pozastavíte nahrávání", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          if (recording)
            Padding(
              padding: EdgeInsets.only(left: halfScreen),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _stop,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black, width: 2),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Ukončit nahrávání", style: TextStyle(color: Colors.black)),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.black),
                    onPressed: _discardRecording,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
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
          title: const Text('Confirm Discard'),
          content: const Text('Are you sure you want to discard the current recording?'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                // todo not discording
                clear();
                Navigator.of(context).pop();
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LiveRec()));
              },
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _start() async {
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
        // Create a new segment with a fresh start time.
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
        });
      }
      else {
        exitApp(context, 'Pro správné fungování aplikace je potřeba povolit mikrofon');
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

  Future<String> recordStream(AudioRecorder recorder, RecordConfig config, String filepath) async {
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
    // Set the end time for this segment.
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
    });
  }

  Future<void> _resume() async {
    var path = await _getPath();
    setState(() {
      filepath = path;
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
    // Start a new segment with a fresh start time.
    recordedPart = RecordingPartUnready(
      dataBase64: null,
      gpsLongitudeStart: _locService.lastKnownPosition?.longitude,
      gpsLatitudeStart: _locService.lastKnownPosition?.latitude,
      startTime: DateTime.now(),
    );
    logger.i('New segment start time: ${recordedPart!.startTime}');
    if (recordedPart!.gpsLongitudeStart == null || recordedPart!.gpsLatitudeStart == null) {
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