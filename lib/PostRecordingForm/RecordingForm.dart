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
import 'dart:io';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:strnadi/PostRecordingForm/imageUpload.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import 'package:strnadi/localRecordings/recordingsDb.dart';
import '../config/config.dart';
import '../database/soundDatabase.dart';
import 'package:strnadi/locationService.dart' as loc;

final MAPY_CZ_API_KEY = Config.mapsApiKey;
final logger = Logger();

class Recording {
  final DateTime createdAt;
  final int estimatedBirdsCount;
  final String device;
  final bool byApp;
  final String? note;

  Recording({
    required this.createdAt,
    required this.estimatedBirdsCount,
    required this.device,
    required this.byApp,
    this.note,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      createdAt: DateTime.parse(json['CreatedAt']),
      estimatedBirdsCount: json['EstimatedBirdsCount'],
      device: json['Device'],
      byApp: json['ByApp'],
      note: json['Note'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "CreatedAt": createdAt.toIso8601String(),
      "EstimatedBirdsCount": estimatedBirdsCount,
      "Device": device,
      "ByApp": byApp,
      "Note": note,
    };
  }
}

class RecordingForm extends StatefulWidget {
  final String filepath;
  final LatLng? currentPosition;
  final List<RecordingParts> recordingParts;
  final DateTime startTime;
  final List<int> recordingPartsTimeList;

  const RecordingForm({
    Key? key,
    required this.filepath,
    required this.startTime,
    required this.currentPosition,
    required this.recordingParts,
    required this.recordingPartsTimeList,
  }) : super(key: key);

  @override
  _RecordingFormState createState() => _RecordingFormState();
}

class _RecordingFormState extends State<RecordingForm> {
  final _recordingNameController = TextEditingController();
  final _commentController = TextEditingController();
  double _strnadiCountController = 1.0;

  List<File> _selectedImages = [];

  final _audioPlayer = AudioPlayer();
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool isPlaying = false;

  int? _recordingId;
  
  // List to store the user's route (all recorded locations)
  final List<LatLng> _route = [];
  late Stream<Position> _positionStream;

  late loc.LocationService locationService;

  LatLng? currentLocation;
  LatLng? markerPosition;

  DateTime? _lastRouteUpdate;

