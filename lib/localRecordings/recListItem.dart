/*
 * recListItem.dart
 */

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import '../PostRecordingForm/RecordingForm.dart';
import '../config/config.dart'; // Contains MAPY_CZ_API_KEY

class RecordingItem extends StatefulWidget {
  final Recording recording;

  const RecordingItem({Key? key, required this.recording}) : super(key: key);

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
    getData().then((_) {
      setState(() {
        loaded = true;
      });
    });
  }

  void getParts() {
    parts = DatabaseNew.getPartsById(widget.recording.id!);
  }

  void getLocation() {
    if (parts.isNotEmpty) {
      center = LatLng(parts.last.gpsLatitudeEnd ?? 49.1951, parts.last.gpsLongitudeEnd ?? 16.6068);
    } else {
      center = LatLng(49.1951, 16.6068);
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

  Future<void> _fetchRecordings() async {
    // TODO: Add your fetch logic here if needed
    // For now, simply refresh parts and location
    setState(() {
      getParts();
      getLocation();
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

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return ScaffoldWithBottomBar(
        appBarTitle: widget.recording.note ?? '',
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    return ScaffoldWithBottomBar(
      appBarTitle: widget.recording.name ?? '',
      content: RefreshIndicator(
        onRefresh: _fetchRecordings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: 200,
                width: double.infinity,
                child: LiveSpectogram.SpectogramLive(
                  data: [],
                  filepath: widget.recording.path,
                ),
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
                      padding: const EdgeInsets.all(3.0),
                      width: double.infinity,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child:
                      Text(widget.recording.note ?? '', style: const TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    const Row(children: [Text("Location")]),
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
                              'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${Config.mapsApiKey}',
                              userAgentPackageName: 'cz.delta.strnadi',
                            ),
                            MarkerLayer(
                              markers: [
                                if (locationService.lastKnownPosition != null)
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
              )
            ],
          ),
        ),
      ),
    );
  }
}