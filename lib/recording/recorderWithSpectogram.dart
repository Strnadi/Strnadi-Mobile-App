/*
 * Copyright (C) 2024 Marian Pecqueur && Jan Drobílek
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

import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';

import '../PostRecordingForm/RecordingForm.dart';

final logger = Logger();

void _showMessage(String message) {
  var context;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Login'),
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

class RecordingParts {
  String? path;
  double longtitute;
  double latitude;

  RecordingParts({
    required this.path,
    required this.longtitute,
    required this.latitude,
  });
}

String? recordedFilePath;
LatLng? _currentPosition;
final RecorderController recorderController = RecorderController();

class RecorderWithSpectogram extends StatefulWidget {
  const RecorderWithSpectogram({super.key});

  @override
  _RecorderWithSpectogramState createState() => _RecorderWithSpectogramState();
}

class _RecorderWithSpectogramState extends State<RecorderWithSpectogram> {
  final recordingPartsTimeList = <int>[];
  final recordingPartsList = <RecordingParts>[];
  DateTime? StartTime = null;

  @override
  void initState() {
    super.initState();
    recorderController.checkPermission();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage("Please enable location services");
        logger.w("Location services are not enabled");
        print("Location services are not enabled");
        setState(() {
          _currentPosition = LatLng(50.1, 14.4);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w("Location permissions are denied");
          print("Location permissions are denied");
          setState(() {
            _currentPosition = LatLng(50.1, 14.4);
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.w("Location permissions are permanently denied");
        print("Location permissions are permanently denied");
        setState(() {
          _currentPosition = LatLng(50.1, 14.4);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      logger.e(e);
      print("Error retrieving location: $e");
    }
  }

  var _isRecording = false;
  var _isRecordingPaused = false;

  void _toggleRecording() async {
    if (recorderController.isRecording) {
      setState(() {
        _isRecording = false;
        recorderController.pause();

        recordingPartsList.add(RecordingParts(
            path: null,
            longtitute: _currentPosition!.longitude,
            latitude: _currentPosition!.latitude));

        // logging the stops
        recordingPartsTimeList
            .add(recorderController.recordedDuration.inMilliseconds);
        _isRecordingPaused = true;
      });
    } else {
      if (recorderController.hasPermission) {
        setState(() {
          StartTime = DateTime.now();
          _isRecording = true;
          recorderController.record();
          _isRecordingPaused = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Recorder',
      content: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              AudioWaveforms(
                size: Size(300, 300),
                recorderController: recorderController,
              ),
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
                child: MaterialButton(
                  enableFeedback: true,
                  onPressed: _toggleRecording,
                  child: Icon(
                    !_isRecording
                        ? _isRecordingPaused
                            ? Icons.pause
                            : Icons.mic
                        : Icons.play_arrow,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                onPressed: () async {
                  recordedFilePath = await recorderController.stop();
                  if (recordedFilePath != null) {
                    _isRecordingPaused = false;
                    _isRecording = false;
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => Spectogram(
                                  audioFilePath: recordedFilePath!,
                                  currentPosition: _currentPosition,
                                  recParts: recordingPartsList,
                                  recTimeStop: recordingPartsTimeList,
                                  StartTime: StartTime!,
                                )));
                  }
                },
                child: Text(
                  'Stop',
                  style: TextStyle(
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
