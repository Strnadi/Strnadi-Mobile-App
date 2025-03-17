/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/archived/recordingsDb.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/locationService.dart';

import '../PostRecordingForm/RecordingForm.dart';

class RecordingItem extends StatefulWidget {
  Recording recording;

  RecordingItem({Key? key, required this.recording}) : super(key: key);

  @override
  _RecordingItemState createState() => _RecordingItemState();
}

class _RecordingItemState extends State<RecordingItem> {

  bool loaded = false;

  late LatLng center;

  late List<RecordingPart> parts;

  late LocationService locationService;

  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    getData().then((_) {
      setState(() {
        loaded = true;
      });
    });

    locationService = LocationService();

    getParts();
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

  void getParts(){
    parts = DatabaseNew.getPartsById(widget.recording.id!);
  }

  void getLocation() {
    if (parts.isNotEmpty) {
      center = LatLng(parts.last.gpsLatitudeEnd, parts.last.gpsLongitudeEnd);
    } else {
      // Set a default center, e.g., a predetermined location or the user's last known position.
      center = LatLng(49.1951, 16.6068); // Example default value
    }
  }


  Future<void> getData() async {
    if(widget.recording.path != null) {
      await player.setFilePath(widget.recording.path!);
      setState(() {
        isFileLoaded = true;
      });
    }
  }

  /*
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
  */

  /*
  Future<void> DownloadRecording() async {
    var db = await LocalDb.database;
    var filepath = await db.rawQuery(
        "SELECT created_at FROM recordings WHERE title = ?",
        [widget.recording.title]);
    var rec_date = filepath[0]["created_at"].toString();

    // TODO stasik endopint to download file
  }
  */

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

    if(!loaded){
      return ScaffoldWithBottomBar(
        appBarTitle: widget.recording.note??'',
        content: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return ScaffoldWithBottomBar(
      appBarTitle: widget.recording.note??'',
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Spectrogram
          SizedBox(
            height: 200,
            width: double.infinity,
            child: LiveSpectogram.SpectogramLive(
              data: [],
              filepath: widget.recording.path,
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
                          initialCenter: center,
                          initialZoom: 13.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                            'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                            userAgentPackageName: 'cz.delta.strnadi',
                          ),
                          MarkerLayer(
                            markers: [
                              if(locationService.lastKnownPosition != null)
                              Marker(
                                width: 20.0,
                                height: 20.0,
                                point: locationService.lastKnownPosition!,
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