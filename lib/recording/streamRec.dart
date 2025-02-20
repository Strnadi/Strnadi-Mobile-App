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
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:record/record.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/recording/platform/audio_recorder_io.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


import '../bottomBar.dart';

final logger = Logger();


class LiveRec extends StatefulWidget {

  const LiveRec({super.key});

  @override
  State<LiveRec> createState() => _LiveRecState();
}

int calcBitRate(int sampleRate, int bitDepth) {
  return sampleRate * bitDepth;
}

class _LiveRecState extends State<LiveRec> with AudioRecorderMixin {
  int _recordDuration = 0;
  var filepath = "";
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Amplitude? _amplitude;

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

  @override
  void initState() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 300))
        .listen((amp) {
      setState(() => _amplitude = amp);
    });

    super.initState();
  }

  Future<void> _stop() async {

    recordingPartsList.add(
      RecordingParts(
        path: null,
        longitude: currentPosition?.longitude ?? 14.4,
        latitude: currentPosition?.latitude ?? 50.1,
      ),
    );

    recordingPartsTimeList.add(_recordDuration);

    final path = await _audioRecorder.stop();

    await onStop(filepath);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Recording Form")),
          body: RecordingForm(
            filepath: filepath,
            StartTime: overallStartTime!,
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

  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final config = RecordConfig(encoder: encoder, numChannels: 1, sampleRate: sampleRate, bitRate: bitRate);

        // Record to file
        //await recordFile(_audioRecorder, config);

        // Record to stream
        filepath = await _getPath();
        var path = await recordStream(_audioRecorder, config, filepath);
        setState(() {
          filepath = path;
        });

        _recordDuration = 0;

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

  Future<void> _pause() async {
    _audioRecorder.pause();

    recordingPartsTimeList.add(_recordDuration);

    recordingPartsList.add(RecordingParts(
      path: null,
      longitude: currentPosition?.longitude ?? 14.4,
      latitude: currentPosition?.latitude ?? 50.1,
    ));
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
    final isSupported = await _audioRecorder.isEncoderSupported(
      encoder,
    );

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
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: "Live Recorder",
      content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildRecordStopControl(),
                const SizedBox(width: 20),
                _buildPauseResumeControl(),
                const SizedBox(width: 20),
                _buildText(),
              ],
            ),
            if (_amplitude != null) ...[
              const SizedBox(height: 40),
              Text('Current: ${_amplitude?.current ?? 0.0}'),
              Text('Max: ${_amplitude?.max ?? 0.0}'),
            ],
          ],
        ),
      );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Widget _buildRecordStopControl() {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop) {
      icon = const Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withValues(alpha: 0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: Colors.red,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState != RecordState.stop) ? _stop() : _start();
          },
        ),
      ),
    );
  }

  Widget _buildPauseResumeControl() {
    if (_recordState == RecordState.stop) {
      return const SizedBox.shrink();
    }

    late Icon icon;
    late Color color;

    if (_recordState == RecordState.record) {
      icon = const Icon(Icons.pause, color: Colors.red, size: 30);
      color = Colors.red.withValues(alpha: 0.1);
    } else {
      final theme = Theme.of(context);
      icon = const Icon(Icons.play_arrow, color: Colors.red, size: 30);
      color = theme.primaryColor.withValues(alpha: 0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            (_recordState == RecordState.pause) ? _resume() : _pause();
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_recordState != RecordState.stop) {
      return _buildTimer();
    }

    return const Text("Waiting to record");
  }

  Widget _buildTimer() {
    final String minutes = _formatNumber(_recordDuration ~/ 60);
    final String seconds = _formatNumber(_recordDuration % 60);

    return Text(
      '$minutes : $seconds',
      style: const TextStyle(color: Colors.red),
    );
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

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() => _recordDuration++);
    });
  }

  Future<void> onStop(String path) async {

    Uint8List data = await File(path).readAsBytes();

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
    // For mono PCM audio with 16-bit depth:
    int channels = 1;
    int bitDepth = 16;
    int byteRate = sampleRate * channels * bitDepth ~/ 8;
    int blockAlign = channels * bitDepth ~/ 8;
    int chunkSize = 36 + dataSize; // Correct chunk size: file size minus 8 bytes

    // Create a 44-byte header buffer.
    Uint8List header = Uint8List(44);
    ByteData bd = ByteData.sublistView(header);

    // 'RIFF'
    header.setRange(0, 4, [82, 73, 70, 70]); // ASCII: R I F F
    bd.setUint32(4, chunkSize, Endian.little);
    // 'WAVE'
    header.setRange(8, 12, [87, 65, 86, 69]); // ASCII: W A V E
    // 'fmt ' (note the trailing space)
    header.setRange(12, 16, [102, 109, 116, 32]); // ASCII: f m t ' '
    // Format Chunk Size: 16 for PCM
    bd.setUint32(16, 16, Endian.little);
    // Audio Format: 1 (PCM)
    bd.setUint16(20, 1, Endian.little);
    // Number of channels: 1 (mono)
    bd.setUint16(22, channels, Endian.little);
    // Sample rate
    bd.setUint32(24, sampleRate, Endian.little);
    // Byte rate
    bd.setUint32(28, byteRate, Endian.little);
    // Block Align
    bd.setUint16(32, blockAlign, Endian.little);
    // Bits per sample
    bd.setUint16(34, bitDepth, Endian.little);
    // 'data'
    header.setRange(36, 40, [100, 97, 116, 97]); // ASCII: d a t a
    // Data Size (audio_data_len)
    bd.setUint32(40, dataSize, Endian.little);

    return header;
  }
}