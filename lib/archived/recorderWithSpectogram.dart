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
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/archived/editor.dart';
import 'package:strnadi/bottomBar.dart';
//import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
//import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:strnadi/database/databaseNew.dart';
import '../PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/exceptions.dart';

final logger = Logger();

/// A helper to show an AlertDialog with a message.
void _showMessage(BuildContext context, String message) {
  if (!isContextMounted(context)) return;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Notification'),
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

/// A helper to check if a BuildContext is still mounted.
bool isContextMounted(BuildContext context) {
  return ModalRoute.of(context)?.isCurrent ?? true;
}

/*
/// A data class for recording parts (here we also store the file path for each segment).
class RecordingParts {
  String? path;
  double longitude;
  double latitude;

  RecordingParts({
    required this.path,
    required this.longitude,
    required this.latitude,
  });
}
 */

/// RecorderWithSpectogram now implements manual segmentation:
/// • When the user taps the record button while not recording, we start a new segment.
/// • When the user taps while recording, we stop the current segment (simulate “pause”) and record its metadata.
/// • When the user presses Stop, if a segment is running we stop it and then merge all segments into one WAV file.
class RecorderWithSpectogram extends StatefulWidget {
  const RecorderWithSpectogram({Key? key}) : super(key: key);

  @override
  _RecorderWithSpectogramState createState() => _RecorderWithSpectogramState();
}

class _RecorderWithSpectogramState extends State<RecorderWithSpectogram> {
  // Lists to store timestamps and geolocation info for each segment.
  final recordingPartsTimeList = <int>[];
  final recordingPartsList = List<RecordingPartUnready>.empty(growable: true);

  // overallStartTime is the time when the very first segment started.
  DateTime? overallStartTime;
  // segmentStartTime is updated each time a new segment starts.
  DateTime? segmentStartTime;

  // This will hold the merged recording file path.
  String? recordedFilePath;
  // The current location.
  late LocationService locationService;
  //LatLng? currentPosition;

  // List to keep file paths for all segments.
  final List<String> segmentPaths = [];

  // Create an instance of our AudioRecorder (wrapping the record package).
  final _recorder = AudioRecorder();

  // These booleans control the UI state.
  bool _isRecording = false;
  bool _isRecordingPaused = false;

  // NEW: Live timer variables.
  double _recordDuration = 0; // elapsed time in seconds for the current segment
  Timer? _timer;

  RecordingPartUnready? recorded;

  @override
  void initState(){
    locationService = LocationService();

    locationService.checkLocationWorking().then((_){

    },onError: (e){
      if(e is LocationException){
        if(e.enabled){
          _showMessage(context, "Please enable location services");
        }
        else if(e.permission){
          _showMessage(context, "Please enable access location services");
        }
      }
      else {
        _showMessage(context, "Error retrieving location: $e");
      }
      Sentry.captureException(e);
    });

    super.initState();
  }

  /// Starts or pauses recording. When starting a new segment, we also start a live timer.
  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        // Stop the current segment.
        _timer?.cancel();
        final path = await _recorder.stop();
        segmentPaths.add(path!);
        recorded!.gpsLatitudeEnd = locationService.lastKnownPosition?.latitude;
        recorded!.gpsLongitudeEnd = locationService.lastKnownPosition?.longitude;
        recorded!.endTime = DateTime.now();
        recordingPartsList.add(recorded!);
        if (overallStartTime != null) {
          recordingPartsTimeList.add(DateTime.now().difference(overallStartTime!).inMilliseconds);
        }
        if (isContextMounted(context)) {
          setState(() {
            _isRecording = false;
            _isRecordingPaused = true;
          });
        }
      } else {
        // Start a new segment.
        bool hasPermission = await _recorder.hasPermission();
        if (!hasPermission) {
          if (isContextMounted(context)) {
            _showMessage(context, "Recording permission not granted");
          }
          logger.w("Recording permissions are denied");
          return;
        }
        // Mark overall start time if this is the first segment.
        if (overallStartTime == null) {
          overallStartTime = DateTime.now();
          segmentStartTime = overallStartTime;
        } else {
          segmentStartTime = DateTime.now();
        }
        Directory appDocDir = await getApplicationDocumentsDirectory();
        String filePath = '${appDocDir.path}/recording_segment_${DateTime.now().millisecondsSinceEpoch}.wav';
        final config = RecordConfig(encoder: AudioEncoder.wav, bitRate: 128000);

        recorded = RecordingPartUnready(startTime: segmentStartTime!, gpsLatitudeStart: locationService.lastKnownPosition?.latitude, gpsLongitudeStart: locationService.lastKnownPosition?.longitude);
        await _recorder.start(config, path: filePath);
        // Start the live timer.
        _startTimer();
        if (isContextMounted(context)) {
          setState(() {
            _isRecording = true;
            _isRecordingPaused = false;
            _recordDuration = 0; // Reset for the new segment.
          });
        }
      }
    } catch (e, stackTrace) {
      logger.e("An error has eccured $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      if (isContextMounted(context)) {
        _showMessage(context, "Error during recording: $e");
      }
    }
  }

  /// Stop recording completely, merge segments, and navigate to the Spectogram screen.
  Future<void> _stopRecording() async {
    try {
      // If a segment is currently recording, finish it.
      if (_isRecording && overallStartTime != null) {
        _timer?.cancel();
        final path = await _recorder.stop();
        segmentPaths.add(path!);

        if(recorded!.gpsLongitudeStart == null){

          recorded!.gpsLongitudeStart = locationService.lastKnownPosition?.longitude;
        }
        if(recorded!.gpsLatitudeStart == null) {
          recorded!.gpsLatitudeStart = locationService.lastKnownPosition?.latitude;
        }


        recorded!.gpsLatitudeEnd = locationService.lastKnownPosition?.latitude;
        recorded!.gpsLongitudeEnd = locationService.lastKnownPosition?.longitude;
        recorded!.endTime = DateTime.now();
        recordingPartsList.add(recorded!);

        recordingPartsTimeList.add(DateTime.now().difference(overallStartTime!).inMilliseconds);
      }

      // Merge segments if needed.
      String finalFilePath;
      if (segmentPaths.length == 1) {
        finalFilePath = segmentPaths.first;
      } else {
        Directory appDocDir = await getApplicationDocumentsDirectory();
        finalFilePath = '${appDocDir.path}/recording_merged_${DateTime.now().millisecondsSinceEpoch}.wav';
        finalFilePath = await mergeWavFiles(segmentPaths, finalFilePath);
      }

      if (isContextMounted(context)) {
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
          recordedFilePath = finalFilePath;
        });
      }

      // Navigate to the Spectogram screen.
      if (recordedFilePath != null && overallStartTime != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Spectogram(
              audioFilePath: recordedFilePath!,
              currentPosition: locationService.lastKnownPosition,
              recParts: recordingPartsList,
              recTimeStop: recordingPartsTimeList,
              StartTime: overallStartTime!,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      logger.e("An error has eccured $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      if (isContextMounted(context)) {
        _showMessage(context, "Error stopping recording: $e");
      }
    }
  }

  /// Starts a timer that updates _recordDuration every 100ms.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (Timer t) {
      setState(() {
        _recordDuration += 0.1;
      });
    });
  }

  /// Format a duration (in seconds) into MM:SS.
  String _formatTime(double seconds) {
    int s = seconds.floor();
    int m = s ~/ 60;
    int sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Recorder',
      content: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Display the live timer above the status.
            Text(
              "Time: ${_formatTime(_recordDuration)}",
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            // Display recording status.
            Container(
              width: 300,
              height: 300,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
              ),
              child: Text(
                _isRecording ? "Recording..." : "Not Recording",
                style: const TextStyle(fontSize: 24),
              ),
            ),
            // Record/Pause-Resume button.
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 100,
              height: 100,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(
                  color: Colors.white,
                  width: 3,
                ),
              ),
              child: IconButton(
                onPressed: _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.pause : (_isRecordingPaused ? Icons.play_arrow : Icons.mic),
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            // Stop button, enabled if recording or paused.
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: (_isRecording || _isRecordingPaused) ? _stopRecording : null,
              child: const Text(
                'Stop',
                style: TextStyle(
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Merges multiple WAV segments into one file.
  Future<String> mergeWavFiles(List<String> segmentPaths, String outputPath) async {
    if (segmentPaths.isEmpty) return "";

    Directory appDocDir = await getApplicationDocumentsDirectory();
    String fileListPath = '${appDocDir.path}/filelist.txt';
    File fileList = File(fileListPath);

    String fileListContent = segmentPaths.map((path) => "file '$path'").join('\n');
    await fileList.writeAsString(fileListContent);

    String command = "-f concat -safe 0 -i \"$fileListPath\" -c copy \"$outputPath\"";
    //final session = await FFmpegKit.execute(command);
    //final returnCode = await session.getReturnCode();

    await fileList.delete();

    // if (ReturnCode.isSuccess(returnCode)) {
    //   return outputPath;
    // } else {
    //   throw Exception("FFmpeg merge failed with return code: ${returnCode?.getValue()}");
    // }
    return '';
  }
}
