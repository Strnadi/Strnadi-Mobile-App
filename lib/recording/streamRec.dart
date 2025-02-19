import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:record/record.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/recording/platform/audio_recorder_io.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';

class LiveRec extends StatefulWidget {

  const LiveRec({super.key});

  @override
  State<LiveRec> createState() => _LiveRecState();
}

class _LiveRecState extends State<LiveRec> with AudioRecorderMixin {
  int _recordDuration = 0;
  Timer? _timer;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Amplitude? _amplitude;


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

    if (path != null) {
      onStop(path);
      Navigator.push(context, MaterialPageRoute(builder: (context) => RecordingForm(filepath: path, StartTime: overallStartTime!, currentPosition: currentPosition, recordingParts: recordingPartsList, recordingPartsTimeList: recordingPartsTimeList)));
    }
  }

  Future<void> _start() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        const config = RecordConfig(encoder: encoder, numChannels: 1);

        // Record to file
        //await recordFile(_audioRecorder, config);

        // Record to stream
        await recordStream(_audioRecorder, config);

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
    return MaterialApp(
      home: Scaffold(
        body: Column(
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
        color: color,
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

  void onStop(String path) {
    setState(() {
      recordedFilePath = path;
    });
  }
}