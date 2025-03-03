import 'package:audioplayers/audioplayers.dart';
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

class _RecordingItemState extends State<RecordingItem>{

  late String _filepath;

  var player = AudioPlayer();

  void getData() async{
    var db =await LocalDb.database;

    var filepath = await db.rawQuery("SELECT filepath FROM recordings WHERE title = ?", [widget.recording.title]);
    var ret = filepath[0]["filepath"].toString();

    _filepath = ret;

    setState(() {});
  }

  void togglePlay() async {
    if (player.state == PlayerState.playing) {
      await player.pause();
    } else {
      await player.play(DeviceFileSource(_filepath));
    }
  }

  @override
  Widget build(BuildContext context) {
    getData();
    double width = MediaQuery.of(context).size.width;

    return ScaffoldWithBottomBar(
        appBarTitle: widget.recording.title,
        content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Center(
              child: Column(
                children: [
                  SizedBox(
                      width: width,
                      height: 200,
                      child: LiveSpectogram.SpectogramLive(data: [], filepath: _filepath)
                  ),
                  ElevatedButton(
                    onPressed: () {
                      togglePlay();
                    },
                    child: player.state == PlayerState.paused ? Icon(Icons.play_arrow) : Icon(Icons.pause),
                  ),
                ],
              ),
            )
          ],
        )
    );
  }

}