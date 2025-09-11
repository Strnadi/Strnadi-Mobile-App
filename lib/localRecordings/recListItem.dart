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

import 'package:strnadi/localization/localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/dialectBadge.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import '../dialects/ModelHandler.dart';
import 'editRecording.dart';
import '../config/config.dart'; // Contains MAPY_CZ_API_KEY

final logger = Logger();

class RecordingItem extends StatefulWidget {
  Recording recording;

  RecordingItem({Key? key, required this.recording}) : super(key: key);

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

  Dialect? dialect;

  final MapController _mapController = MapController();

  String placeTitle = 'Mapa';
  Widget? _cachedSpectrogram;

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    _initializeRecording();
  }

  Future<void> _initializeRecording() async {
    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      _cachedSpectrogram = LiveSpectogram.SpectogramLive(
        data: [],
        filepath: widget.recording.path,
      );
    }

    await getParts();
    await GetDialect();

    logger.i("[RecordingItem] initState: recording path: ${widget.recording.path}, downloaded: ${widget.recording.downloaded}");

    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
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
      await getData();
      setState(() {
        loaded = true;
      });
    } else {
      List<RecordingPart> parts = await DatabaseNew.getPartsById(widget.recording.BEId!);
      if (parts.isNotEmpty) {
        logger.i("[RecordingItem] Recording path is empty. Starting concatenation of recording parts for recording id: ${widget.recording.id}");
        await DatabaseNew.concatRecordingParts(widget.recording.BEId!);
        logger.i("[RecordingItem] Concatenation complete for recording id: ${widget.recording.id}. Fetching updated recording.");
        Recording? updatedRecording = await DatabaseNew.getRecordingFromDbById(widget.recording.BEId!);
        logger.i("[RecordingItem] Fetched updated recording: $updatedRecording");
        logger.i("[RecordingItem] Original recording path: ${widget.recording.path}");
        setState(() {
          widget.recording.path = updatedRecording?.path ?? widget.recording.path;
          loaded = true;
        });
      } else {
        logger.w("[RecordingItem] No recording parts found for recording id: ${widget.recording.id}");
        setState(() {
          loaded = true;
        });
      }
    }
  }


  Future<void> GetDialect() async {
    final int recordingId = widget.recording.id!;
    final List<Dialect> dialects =
        await DatabaseNew.getDialectsByRecordingId(recordingId);

    if (dialects.isEmpty) {
      setState(() => dialect = null);
      return;
    }

    setState(() => dialect = dialects.first);
  }



  Future<void> getData() async {
    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      try {
        await player.setFilePath(widget.recording.path!);
        setState(() {
          isFileLoaded = true;
        });
      } catch (e, stackTrace) {
        logger.e("Error loading audio file: $e", error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
  }

  Future<void> getParts() async {
    logger.i('Recording ID: ${widget.recording.id}');
    var parts = await DatabaseNew.getPartsById(widget.recording.id!);
    setState(() {
      this.parts = parts;
    });
    await reverseGeocode(this.parts[0].gpsLatitudeStart, this.parts[0].gpsLongitudeStart);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _mapController.move(LatLng(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart), 13.0);
  });
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
      logger.e("Error toggling playback: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
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

  Future<void> _downloadRecording() async {
    if (!await Config.hasBasicInternet) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Stahování nedostupné')),
          content: Text(t('Pro stažení nahrávky je vyžadováno připojení k internetu.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('OK')),
            ),
          ],
        ),
      );
      return;
    }

    // Show loader while downloading
    setState(() {
      loaded = false;
    });
    try {
      logger.i("Initiating download for recording id: ${widget.recording.id}");
      await DatabaseNew.downloadRecording(widget.recording.id!);
      Recording? updatedRecording = await DatabaseNew.getRecordingFromDbById(widget.recording.id!);
      setState(() {
        widget.recording = updatedRecording?? widget.recording;
      });
      // Re‑initialise spectrogram and audio player with the newly downloaded file
      _cachedSpectrogram = LiveSpectogram.SpectogramLive(
        data: [],
        filepath: widget.recording.path,
      );
      await getData();       // load the file into the player
      setState(() {
        loaded = true;       // dismiss the loader and show the UI
      });
      logger.i("Downloaded recording updated: ${widget.recording.path}");
    } catch (e, stackTrace) {
      logger.e("Error downloading recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t("Error downloading recording"))),
      );
    }
  }

  /// Permanently deletes the current recording both on the server (if already sent)
  /// and locally in the SQLite database.
  Future<void> _deleteRecording() async {
    try {
      // Always remove it from the local DB.
      await DatabaseNew.deleteRecording(widget.recording.id!);

      // Return to the previous screen so the list refreshes.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      logger.e('Error deleting recording: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('Error deleting recording'))),
        );
      }
    }
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
        final data = jsonDecode(utf8.decode(response.bodyBytes));
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
        selectedPage: BottomBarItem.list,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final updatedRecording = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditRecordingPage(recording: widget.recording),
                ),
              );
              // If the user saved changes, rebuild to show the latest data
              if (updatedRecording != null && mounted) {
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRecordings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              widget.recording.path != null && widget.recording.path!.isNotEmpty
                  ? SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: RepaintBoundary(
                        child: _cachedSpectrogram ?? LiveSpectogram.SpectogramLive(
                          data: [],
                          filepath: widget.recording.path,
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(t('Nahrávka není dostupná')),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _downloadRecording,
                              child: Text(t('Stáhnout nahrávku')),
                            ),
                          ],
                        ),
                      ),
                    ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Text(_formatDuration(totalDuration),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(widget.recording.note ?? 'K tomuto zaznamu neni poznamka', style: TextStyle(fontSize: 16))]),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [Text(t("Datum a čas"))],
                              ),
                              Text(
                                formatDateTime(widget.recording.createdAt),
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (dialect != null) DialectBadge(
                      dialect: dialect!,
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
                          Text(t("Predpokladany pocet strnadu: ")),
                          Text(widget.recording.estimatedBirdsCount.toString()),
                        ],
                      ),
                    ),
                    Visibility(
                      visible: widget.recording.sent == false && widget.recording.sending == false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send),
                          label: Text(t('Odeslat záznam')),
                          onPressed: () async {
                            try {
                              // ensure all parts have been sent
                              await DatabaseNew.checkRecordingPartsSent(widget.recording.id!);
                              setState(() {
                                widget.recording.sending = true;
                              });
                              DatabaseNew.sendRecordingBackground(widget.recording.id!);
                              logger.i("Sending recording: ${widget.recording.id}");
                            } on UnsentPartsException {
                              // prompt to resend unsent parts
                              final shouldResend = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(t('Neodeslané části')),
                                  content: Text(t('Některé části nahrávky nebyly odeslány. Chcete je zkusit znovu odeslat?')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t('Zrušit'))),
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t('Odeslat znovu'))),
                                  ],
                                ),
                              );
                              if (shouldResend == true) {
                                await DatabaseNew.resendUnsentParts();
                              }
                            } catch (e, stackTrace) {
                              logger.e('Error during send check/resend: $e', error: e, stackTrace: stackTrace);
                            }
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton(
                        onPressed: () {
                          // Delete recording from cache
                          DatabaseNew.deleteRecordingFromCache(widget.recording.id!);
                          setState(() {
                            // Optionally refresh UI or provide feedback
                          });
                        },
                        child: Text(t('Smazat z cache')),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.white,),
                        label: Text(t('Smazat záznam'), style: TextStyle(color: Colors.white),),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(t('Potvrdit smazání')),
                              content: Text(t('Opravdu chcete tento záznam natrvalo smazat?')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(t('Zrušit')),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(t('Smazat')),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            _deleteRecording();
                          }
                        },
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