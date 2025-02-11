/*
 * Copyright (C) 2024 [Your Name]
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
import 'package:strnadi/AudioSpectogram/audioRecorder.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/bottomBar.dart';

class Spectogram extends StatelessWidget {
  final String audioFilePath;
  final LatLng? currentPosition;

  const Spectogram({
    Key? key,
    required this.audioFilePath,
    required this.currentPosition,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Submit'),),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 300, // Specify a height for the spectrogram viewer
              child: SpectrogramViewer(audioFilePath: audioFilePath),
            ),
            RecordingForm(filepath: audioFilePath, currentPosition: currentPosition,),
          ],
        ),
      ),
    );
  }
}