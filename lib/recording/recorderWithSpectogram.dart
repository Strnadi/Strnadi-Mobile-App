import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/AudioSpectogram/editor.dart';

String? recordedFilePath;
final RecorderController recorderController = RecorderController();

class RecorderWithSpectogram extends StatefulWidget {
  const RecorderWithSpectogram({super.key});

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
  var _isRecordingPaused = false;

  void _toggleRecording() async {
    if (recorderController.isRecording) {
      setState(() {
        _isRecording = false;
        recorderController.pause();
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
                              Spectogram(audioFilePath: recordedFilePath!)));
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
