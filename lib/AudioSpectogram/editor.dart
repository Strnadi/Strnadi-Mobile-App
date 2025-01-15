import 'package:flutter/material.dart';
import 'package:strnadi/AudioSpectogram/audioRecorder.dart';
import 'package:strnadi/bottomBar.dart';

class Spectogram extends StatelessWidget {
  final String audioFilePath;

  const Spectogram({
    Key? key,
    required this.audioFilePath,
  }) : super(key: key);


  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Editor',
      content: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: SpectrogramViewer(audioFilePath: audioFilePath),
            ),
          ],
        ),
      ),
    );
  }
}