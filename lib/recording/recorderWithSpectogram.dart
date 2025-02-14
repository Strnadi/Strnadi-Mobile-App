/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';

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

  @override
  void initState() {
    super.initState();
    recorderController.checkPermission();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are not enabled");
      return;
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Get the current location
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
  }

  var _isRecording = false;
  var _isRecordingPaused = false;

  void _toggleRecording() async {
    if (recorderController.isRecording) {
      setState(() {
        _isRecording = false;
        recorderController.pause();
        // logging the stops
        recordingPartsTimeList.add(recorderController.recordedDuration.inMilliseconds);
        _isRecordingPaused = true;
      });
    } else {
      if (recorderController.hasPermission) {
        setState(() {
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
                  if (recordedFilePath == null) {
                    return;
                  }
                  _isRecordingPaused = false;
                  _isRecording = false;
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              Spectogram(audioFilePath: recordedFilePath!, currentPosition: _currentPosition,)));
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
