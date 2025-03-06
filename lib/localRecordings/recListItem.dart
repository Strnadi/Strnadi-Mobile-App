import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/localRecordings/recordingsDb.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';

import '../PostRecordingForm/RecordingForm.dart';

class RecordingItem extends StatefulWidget {
  final RecordItem recording;

  const RecordingItem({Key? key, required this.recording}) : super(key: key);

  @override
  _RecordingItemState createState() => _RecordingItemState();
}

class _RecordingItemState extends State<RecordingItem> {
  late String _filepath;
  late String _note;
  late double _latitude;
  late double _longitude;
  late LatLng? fallbackPosition = null;

  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    getData();
    getNote();
    getLocation();

    player.positionStream.listen((position) {
      setState(() {
        currentPosition = position;
      });
    });

    player.durationStream.listen((duration) {
      setState(() {
        totalDuration = duration ?? Duration.zero;
      });
    });

    player.playingStream.listen((playing) {
      setState(() {
        isPlaying = playing;
      });
    });
  }

  Future<void> getData() async {
    var db = await LocalDb.database;
    var filepath = await db.rawQuery(
        "SELECT filepath FROM recordings WHERE title = ?",
        [widget.recording.title]);

    if (filepath.isNotEmpty) {
      _filepath = filepath[0]["filepath"].toString();
      await player.setFilePath(_filepath);
      setState(() {
        isFileLoaded = true;
      });
    }
  }

  Future<void> getNote() async {
    var db = await LocalDb.database;
    var note = await db.rawQuery("SELECT note FROM recordings WHERE title = ?",
        [widget.recording.title]);

    if (note.isNotEmpty) {
      _note = note[0]["note"].toString();
    }
  }

  Future<void> getLocation() async {
    var db = await LocalDb.database;
    var filepath = await db.rawQuery(
        "SELECT latitude, longitude FROM recordings WHERE title = ?",
        [widget.recording.title]);

    if (filepath.isNotEmpty) {
      _latitude = double.parse(filepath[0]["latitude"].toString());
      _longitude = double.parse(filepath[0]["longitude"].toString());

      fallbackPosition = LatLng(_latitude, _longitude);
      setState(() {
        isFileLoaded = true;
      });
    }
  }

  void togglePlay() async {
    if (!isFileLoaded) return;

    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void seekRelative(int seconds) {
    final newPosition = currentPosition + Duration(seconds: seconds);
    player.seek(newPosition);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: widget.recording.title,
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Spectrogram
          SizedBox(
            height: 200,
            width: double.infinity,
            child: LiveSpectogram.SpectogramLive(
              data: [],
              filepath: _filepath,
            ),
          ),

          // Audio Player Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                Text(_formatDuration(totalDuration), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold) ),
                // Playback Controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.replay_10, size: 32),
                      onPressed: () => seekRelative(-10),
                    ),
                    IconButton(
                      icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                      iconSize: 72,
                      onPressed: togglePlay,
                    ),
                    IconButton(
                      icon: Icon(Icons.forward_10, size: 32),
                      onPressed: () => seekRelative(10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Note
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _note.isNotEmpty ? _note : "No note",
              style: TextStyle(fontSize: 16),
            ),
          ),

          // Map
          Container(
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                children: [
                  Row(
                    children: [Text("Location")]
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 300,
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: fallbackPosition ?? LatLng(49.1951, 16.6068),
                          initialZoom: 13.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                            'https://api.mapy.cz/v1/maptiles/basic/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                            userAgentPackageName: 'cz.delta.strnadi',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 20.0,
                                height: 20.0,
                                point: fallbackPosition ?? LatLng(49.1951, 16.6068),
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.blue,
                                  size: 30.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}