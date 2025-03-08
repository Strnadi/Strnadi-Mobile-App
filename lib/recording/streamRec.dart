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
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:record/record.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../bottomBar.dart';
import 'package:strnadi/locationService.dart'; // Import our location service

final logger = Logger();

class LiveRec extends StatefulWidget {
  const LiveRec({super.key});

  @override
  State<LiveRec> createState() => _LiveRecState();
}

int calcBitRate(int sampleRate, int bitDepth) {
  return sampleRate * bitDepth;
}

class _LiveRecState extends State<LiveRec> {
  // _recordDuration holds the duration of the current (running) segment.
  double _recordDuration = 0;
  // _totalRecordedTime holds the cumulative duration of all segments that have been paused.
  double _totalRecordedTime = 0;

  var filepath = "";
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;

  List<List<double>> spectrogramData = [];

  int sampleRate = 44100;
  int bitRate = calcBitRate(44100, 16);

  final recordingPartsTimeList = <int>[];
  final recordingPartsList = <RecordingParts>[];

  // overallStartTime is the time when the very first segment started.
  DateTime? overallStartTime;
  // segmentStartTime is updated each time a new segment starts.
  DateTime? segmentStartTime;

  // This will hold the merged recording file path.
  String? recordedFilePath;

  // The current location.
  LatLng? currentPosition;

  // List to keep file paths for all segments.
  final List<String> segmentPaths = [];

  // New: Subscription to the location stream.
  StreamSubscription? _locationSub;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
      // Optionally, update spectrogramData here.
    });

    // Subscribe to our centralized location stream.
    _locationSub = LocationService().positionStream.listen((position) {
      setState(() {
        currentPosition = LatLng(position.latitude, position.longitude);
      });
    });

    super.initState();
  }

  void _toggleRecording(){
    if (_recordState == RecordState.record) {
      _pause();
    } else if (_recordState == RecordState.pause) {
      _resume();
    } else {
      _start();
    }
  }

  /// Stop function: Add the final segment duration to the cumulative total,
  /// then pass the overall time and per-segment data to the RecordingForm.
  Future<void> _stop() async {
    // Add the current segment duration to total if any.
    int segmentDuration = _recordDuration.toInt();
    _totalRecordedTime += _recordDuration;
    recordingPartsTimeList.add(segmentDuration);

    recordingPartsList.add(
      RecordingParts(
        path: null,
        longitude: currentPosition?.longitude ?? 14.4,
        latitude: currentPosition?.latitude ?? 50.1,
      ),
    );

    try {
      await _audioRecorder.stop();
      await onStop(filepath);
    } catch (e) {
      logger.e("Error stopping recorder or processing file: $e");
      return;
    }

    if (overallStartTime == null) {
      return;
    }

    await onStop(filepath);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Recording Form")),
          body: RecordingForm(
            filepath: filepath,
            startTime: overallStartTime!,
            currentPosition: currentPosition,
            recordingParts: recordingPartsList,
            recordingPartsTimeList: recordingPartsTimeList,
          ),
        ),
      ),
    );
  }

  Future<String> _getPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(
      dir.path,
      'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Display total cumulative time: current segment + previous segments.
    int displayTime = (_totalRecordedTime + _recordDuration).toInt();
    return ScaffoldWithBottomBar(
      appBarTitle: "Nahrávání",
      content: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Expanded(
            child: Container(
              color: Colors.grey.shade300,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            _formatTime(displayTime),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black,
              ),
              child: Icon(
                _recordState == RecordState.record ? Icons.pause : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Stisknutím zahájíte nebo pozastavíte nahrávání",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          if (_recordState == RecordState.pause)
            ElevatedButton(
              onPressed: _stop,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Ukončit nahrávání"),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final config = RecordConfig(
          encoder: encoder,
          numChannels: 1,
          sampleRate: sampleRate,
          bitRate: bitRate,
        );

        filepath = await _getPath();
        var path = await recordStream(_audioRecorder, config, filepath);
        setState(() {
          filepath = path;
        });

        _recordDuration = 0;
        _totalRecordedTime = 0;
        _startTimer();
        overallStartTime = DateTime.now();

        recordingPartsList.add(RecordingParts(
          path: null,
          longitude: currentPosition?.longitude ?? 14.4,
          latitude: currentPosition?.latitude ?? 50.1,
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        //print(e);
      }
    }
  }

  String _formatTime(int duration) {
    final milliseconds = (duration % 10) * 10;
    final seconds = (duration ~/ 10) % 60;
    final minutes = (duration ~/ 600);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')},${milliseconds.toString().padLeft(2, '0')}';
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
        print('End of stream. File written to $filepath.');
        completer.complete(filepath);
      },
      onError: (error) {
        completer.completeError(error);
      },
    );

    return completer.future;
  }

  Future<void> _pause() async {
    _audioRecorder.pause();

    int segmentDuration = _recordDuration.toInt();
    _totalRecordedTime += _recordDuration;
    recordingPartsTimeList.add(segmentDuration);

    recordingPartsList.add(RecordingParts(
      path: null,
      longitude: currentPosition?.longitude ?? 14.4,
      latitude: currentPosition?.latitude ?? 50.1,
    ));

    _recordDuration = 0;
  }

  Future<void> _resume() => _audioRecorder.resume();

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);

    switch (recordState) {
      case RecordState.pause:
        _timer?.cancel();
        break;
      case RecordState.record:
        _startTimer();
        break;
      case RecordState.stop:
        _timer?.cancel();
        _recordDuration = 0;
        break;
    }
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
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  String _formatNumber(int number) {
    String numberStr = number.toString();
    if (number < 10) {
      numberStr = '0$numberStr';
    }
    return numberStr;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1), (Timer t) {
      setState(() => _recordDuration += 0.01);
    });
  }

  Future<void> onStop(String path) async {
    final _file = File(path);
    if (!await _file.exists()) {
      logger.e('File does not exist at path: $path');
      return;
    }
    Uint8List data = await _file.readAsBytes();

    Uint8List header = createHeader(data.length, sampleRate, bitRate);
    final file = header + data;
    await File(path).delete();
    final newFile = await File(path).create();
    await newFile.writeAsBytes(file);
    logger.i('Recording saved to: $path');
    setState(() {
      recordedFilePath = path;
    });
  }

  Uint8List createHeader(int dataSize, int sampleRate, int bitRate) {
    int channels = 1;
    int bitDepth = 16;
    int byteRate = sampleRate * channels * bitDepth ~/ 8;
    int blockAlign = channels * bitDepth ~/ 8;
    int chunkSize = 36 + dataSize;

    Uint8List header = Uint8List(44);
    ByteData bd = ByteData.sublistView(header);

    header.setRange(0, 4, [82, 73, 70, 70]);
    bd.setUint32(4, chunkSize, Endian.little);
    header.setRange(8, 12, [87, 65, 86, 69]);
    header.setRange(12, 16, [102, 109, 116, 32]);
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitDepth, Endian.little);
    header.setRange(36, 40, [100, 97, 116, 97]);
    bd.setUint32(40, dataSize, Endian.little);

    return header;
  }
}
