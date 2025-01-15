import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:record/record.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';

String? recordedFilePath;
final RecorderController recorderController = RecorderController();

class RecorderWithSpectogram extends StatefulWidget {
  const RecorderWithSpectogram({Key? key}) : super(key: key);

  @override
  _RecorderWithSpectogramState createState() => _RecorderWithSpectogramState();
}

class _RecorderWithSpectogramState extends State<RecorderWithSpectogram> {
  @override
  void initState() {
    super.initState();
    recorderController.checkPermission();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Recorder with Spectogram',
      content: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  if (recorderController.hasPermission) {
                    recorderController.record(); // By default saves file with datetime as name.
                  }
                },
                child: Text('Record'),
              ),
              ElevatedButton(
                onPressed: () {
                  recorderController.pause();
                },
                child: Text('Pause'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (recorderController.isRecording) {
                    recordedFilePath = await recorderController.stop();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => Spectogram(audioFilePath: recordedFilePath!)));
                  }
                },
                child: Text('Stop'),
              ),
              AudioWaveforms(
                size: Size(300, 50),
                recorderController: recorderController,
              ),
            ],
          ),
        ),
      ),
    );
  }
}