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
 * RecordingForm.dart
 */

import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:strnadi/PostRecordingForm/imageUpload.dart';
import 'package:strnadi/archived/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import 'package:strnadi/archived/recordingsDb.dart';
import '../config/config.dart';
import '../archived/soundDatabase.dart';
import 'package:strnadi/locationService.dart' as loc;
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/auth/authorizator.dart' as auth;
import 'addDialect.dart';
import 'dart:math' as math;

final MAPY_CZ_API_KEY = Config.mapsApiKey;
final logger = Logger();

class RecordingForm extends StatefulWidget {
  final String filepath;
  final LatLng? currentPosition;
  final List<RecordingPartUnready> recordingParts;
  final DateTime startTime;
  final List<int> recordingPartsTimeList;
  final List<LatLng> route;

  const RecordingForm({
    Key? key,
    required this.filepath,
    required this.startTime,
    required this.currentPosition,
    required this.recordingParts,
    required this.recordingPartsTimeList,
    required this.route,
  }) : super(key: key);

  @override
  _RecordingFormState createState() => _RecordingFormState();
}

class _RecordingFormState extends State<RecordingForm> {
  final _recordingNameController = TextEditingController();
  final _commentController = TextEditingController();
  double _strnadiCountController = 1.0;
  double currentPos = 0.0;
  List<File> _selectedImages = [];
  Widget? spectogram;
  List<DialectModel> dialectSegments = [];
  final _audioPlayer = AudioPlayer();
  Duration currentPositionDuration = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool isPlaying = false;
  late Recording recording;
  int? _recordingId;
  final List<LatLng> _route = [];
  late Stream<Position> _positionStream;
  late loc.LocationService locationService;
  LatLng? currentLocation;
  LatLng? markerPosition;
  DateTime? _lastRouteUpdate;
  // This will hold the converted parts.
  List<RecordingPart> recordingParts = [];

  var placeTitle = "mapa";

