import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class SpectrogramViewer extends StatefulWidget {
  final String audioFilePath;

  const SpectrogramViewer({Key? key, required this.audioFilePath}) : super(key: key);

  @override
  _SpectrogramViewerState createState() => _SpectrogramViewerState();
}

class _SpectrogramViewerState extends State<SpectrogramViewer> {
  late final PlayerController _playerController;
  //late final RecorderController _recorderController;

  @override
  void initState() {
    super.initState();
    _playerController = PlayerController();
    _preparePlayer();
  }

  Future<void> _preparePlayer() async {
    await _playerController.preparePlayer(
      path: widget.audioFilePath,
      noOfSamples: 100,
    );
    setState(() {}); // Refresh the UI after preparation
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_playerController.playerState == PlayerState.initialized ||
            _playerController.playerState == PlayerState.playing ||
            _playerController.playerState == PlayerState.paused)
          AudioFileWaveforms(
            playerController: _playerController,
            playerWaveStyle: PlayerWaveStyle(
              fixedWaveColor: Colors.pinkAccent,
              liveWaveColor: Colors.white,
            ),
            size: Size(MediaQuery.of(context).size.width, 200.0),
            enableSeekGesture: true,
            waveformType: WaveformType.long, // Use a valid WaveformType
          )
        else
          const CircularProgressIndicator(),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            if (_playerController.playerState == PlayerState.playing) {
              _playerController.pausePlayer();
            } else {
              _playerController.startPlayer();
            }
            setState(() {});
          },
          child: Text(
            _playerController.playerState == PlayerState.playing
                ? 'Pause'
                : 'Play',
          ),
        ),
      ],
    );
  }
}