  @override
  void initState() {


    _audioPlayer.positionStream.listen((position) {
      setState(() {
        currentPosition = position;
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

    _audioPlayer.setFilePath(widget.filepath);
    super.initState();
    locationService = loc.LocationService();
    _positionStream = locationService.positionStream;
    markerPosition = null;
    // Subscribe to the position stream once using the dedicated method
    _positionStream.listen((Position position) {
      _onNewPosition(position);
    });
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
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine;
    } else {
      return "Unknown Device";
    }
  }

  Future<void> uploadAudio(File audioFile, int id) async {
    List<RecordingParts> trimmedAudioParts = await DatabaseHelper.trimAudio(
      widget.filepath,
      widget.recordingPartsTimeList,
      widget.recordingParts,
    );

    final uploadPart = Uri.parse('https://api.strnadi.cz/recordings/upload-part');
    final safeStorage = FlutterSecureStorage();
    final token = await safeStorage.read(key: "token");

    int cumulativeSeconds = 0;
    for (int i = 0; i < trimmedAudioParts.length; i++) {
      String? segmentPath = trimmedAudioParts[i].path;
      if (segmentPath == null || segmentPath.isEmpty) {
        logger.e("Trimmed audio segment $i has an invalid path; skipping upload for this segment.");
        continue;
      }
      final segmentFile = File(segmentPath);
      final fileBytes = await segmentFile.readAsBytes();
      final base64Audio = base64Encode(fileBytes);
      int segmentDuration = widget.recordingPartsTimeList[i];
      final segmentStart = widget.startTime.add(Duration(seconds: cumulativeSeconds));
      final segmentEnd = segmentStart.add(Duration(seconds: segmentDuration));
      cumulativeSeconds += segmentDuration;
      try {
        final response = await http.post(
          uploadPart,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'RecordingId': id,
            "Start": segmentStart.toIso8601String(),
            "End": segmentEnd.toIso8601String(),
            "LatitudeStart": trimmedAudioParts[i].latitude,
            "LongitudeStart": trimmedAudioParts[i].longitude,
            "LatitudeEnd": trimmedAudioParts[i].latitude,
            "LongitudeEnd": trimmedAudioParts[i].longitude,
            "data": base64Audio,
          }),
        );

        if (response.statusCode == 200 ||
            response.statusCode == 201 ||
            response.statusCode == 202) {
          logger.i('Upload was successful for segment $i');
          _showMessage("Upload was successful for segment $i");
        } else {
          logger.w('Error: ${response.statusCode} ${response.body}');
          _showMessage("Upload was not successful for segment $i");
        }
      } catch (error) {
        logger.e(error);
        _showMessage("Failed to upload segment $i: $error");
      }
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LiveRec()),
    );
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

  void upload() async {
    final platform = await getDeviceModel();
    print("Estimated birds count: ${_strnadiCountController.toInt()}");
    final rec = Recording(
      createdAt: DateTime.now(),
      estimatedBirdsCount: _strnadiCountController.toInt(),
      device: platform,
      byApp: true,
      note: _commentController.text,
    );


    if (!await hasInternetAccess()) {
      logger.e("No internet connection");
      _showMessage("No internet connection");
      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
    }

    final recordingSign = Uri.parse('https://api.strnadi.cz/recordings/upload');
    final safeStorage = FlutterSecureStorage();
    final token = await safeStorage.read(key: 'token');
    try {
      final response = await http.post(
        recordingSign,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'jwt': token,
          'EstimatedBirdsCount': rec.estimatedBirdsCount,
          "Device": rec.device,
          "ByApp": rec.byApp,
          "Note": rec.note,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 202) {
        final data = jsonDecode(response.body);
        _recordingId = data;
        uploadAudio(File(widget.filepath), _recordingId!);
        logger.i(widget.filepath);
        LocalDb.UpdateStatus(widget.filepath);
      } else {
        logger.w(response);
        Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
      }
    } catch (error) {
      logger.e(error);
      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
    }
    LocalDb.insertRecording(
      rec,
      _recordingNameController.text,
      0,
      widget.filepath,
      widget.currentPosition?.latitude ?? 0,
      widget.currentPosition?.longitude ?? 0,
      widget.recordingParts,
      widget.recordingPartsTimeList,
      widget.startTime,
      _recordingId ?? -1,
    );
    logger.i("inserted into local db");
  }

  // New method to handle each new position update
  void _onNewPosition(Position position) {
    final newPoint = LatLng(position.latitude, position.longitude);
    setState(() {
      markerPosition = newPoint;
      currentLocation = newPoint;
      if (_route.isEmpty) {
        _route.add(newPoint);
      } else {
        final distance = Distance().distance(_route.last, newPoint);
        if (distance > 10) {
          if (_lastRouteUpdate == null ||
              DateTime.now().difference(_lastRouteUpdate!) > const Duration(seconds: 1)) {
            _lastRouteUpdate = DateTime.now();
            _route.add(newPoint);
          } else {
            _route.add(newPoint);
          }
        }
      }
    });
  }

  void seekRelative(int seconds) {
    final newPosition = currentPosition + Duration(seconds: seconds);
    _audioPlayer.seek(newPosition);
  }

  @override
  void dispose() {
    _recordingNameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the last known position as the current location if available
    currentLocation = locationService.lastKnownPosition;

    LatLng? validRecordingPartLocation;
    if (widget.recordingParts.isNotEmpty) {
      final firstPart = widget.recordingParts.first;
      if (firstPart.latitude != 50.1 || firstPart.longitude != 14.4) {
        validRecordingPartLocation = LatLng(firstPart.latitude, firstPart.longitude);
      }
    }

    // Determine the map center based on available data.
    LatLng mapCenter;
    if (_route.isNotEmpty) {
      mapCenter = _route.last;
    } else if (validRecordingPartLocation != null) {
      mapCenter = validRecordingPartLocation;
    } else if (currentLocation != null) {
      mapCenter = currentLocation!;
    } else {
      mapCenter = LatLng(50.1, 14.4);
    }

    final halfScreen = MediaQuery.of(context).size.width * 0.45;

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 300,
              width: double.infinity,
              child: LiveSpectogram.SpectogramLive(
                data: [],
                filepath: widget.filepath,
              ),
            ),
            Text(_formatDuration(totalDuration), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold) ),
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
            const SizedBox(height: 50),
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 13.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                        'https://api.mapy.cz/v1/maptiles/basic/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                        userAgentPackageName: 'cz.delta.strnadi',
                      ),
                      if (_route.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: List.from(_route),
                              strokeWidth: 4.0,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (markerPosition != null)
                            Marker(
                              width: 20.0,
                              height: 20.0,
                              point: markerPosition!,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 30.0,
                              ),
                            ),
                          // Place markers for all recording parts
                          ...widget.recordingParts.map(
                                (part) => Marker(
                              width: 20.0,
                              height: 20.0,
                              point: LatLng(part.latitude, part.longitude),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 30.0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_route.isEmpty &&
                      currentLocation == null &&
                      validRecordingPartLocation == null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: const Center(
                          child: Text(
                            "Error: Location not recorded",
                            style: TextStyle(color: Colors.red, fontSize: 16),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Form(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    TextFormField(
                      controller: _recordingNameController,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Nazev Nahravky',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.text,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      textAlign: TextAlign.center,
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Komentar',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.text,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                    ),
                    Slider(
                      value: _strnadiCountController,
                      min: 1,
                      max: 3,
                      divisions: 2,
                      label: "Pocet Strnadi",
                      onChanged: (value) {
                        setState(() {
                          _strnadiCountController = value;
                        });
                      },
                    ),
                    MultiPhotoUploadWidget(onImagesSelected: _onImagesSelected),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: SizedBox(
                            width: halfScreen,
                            child: ElevatedButton(
                              style: ButtonStyle(
                                shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                ),
                              ),
                              onPressed: upload,
                              child: const Text('Submit'),
                            ),
                          ),
                        ),
                        Padding(

                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: SizedBox(
                            width: halfScreen,
                            child: ElevatedButton(
                              style: ButtonStyle(
                                shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                ),
                              ),
                              onPressed: () {
                                dispose();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => LiveRec()),
                                );
                              },
                              child: const Text('Discard'),
                            ),
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
    );
  }

  void _showMessage(String s) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s),
      ),
    );
  }
}