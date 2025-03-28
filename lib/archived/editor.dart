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
import 'package:latlong2/latlong.dart';
import 'package:strnadi/archived/audioRecorder.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/archived/recorderWithSpectogram.dart';

class Spectogram extends StatelessWidget {
  final String audioFilePath;
  final LatLng? currentPosition;
  final List<RecordingPartUnready> recParts;
  final List<int> recTimeStop;
  final DateTime StartTime;
  //final List<LatLng> route;

  const Spectogram(
      {Key? key,
      required this.StartTime,
      required this.audioFilePath,
      required this.currentPosition,
      required this.recParts,
      required this.recTimeStop,
      //required this.route
      })
      : super(key: key);


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Submit'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 300, // Specify a height for the spectrogram viewer
              child: SpectrogramViewer(audioFilePath: audioFilePath),
            ),
            RecordingForm(filepath: audioFilePath, currentPosition: currentPosition, recordingParts: recParts, recordingPartsTimeList: recTimeStop, startTime: StartTime, route: [],),
          ],
        ),
      ),
    );
  }
}
