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