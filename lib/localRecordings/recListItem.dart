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
/*
 * recListItem.dart
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import '../PostRecordingForm/RecordingForm.dart';
import '../config/config.dart'; // Contains MAPY_CZ_API_KEY

final logger = Logger();

class RecordingItem extends StatefulWidget {
  final Recording recording;

  const RecordingItem({Key? key, required this.recording}) : super(key: key);

  @override
  _RecordingItemState createState() => _RecordingItemState();
}

class _RecordingItemState extends State<RecordingItem> {
  bool loaded = false;
  late LatLng center;
  late List<RecordingPart> parts = [];
  late LocationService locationService;
  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  final MapController _mapController = MapController();

  String placeTitle = 'Mapa';

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    getParts();

    if (widget.recording.path != null) {
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


      getData().then((_) {
        setState(() {
          loaded = true;
        });
      });
    }
    else{
      if(widget.recording.downloaded) {
        DatabaseNew.concatRecordingParts(widget.recording.id!).then((value) {
          setState(() {
            loaded = true;
          });
        });
      }
    }
  }



  Future<void> getData() async {
    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      try {
        await player.setFilePath(widget.recording.path!);
        setState(() {
          isFileLoaded = true;
        });
      } catch (e, stackTrace) {
        print("Error loading audio file: $e");
      }
    }
  }

  Future<void> getParts() async {
    logger.i('Recording ID: ${widget.recording.id}');
    var parts = DatabaseNew.getPartsById(widget.recording.id!);
    setState(() {
      this.parts = parts;
      reverseGeocode(this.parts[0].gpsLatitudeStart, this.parts[0].gpsLongitudeStart);
    });
    _mapController.move(LatLng(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart), 13.0);
  }

  Future<void> _fetchRecordings() async {
    // TODO: Add your fetch logic here if needed
    // For now, simply refresh parts and location
    setState(() {
      getParts();
    });
  }

  void togglePlay() async {
    if (!isFileLoaded) return;
    try {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
    } catch (e, stackTrace) {
      print("Error toggling playback: $e");
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


  Future<void> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse("https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

    logger.i("reverse geocode url: $url");
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.mapsApiKey}',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final results = data['items'];
        if (results.isNotEmpty) {
          logger.i("Reverse geocode result: $results");
          setState(() {
            placeTitle = results[0]['name'];
          });
        }
      }
      else {
        logger.e("Reverse geocode failed with status code ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }


  @override
  Widget build(BuildContext context) {
    if (!loaded && widget.recording.path != null) {
      return ScaffoldWithBottomBar(
        appBarTitle: widget.recording.name ?? '',
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recording.name ?? ''),
        leading: IconButton(
          icon: Image.asset('assets/icons/backButton.png', width: 30, height: 30),
          onPressed: () async {
            Navigator.pop(context);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRecordings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              widget.recording.path != null && widget.recording.path!.isNotEmpty ?
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: LiveSpectogram.SpectogramLive(
                    data: [],
                    filepath: widget.recording.path,
                  ),
              ) : const SizedBox(
                height: 200,
                width: double.infinity,
                child: Center(child: Text('Nahrávka není dostupná')),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Text(_formatDuration(totalDuration),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(icon: const Icon(Icons.replay_10, size: 32), onPressed: () => seekRelative(-10)),
                        IconButton(
                          icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          iconSize: 72,
                          onPressed: togglePlay,
                        ),
                        IconButton(icon: const Icon(Icons.forward_10, size: 32), onPressed: () => seekRelative(10)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      width: double.infinity,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(widget.recording.note ?? 'K tomuto zaznamu neni poznamka', style: const TextStyle(fontSize: 16))]),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(3.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [Container(
                          padding: const EdgeInsets.all(10.0),
                          child: Column(
                            children: [
                              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text("Datum a čas")]),
                              Text(
                                formatDateTime(widget.recording.createdAt),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Predpokladany pocet strnadu: "),
                          Text(widget.recording.estimatedBirdsCount.toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    Row(children: [Text(placeTitle)]),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 300,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
                            initialCenter: parts.isNotEmpty
                                ? LatLng(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart)
                                : LatLng(0.0, 0.0),
                            initialZoom: 13.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                              'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${Config.mapsApiKey}',
                              userAgentPackageName: 'cz.delta.strnadi',
                            ),
                            MarkerLayer(
                              markers: [
                                  Marker(
                                    width: 20.0,
                                    height: 20.0,
                                    point: parts.isNotEmpty
                                        ? LatLng(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart)
                                        : LatLng(0.0, 0.0),
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
              )
            ],
          ),
        ),
      ),
    );
  }

  void fetchRecPart(int id) async {
    final part = await DatabaseNew.fetchPartsFromDbById(id);
    setState(() {
      parts = part;
    });
  }

  String formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }
}