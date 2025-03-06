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
import 'package:strnadi/database/soundDatabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart'; // Marker layer package
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import 'package:strnadi/localRecordings/recordingsDb.dart';
import '../config/config.dart';

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
  int? _recordingId;

  // List to store the user's route (all recorded locations)
  final List<LatLng> _route = [];
  StreamSubscription<Position>? _positionStreamSub;

  DateTime? _lastRouteUpdate;

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

    print(widget.filepath);

    final uploadPart = Uri.parse('https://api.strnadi.cz/recordings/upload-part');
    final safeStorage = FlutterSecureStorage();
    final token = await safeStorage.read(key: "token");

    print("token $token");

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

    LocalDb.insertRecording(
      rec,
      _recordingNameController.text,
      0,
      widget.filepath,
      widget.currentPosition?.latitude ?? 0,
      widget.currentPosition?.longitude ?? 0,
    );
    logger.i("inserted into local db");

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
  }

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((Position position) {
      LatLng newPoint = LatLng(position.latitude, position.longitude);
      if (_route.isEmpty || Distance().distance(_route.last, newPoint) > 10) {
        if (_lastRouteUpdate == null ||
            DateTime.now().difference(_lastRouteUpdate!) > const Duration(seconds: 1)) {
          _lastRouteUpdate = DateTime.now();
          setState(() {
            _route.add(newPoint);
          });
        } else {
          _route.add(newPoint);
        }
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _recordingNameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check for a valid current position (non-default) and valid recording part.
    LatLng? validCurrentPosition;
    if (widget.currentPosition != null) {
      if (widget.currentPosition!.latitude != 50.1 ||
          widget.currentPosition!.longitude != 14.4) {
        validCurrentPosition = widget.currentPosition;
      }
    }
    LatLng? validRecordingPart;
    if (widget.recordingParts.isNotEmpty) {
      final firstPart = widget.recordingParts.first;
      if (firstPart.latitude != 50.1 || firstPart.longitude != 14.4) {
        validRecordingPart = LatLng(firstPart.latitude, firstPart.longitude);
      }
    }

    // Determine the map center based on available data.
    LatLng mapCenter;
    if (_route.isNotEmpty) {
      mapCenter = _route.last;
    } else if (validCurrentPosition != null) {
      mapCenter = validCurrentPosition;
    } else if (validRecordingPart != null) {
      mapCenter = validRecordingPart;
    } else {
      mapCenter = LatLng(50.1, 14.4);
    }

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
                      // Defensive copy of _route list to avoid concurrent modification errors.
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
                          Marker(
                            width: 20.0,
                            height: 20.0,
                            point: mapCenter,
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
                  if (_route.isEmpty &&
                      validCurrentPosition == null &&
                      validRecordingPart == null)
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: SizedBox(
                        width: double.infinity,
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
