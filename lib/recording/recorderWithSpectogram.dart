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

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import '../PostRecordingForm/RecordingForm.dart';

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

  // Create an instance of our AudioRecorder (wrapping the record package).
  final _recorder = AudioRecorder();

  // These booleans control the UI state.
  // _isRecording == true means a segment is currently recording.
  // _isRecordingPaused == true means recording is paused (i.e. a segment has ended, but the user may resume a new one).
  bool _isRecording = false;
  bool _isRecordingPaused = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  /// Get current location with error/permission handling.
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(context, "Please enable location services");
        logger.w("Location services are not enabled");
        if (isContextMounted(context)) {
          setState(() {
            currentPosition = const LatLng(50.1, 14.4);
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w("Location permissions are denied");
          if (isContextMounted(context)) {
            setState(() {
              currentPosition = const LatLng(50.1, 14.4);
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.w("Location permissions are permanently denied");
        if (isContextMounted(context)) {
          setState(() {
            currentPosition = const LatLng(50.1, 14.4);
          });
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      if (isContextMounted(context)) {
        setState(() {
          currentPosition = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      logger.e(e);
      if (isContextMounted(context)) {
        _showMessage(context, "Error retrieving location: $e");
      }
    }
  }

  /// Instead of using pause/resume (which is problematic with WAV),
  /// we simulate segmentation:
  /// • If a segment is running (_isRecording true), then we stop it (simulate pause).
  /// • If no segment is running, we start a new one.
  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        // Stop the current segment.
        final path = await _recorder.stop();
        segmentPaths.add(path!);
        recordingPartsList.add(RecordingParts(
          path: path,
          longitude: currentPosition?.longitude ?? 14.4,
          latitude: currentPosition?.latitude ?? 50.1,
        ));
        // Record the overall elapsed time from the very first segment start.
        if (overallStartTime != null) {
          recordingPartsTimeList.add(
              DateTime.now().difference(overallStartTime!).inMilliseconds);
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
        // If this is the first segment, mark overallStartTime.
        if (overallStartTime == null) {
          overallStartTime = DateTime.now();
          segmentStartTime = overallStartTime;
        }
        else {
          // Mark the start time of this segment.
          segmentStartTime = DateTime.now();
        }
        Directory appDocDir = await getApplicationDocumentsDirectory();
        String filePath =
            '${appDocDir.path}/recording_segment_${DateTime.now().millisecondsSinceEpoch}.wav';
        // Start recording the new segment.
        final config =
        RecordConfig(encoder: AudioEncoder.wav, bitRate: 128000);
        await _recorder.start(config, path: filePath);
        if (isContextMounted(context)) {
          setState(() {
            _isRecording = true;
            _isRecordingPaused = false;
          });
        }
      }
    } catch (e) {
      logger.e(e);
      if (isContextMounted(context)) {
        _showMessage(context, "Error during recording: $e");
      }
    }
  }

  /// When the user presses Stop, if a segment is still running we stop it,
  /// then merge all the segments into one WAV file.
  Future<void> _stopRecording() async {
    try {
      // If currently recording a segment, finish it.
      if (_isRecording && overallStartTime != null) {
        final path = await _recorder.stop();
        segmentPaths.add(path!);
        recordingPartsList.add(RecordingParts(
          path: path,
          longitude: currentPosition?.longitude ?? 14.4,
          latitude: currentPosition?.latitude ?? 50.1,
        ));
        recordingPartsTimeList.add(
            DateTime.now().difference(overallStartTime!).inMilliseconds);
      }

      // Merge segments if there is more than one.
      String finalFilePath;
      if (segmentPaths.length == 1) {
        finalFilePath = segmentPaths.first;
      } else {
        Directory appDocDir = await getApplicationDocumentsDirectory();
        finalFilePath =
        '${appDocDir.path}/recording_merged_${DateTime.now().millisecondsSinceEpoch}.wav';
        finalFilePath = await mergeWavFiles(segmentPaths, finalFilePath);
      }

      if (isContextMounted(context)) {
        setState(() {
          _isRecording = false;
          _isRecordingPaused = false;
          recordedFilePath = finalFilePath;
        });
      }

      // Navigate to the Spectogram screen with the final file and metadata.
      if (recordedFilePath != null && overallStartTime != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Spectogram(
              audioFilePath: recordedFilePath!,
              currentPosition: currentPosition,
              recParts: recordingPartsList,
              recTimeStop: recordingPartsTimeList,
              StartTime: overallStartTime!,
            ),
          ),
        );
      }
    } catch (e) {
      logger.e(e);
      if (isContextMounted(context)) {
        _showMessage(context, "Error stopping recording: $e");
      }
    }
  }

  /// Merges multiple WAV files (segments) into a single WAV file.
  /// This basic implementation assumes each segment has a 44-byte header
  /// and uses PCM encoding.
  Future<String> mergeWavFiles(List<String> segmentPaths, String outputPath) async {
    if (segmentPaths.isEmpty) return "";

    // Get the application documents directory.
    Directory appDocDir = await getApplicationDocumentsDirectory();
    String fileListPath = '${appDocDir.path}/filelist.txt';
    File fileList = File(fileListPath);

    // Build the file list content in the format:
    // file '/path/to/segment1.wav'
    // file '/path/to/segment2.wav'
    String fileListContent = segmentPaths.map((path) => "file '$path'").join('\n');
    await fileList.writeAsString(fileListContent);

    // Construct the FFmpeg command.
    // Quoting file paths to handle spaces in directory/file names.
    String command = "-f concat -safe 0 -i \"$fileListPath\" -c copy \"$outputPath\"";

    // Execute the FFmpeg command.
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    // Clean up the temporary file list.
    await fileList.delete();

    if (ReturnCode.isSuccess(returnCode)) {
      return outputPath;
    } else {
      throw Exception("FFmpeg merge failed with return code: ${returnCode?.getValue()}");
    }
  }

  @override
  void dispose() {
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
                  _isRecording
                      ? Icons.pause
                      : (_isRecordingPaused ? Icons.play_arrow : Icons.mic),
                  size: 50,
                  color: Colors.white,
                ),
              ),
            ),
            // Stop button, enabled if either recording or paused.
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: (_isRecording || _isRecordingPaused)
                  ? _stopRecording
                  : null,
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
}