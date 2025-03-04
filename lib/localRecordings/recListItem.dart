import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/localRecordings/recordingsDb.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';

import '../HealthCheck/serverHealth.dart';

class RecordingItem extends StatefulWidget {
  final RecordItem recording;

  const RecordingItem({Key? key, required this.recording}) : super(key: key);

  @override
  _RecordingItemState createState() => _RecordingItemState();
}

class _RecordingItemState extends State<RecordingItem> {
  late String _filepath;
  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;

  @override
  void initState() {
    super.initState();
    getData();

    // Listen for playback state changes to update UI
    player.playingStream.listen((isPlaying) {
      setState(() {});
    });
  }

  Future<void> getData() async {
    var db = await LocalDb.database;
    var filepath = await db.rawQuery(
        "SELECT filepath FROM recordings WHERE title = ?", [widget.recording.title]);

    if (filepath.isNotEmpty) {
      logger.i("Loading file: ${filepath[0]["filepath"]}");
      _filepath = filepath[0]["filepath"].toString();
      await player.setFilePath(_filepath); // Load the file for playback
      setState(() {
        isFileLoaded = true;
      });
    }
  }

  void togglePlay() async {
    if (!isFileLoaded) return; // Ensure file is ready before playing

    if (player.playing) {
      await player.pause();
    } else {
      logger.i("Playing file: $_filepath");
      await player.play();
    }
  }

  @override
  void dispose() {
    player.dispose(); // Properly dispose of the audio player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;

    return ScaffoldWithBottomBar(
      appBarTitle: widget.recording.title,
      content: Column(
        children: [
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: width,
                  height: 200,
                  child: LiveSpectogram.SpectogramLive(
                    data: [],
                    filepath: _filepath,
                  ),
                ),
                ElevatedButton(
                  onPressed: isFileLoaded ? togglePlay : null,
                  child: Icon(player.playing ? Icons.pause : Icons.play_arrow),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
