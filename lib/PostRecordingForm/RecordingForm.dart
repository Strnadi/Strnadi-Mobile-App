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

import 'package:strnadi/database/soundDatabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';

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
    this.note = null,
  });

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
  final DateTime StartTime;
  final List<int> recordingPartsTimeList;

  const RecordingForm({
    Key? key,
    required this.filepath,
    required this.StartTime,
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
  int? _recordingId = null;

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
      return androidInfo.model; // e.g., "Pixel 6"
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine; // e.g., "iPhone14,2"
    } else {
      return "Unknown Device";
    }
  }

  Future<void> uploadAudio(File audioFile, int id) async {
    // Trim the audio into segments.
    // DatabaseHelper.trimAudio returns a List<RecordingParts>.
    List<RecordingParts> trimmedAudioParts = await DatabaseHelper.trimAudio(
      widget.filepath,
      widget.recordingPartsTimeList,
      widget.recordingParts,
    );
    
    print(widget.filepath);

    final uploadPart =
    Uri.parse('https://strnadiapi.slavetraders.tech/recordings/upload-part');

    final safeStorage = FlutterSecureStorage();
    final token = await safeStorage.read(key: "token");

    int cumulativeSeconds = 0;

    for (int i = 0; i < trimmedAudioParts.length; i++) {
      // Check if the trimmed segment's path is valid (not null and not empty)
      String? segmentPath = trimmedAudioParts[i].path;
      if (segmentPath == null || segmentPath.isEmpty) {
        logger.e(
            "Trimmed audio segment $i has an invalid (null or empty) path; skipping upload for this segment.");
        continue;
      }

      final segmentFile = File(segmentPath);
      final fileBytes = await segmentFile.readAsBytes();
      final base64Audio = base64Encode(fileBytes);

      // Calculate start and end times for this segment based on cumulative offset.
      int segmentDuration = widget.recordingPartsTimeList[i];
      final segmentStart =
      widget.StartTime.add(Duration(seconds: cumulativeSeconds));
      final segmentEnd =
      segmentStart.add(Duration(seconds: segmentDuration));
      cumulativeSeconds += segmentDuration;

      try {
        final response = await http.post(
          uploadPart,
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'jwt': token,
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

        if (response.statusCode == 200) {
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
      MaterialPageRoute(builder: (context) => RecorderWithSpectogram()),
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

    if (await hasInternetAccess() == false) {
      logger.w("No internet connection");
      _showMessage('No internet connection');
      return;
    }

    final recordingSign = Uri.parse(
        'https://strnadiapi.slavetraders.tech/recordings/upload');
    final safeStorage = FlutterSecureStorage();

    final token = await safeStorage.read(key: 'token');

    print('token $token');

    print(jsonEncode({
      'token': token,
      'Recording': rec.toJson(),
    }));

    try {
      final response = await http.post(
        recordingSign,
        headers: {
          'Content-Type': 'application/json',
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
        print(data);
        _recordingId = data;
        uploadAudio(File(widget.filepath), _recordingId!);
        logger.i(widget.filepath);
      } else {
        logger.w(response);
        print('Error: ${response.statusCode} ${response.body}');
      }
    } catch (error) {
      logger.e(error);
      print('An error occurred: $error');
    }
  }

  @override
  void dispose() {
    _recordingNameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Provide a fallback coordinate if currentPosition is null.
    final fallbackPosition = widget.currentPosition ?? LatLng(50.1, 14.4);
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 100,
              width: MediaQuery.of(context).size.width * 0.70,
              child: SpectrogramWidget(
                filePath: widget.filepath!,
              ),
            ),
            const SizedBox(height: 50),
            Form(
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
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
                    // If location is null, we use fallbackPosition.
                    SizedBox(
                      height: 200,
                      child: FlutterMap(
                        options: MapOptions(
                          center: fallbackPosition,
                          zoom: 13.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.strnadi.cz',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 20.0,
                                height: 20.0,
                                point: fallbackPosition,
                                builder: (ctx) => const Icon(
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ButtonStyle(
                            shape: MaterialStateProperty.all<
                                RoundedRectangleBorder>(
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