  @override
  void initState() {
    super.initState();
    // Initialize spectrogram widget.
    setState(() {
      spectogram = LiveSpectogram.SpectogramLive(
        key: spectogramKey,
        data: [],
        filepath: widget.filepath,
        getCurrentPosition: (pos) {
          setState(() {
            currentPos = pos;
          });
        },
      );
    });
    _audioPlayer.positionStream.listen((position) {
      setState(() {
        currentPositionDuration = position;
      });
    });
    _audioPlayer.durationStream.listen((duration) {
      setState(() {
        totalDuration = duration ?? Duration.zero;
      });
    });
    _audioPlayer.playingStream.listen((playing) {
      setState(() {
        isPlaying = playing;
      });
    });
    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.pause();
      }
    });
    _audioPlayer.setFilePath(widget.filepath);

    locationService = loc.LocationService();
    _positionStream = locationService.positionStream;
    markerPosition = null;
    _positionStream.listen((Position position) {
      _onNewPosition(position);
    });

    final safeStorage = FlutterSecureStorage();
    // IMPORTANT: assign widget.filepath so that the recording path is not null.
    recording = Recording(
      createdAt: DateTime.now(),
      mail: "",
      estimatedBirdsCount: _strnadiCountController.toInt(),
      device: "",
      byApp: true,
      note: _commentController.text,
      path: widget.filepath,
    );

    safeStorage.read(key: 'token').then((token) async {
      if (token == null) {
        _showMessage('You are not logged in');
      }
      while (recording.mail!.isEmpty) {
        await Future.delayed(const Duration(seconds: 1));
      }
      recording.mail = JwtDecoder.decode(token!)['sub'];
      logger.i('Mail set to ${recording.mail}');
    });

    getDeviceModel().then((model) async {
      while (recording.device?.isEmpty ?? true) {
        await Future.delayed(const Duration(seconds: 1));
      }
      recording.device = model;
      logger.i('Device set to ${recording.device}');
    });

    // Log how many parts we received from streamRec.
    logger.i("RecordingForm: Received ${widget.recordingParts.length} recording parts from streamRec.");

    // Convert the passed parts.
    for (RecordingPartUnready part in widget.recordingParts) {
      try {
        RecordingPart newPart = RecordingPart.fromUnready(part);
        recordingParts.add(newPart);
      } catch (e, stackTrace) {
        logger.e("Error converting part: $e", error: e, stackTrace: stackTrace);
      }
    }

    _route.addAll(widget.route);

    // Fix any parts with invalid (0.0, 0.0) GPS coordinates
    for (var part in recordingParts) {
      if (part.gpsLatitudeStart == 0.0 && part.gpsLongitudeStart == 0.0) {
        // Try to use a previous valid part's location
        var validParts = recordingParts.where((p) =>
        p != part &&
            p.gpsLatitudeStart != 0.0 &&
            p.gpsLongitudeStart != 0.0);
        if (validParts.isNotEmpty) {
          var replacement = validParts.first;
          part.gpsLatitudeStart = replacement.gpsLatitudeStart;
          part.gpsLongitudeStart = replacement.gpsLongitudeStart;
        } else if (_route.isNotEmpty) {
          // Fallback to route if available
          part.gpsLatitudeStart = _route.first.latitude;
          part.gpsLongitudeStart = _route.first.longitude;
        } // else leave as (0.0, 0.0)
      }
    }

    reverseGeocode(widget.recordingParts[0].gpsLatitudeStart!, widget.recordingParts[0].gpsLongitudeStart!);
  }

  // Helper method to display a simple message dialog.
  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Message'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmDiscard() {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Potvrzení'),
          content: const Text('Opravdu chcete smazat nahrávku?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Ne'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Ano'),
            ),
          ],
        );
      },
    );
  }

  void _showDiscardDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Potvrzení'),
          content: const Text('Opravdu chcete smazat nahrávku?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Ne'),
            ),
            TextButton(
              onPressed: () {
                spectogramKey = GlobalKey();
                Navigator.of(context).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => LiveRec()),
                );
              },
              child: const Text('Ano'),
            ),
          ],
        );
      },
    );
  }

  // Helper method to seek the audio player relative to current position.
  void seekRelative(int seconds) {
    final currentPos = _audioPlayer.position;
    _audioPlayer.seek(currentPos + Duration(seconds: seconds));
  }

  void SendDialects() async {
    var id = await DatabaseNew.getRecordingBEIDbyID(recording.id!);

    if (id == null) {
      logger.e("Recording BEID is null");
      return;
    }

    for (DialectModel dialect in dialectSegments) {
      var token = FlutterSecureStorage();
      var jwt = await token.read(key: 'token');
      logger.i("jwt is $jwt");
      logger.i("token is $jwt");
      var body = jsonEncode(<String, dynamic>{
        'recordingId': id,
        'StartDate': recording.createdAt
            .add(
            Duration(milliseconds: dialect.startTime.toInt()))
            .toIso8601String(),
        'endDate': recording.createdAt.add(
            Duration(milliseconds: dialect.endTime.toInt())).toIso8601String(),
        'dialectCode': dialect.label,
      });
      try {
        final url = Uri(scheme: 'https',
            host: Config.host,
            path: '/recordings/filtered/upload');
        await http.post(
          url,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode(<String, dynamic>{
            'recordingId': id,
            'StartDate': recording.createdAt
                .add(
                Duration(milliseconds: dialect.startTime.toInt()))
                .toIso8601String(),
            'endDate': recording.createdAt
                .add(
                Duration(milliseconds: dialect.endTime.toInt()))
                .toIso8601String(),
            'dialectCode': dialect.label,
          }),
        ).then((value) {
          if (value.statusCode == 200) {
            logger.i("Dialect sent successfully");
          } else {
            logger.e("Dialect sending failed with status code ${value
                .statusCode} and body $body");
          }
        });
      } catch (e, stackTrace) {
        logger.e(
            "Error inserting dialect: $e", error: e, stackTrace: stackTrace);
      }
    }
  }

  void _showDialectSelectionDialog() {
    var position = spectogramKey.currentState!.currentPositionPx;
    var spect = spectogram;
    setState(() {
      spectogram = null;
    });
    showDialog(
      // disable tap out hide
      barrierDismissible: false,
      context: context,
      builder: (context) => DialectSelectionDialog(
        spectogram: spect!,
        currentPosition: position,
        duration: totalDuration.inSeconds.toDouble(),
        onDialectAdded: (dialect) {
          setState(() {
            dialectSegments.add(dialect);
            spectogram = spect;
          });
        },
      ),
    );
  }

  String _formatTimestamp(double seconds) {
    int mins = (seconds ~/ 60);
    int secs = (seconds % 60).floor();
    int ms = ((seconds - seconds.floor()) * 100).floor();
    return "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}";
  }

  Widget _buildDialectSegment(DialectModel dialect) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "${_formatTimestamp(dialect.startTime)} — ${_formatTimestamp(dialect.endTime)}",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: dialect.color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: Text(
              dialect.label,
              style: TextStyle(
                fontSize: 14,
                color: dialect.color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                dialectSegments.remove(dialect);
              });
            },
            child: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
          ),
        ],
      ),
    );
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
    } catch (e) {
      print('Reverse geocode error: $e');
    }
  }

  Future<void> insertRecordingWhenReady() async {
    while (recording.mail!.isEmpty || (recording.device?.isEmpty ?? true)) {
      await Future.delayed(const Duration(seconds: 1));
      logger.i('Waiting for recording to be ready');
    }
    logger.i('Started inserting recording');
    recording.downloaded = true;
    recording.id = await DatabaseNew.insertRecording(recording);

    // Update the recording in the database with the final file path and downloaded flag
    await DatabaseNew.updateRecording(recording);

    setState(() {
      _recordingId = recording.id;
    });
    logger.i('ID set to $_recordingId, recording file path: ${recording.path}');
  }

  void _onImagesSelected(List<File> images) {
    setState(() {
      _selectedImages = images;
    });
  }

  Future<bool> hasInternetAccess() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  Future<String> getDeviceModel() async {
    // Implement your device info logic here.
    return "DeviceModel";
  }

  void togglePlay() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> upload() async {
    logger.i("Uploading recording. Estimated birds count: ${_strnadiCountController.toInt()}");
    recording.note = _commentController.text.isEmpty ? null : _commentController.text;
    recording.name = _recordingNameController.text.isEmpty ? null : _recordingNameController.text;
    recording.downloaded = true;
    recording.estimatedBirdsCount = _strnadiCountController.toInt();

    // Log the recording path before insertion
    //logger.i("Recording before insertion: path=${recording.path}");
    _recordingId = await DatabaseNew.insertRecording(recording);
    logger.i("Recording inserted with ID: $_recordingId, file path: ${recording.path}");

    // Log number of parts to insert
    logger.i("Uploading ${recordingParts.length} recording parts.");
    for (RecordingPart part in recordingParts) {
      part.recordingId = _recordingId;
      int partId = await DatabaseNew.insertRecordingPart(part);
      logger.i("Inserted part with id: $partId for recording $_recordingId");
    }
    // Check internet connectivity after inserting recording parts
    if (!await hasInternetAccess()) {
      logger.w("No internet connection, recording saved offline");
      _showMessage("Recording saved offline");
      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
      return;
    }
    try {
      await DatabaseNew.sendRecordingBackground(recording.id!);
    } catch (e, stackTrace) {
      logger.e("Error sending recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
    SendDialects();
    logger.i("Recording uploaded");
    spectogramKey = GlobalKey();
    Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
  }

  void _onNewPosition(Position position) {
    final newPoint = LatLng(position.latitude, position.longitude);
    setState(() {
      markerPosition = newPoint;
    });
  }

  @override
  void dispose() {
    if (spectogramKey.currentState != null) {
      spectogramKey.currentState!.dispose();
    }
    _recordingNameController.dispose();
    _commentController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryRed = const Color(0xFFFF3B3B);
    final Color secondaryRed = const Color(0xFFFFEDED);
    final Color yellowishBlack = const Color(0xFF2D2B18);
    final Color yellow = const Color(0xFFFFD641);

    // Compute half screen width for buttons.
    final halfScreen = MediaQuery.of(context).size.width * 0.45;
    markerPosition = locationService.lastKnownPosition != null
        ? LatLng(locationService.lastKnownPosition!.latitude, locationService.lastKnownPosition!.longitude)
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        final bool shouldPop = await _confirmDiscard() ?? false;
        if (shouldPop) {
          spectogramKey = GlobalKey();
          Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Recording Form"),
          actions: [
            ElevatedButton(
              onPressed: upload,
              style: ElevatedButton.styleFrom(
                backgroundColor: yellow,
                foregroundColor: yellowishBlack,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text("Uložit"),
            ),
          ],
          leading: IconButton(
            icon: Image.asset('assets/icons/backButton.png', width: 30, height: 30),
            onPressed: () async {
              final bool shouldPop = await _confirmDiscard() ?? false;
              if (shouldPop) {
                spectogramKey = GlobalKey();
                Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Column(
              children: [
                // Spectrogram and playback controls remain unchanged.
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: spectogram,
                ),
                Text(
                  _formatDuration(totalDuration),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Přidat dialekt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFF7C0),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _showDialectSelectionDialog,
                  ),
                ),
                if (dialectSegments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: dialectSegments.map((dialect) => _buildDialectSegment(dialect)).toList(),
                    ),
                  ),
                const SizedBox(height: 50),
                Form(
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Název nahrávky field
                        Text('Název nahrávky', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: TextFormField(
                            controller: _recordingNameController,
                            textAlign: TextAlign.start,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            ),
                            keyboardType: TextInputType.text,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Prosím zadejte název nahrávky';
                              } else if (value.length > 49) {
                                return 'Název nahrávky nesmí být delší než 49 znaků';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Počet strnadů slider
                        Text('Počet strnadů', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        // Display current slider value above the slider.
                        Text(
                          _strnadiCountController.toInt() == 3
                              ? "3 a více strnadů"
                              : "${_strnadiCountController.toInt()} strnad${_strnadiCountController.toInt() == 1 ? "" : "i"}",
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 5),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: yellow,
                            inactiveTrackColor: Colors.yellow.shade200,
                            thumbColor: yellow,
                            overlayColor: Colors.yellow.withOpacity(0.3),
                          ),
                          child: Slider(
                            value: _strnadiCountController,
                            min: 1,
                            max: 3,
                            divisions: 2,
                            onChanged: (value) => setState(() => _strnadiCountController = value),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Komentář field (multiline)
                        Text('Komentář', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: TextFormField(
                            controller: _commentController,
                            textAlign: TextAlign.start,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                            ),
                            keyboardType: TextInputType.multiline,
                            maxLines: null,
                            validator: (value) => (value == null || value.isEmpty)
                                ? 'Prosím zadejte komentář'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Mapa label and map widget with same padding as text fields.
                        Text('Mapa', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              height: 200,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: _computedCenter,
                                  initialZoom: _computedZoom,
                                  interactionOptions: InteractionOptions(flags: InteractiveFlag.none),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                    'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                                    userAgentPackageName: 'cz.delta.strnadi',
                                  ),
                                  if (_route.isNotEmpty)
                                    PolylineLayer(
                                      polylines: [
                                        Polyline(points: List.from(_route), strokeWidth: 4.0, color: Colors.blue),
                                      ],
                                    ),

                                  MarkerLayer(markers: widget.recordingParts
                                      .map((part) => Marker(
                                    point: LatLng(part.gpsLatitudeStart!, part.gpsLongitudeStart!), child: Icon(Icons.place, color: Colors.red, size: 30),
                                  ))
                                      .toList()),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Zahodit button at bottom.
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('Potvrzení'),
                                      content: const Text('Opravdu chcete smazat nahrávku?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: const Text('Ne'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            spectogramKey = GlobalKey();
                                            Navigator.of(context).pop();
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => LiveRec()),
                                            );
                                          },
                                          child: const Text('Ano'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: secondaryRed,
                                foregroundColor: primaryRed,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Smazat nahrávku'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Computed getters inserted inside _RecordingFormState:
  LatLng get _computedCenter {
    if (_route.isEmpty) return LatLng(0.0, 0.0);
    double sumLat = 0;
    double sumLon = 0;
    for (LatLng p in _route) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    return LatLng(sumLat / _route.length, sumLon / _route.length);
  }

  double get _computedZoom {
    if (_route.isEmpty) return 13.0;
    double minLat = _route.first.latitude;
    double maxLat = _route.first.latitude;
    double minLon = _route.first.longitude;
    double maxLon = _route.first.longitude;
    for (LatLng p in _route) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    double latDiff = maxLat - minLat;
    double lonDiff = maxLon - minLon;
    double maxDiff = latDiff > lonDiff ? latDiff : lonDiff;
    double idealZoom = math.log(360 / maxDiff) / math.ln2;
    if (idealZoom < 10) idealZoom = 10;
    if (idealZoom > 16) idealZoom = 16;
    return idealZoom;
  }
}