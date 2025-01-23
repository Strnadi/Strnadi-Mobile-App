import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:record/record.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';
import 'package:strnadi/recording/recorderBtn.dart';

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

  var _isRecording = false;

  void _toggleRecording() async {
      if (recorderController.isRecording) {
        setState(() {
          _isRecording = false;
          recorderController.pause();
        });
      } else {
        if (recorderController.hasPermission) {
          setState(() {
            _isRecording = true;
            recorderController.record();
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        recorderController.pause();
                        // need to log the pauses
                      });
                    },
                    child: Text('Pause'),
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
                        _isRecording ? Icons.pause : Icons.mic,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}