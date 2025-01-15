import 'package:flutter/material.dart';
import 'package:strnadi/AudioEditor/audioRecorder.dart';
import 'package:strnadi/bottomBar.dart';

class editor extends StatelessWidget {
  final String audioFilePath;

  const editor({
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