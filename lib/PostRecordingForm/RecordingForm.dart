/*
 * Copyright (C) 2024 [Your Name]
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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/AudioSpectogram/audioRecorder.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:intl/intl.dart';

import '../AudioSpectogram/editor.dart';

class Recording {
  final DateTime createdAt;
  final int estimatedBirdsCount;
  final String device;
  final bool byApp;
  final String? note;
  final String userId = '0';

  Recording({
    required this.createdAt,
    required this.estimatedBirdsCount,
    required this.device,
    required this.byApp,
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      "CreatedAt": createdAt.toIso8601String(),
      "EstimatedBirdsCount": estimatedBirdsCount,
      "Device": device,
      "ByApp": byApp,
      "Note": note,
      "userId": userId,
    };
  }
}

class RecordingForm extends StatefulWidget {
  final String filepath;
  final LatLng? currentPosition;

  const RecordingForm(
      {Key? key, required this.filepath, required this.currentPosition})
      : super(key: key);

  @override
  _RecordingFormState createState() => _RecordingFormState();
}

class _RecordingFormState extends State<RecordingForm> {
  final _recordingNameController = TextEditingController();
  final _commentController = TextEditingController();
  double _strnadiCountController = 1.0;
  final _photoPathController = TextEditingController();
  int? _recordingId = null;



  Future<String> getDeviceModel() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model; // e.g., "Pixel 6"
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine; // e.g., "iPhone14,2"
    } else {
      return "Unknown Device";
    }
  }


  Future<void> uploadAudio(File audioFile) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('https://strnadiapi.slavetraders.tech/recordings/uploadSound'),
    );

    request.files.add(
      await http.MultipartFile.fromPath('recording', audioFile.path),
    );

    var response = await request.send();

    if (response.statusCode == 200) {
      print('Audio uploaded successfully');
    } else {
      print('Upload failed with status: ${response.statusCode}');
    }
  }


  void Upload() async {
    final recordingSign =
        Uri.parse('http://77.236.222.115:6789/recordings/uploadRec');
    final safeStorage = FlutterSecureStorage();

    var platform = await getDeviceModel();

    final rec = Recording(
        createdAt: DateTime.timestamp(),
        estimatedBirdsCount: _strnadiCountController.toInt(),
        device: platform,
        byApp: true,
        note: _commentController.text
    );

    var token = await safeStorage.read(key: 'token');


    print('token $token');

    print(jsonEncode({
<<<<<<< HEAD
      'token': token,
=======
      'jwt': 'test',
>>>>>>> 00d696e (some small changes)
      'Recording': rec.toJson(),
    }));

    try {
      final response = await http.post(
        recordingSign,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
<<<<<<< HEAD
          'jwt': token,
=======
          'jtw': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6InN0YXNzdHJvbmcwNkBnbWFpbC5jb20iLCJzdWIiOiIxIiwiaXNzIjoiU3RybmFkaUFQSSBTZXJ2ZXIiLCJhdWQiOiJOYXZyYXQgS3JhbGUgLSBtb2JpbG5pIGFwcGthIGEgV0VCIiwibmJmIjoxNzM5MzExNTc3LCJleHAiOjE3Mzk1NzA3NzcsImlhdCI6MTczOTMxMTU3N30.jMY7O-c8vcAzBYjZLf80CH7Ag9xiIOCYN4zyrGnPhZY',
>>>>>>> 00d696e (some small changes)
          'Recording': rec.toJson(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _recordingId = data['id'];

      } else {
        print('Error: ${response.statusCode} ${response.body}');
      }
    } catch (error) {
      print('An error occurred: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
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
                    // if location is null request the location from the user
                    SizedBox(

                      height: 200,
                      child: FlutterMap(
                        options: MapOptions(
                          center: widget.currentPosition,
                          zoom: 13.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.navratKrale.app',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                width: 20.0,
                                height: 20.0,
                                point: widget.currentPosition!,
                                builder: (ctx) => Icon(
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
                            shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                          onPressed: Upload,
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
}
