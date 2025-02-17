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

import 'package:strnadi/database/soundDatabase.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'package:strnadi/home.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:strnadi/database/soundDatabase.dart';

import '../AudioSpectogram/editor.dart';

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

  const RecordingForm(
      {Key? key, required this.filepath, required this.StartTime, required this.currentPosition, required this.recordingParts, required this.recordingPartsTimeList})
      : super(key: key);

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
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return androidInfo.model; // e.g., "Pixel 6"
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine; // e.g., "iPhone14,2"
    } else {
      return "Unknown Device";
    }
  }



  Future<void> uploadAudio(File audioFile, int id) async {

    // extract this to a method and trim it and than in a for call the upload
    var trimmedAudo = await DatabaseHelper.trimAudio(widget.filepath, widget.recordingPartsTimeList, widget.recordingParts);

    final uploadPart =
    Uri.parse('https://strnadiapi.slavetraders.tech/recordings/upload-part');

    var safeStorage = FlutterSecureStorage();

    var token = await safeStorage.read(key: "token");

    for (int i = 0; i < trimmedAudo.length - 1; i++) {

      List<int> fileBytes = await audioFile.readAsBytes();

      String base64Audio = base64Encode(fileBytes);

      try {
        final response = await http.post(
          uploadPart,
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'jwt': token,
            'RecordingId': id,
            "Start": widget.StartTime.toIso8601String(),
            "End": widget.StartTime.add(Duration(seconds: widget.recordingPartsTimeList[i])).toIso8601String(),
            "LatitudeStart": widget.recordingParts[i].latitude,
            "LongitudeStart": widget.recordingParts[i].longtitute,
            "LatitudeEnd": widget.recordingParts[i].latitude,
            "LongitudeEnd": widget.recordingParts[i].longtitute,
            "data": base64Audio
          }),
        );

        if (response.statusCode == 200) {
          print('upload was successful');
          _showMessage("upload was successful");
          Navigator.push(context, MaterialPageRoute(builder: (context) => HomePage()));
        } else {
          print('Error: ${response.statusCode} ${response.body}');
          _showMessage("upload was not successful");
        }
      } catch (error) {
        _showMessage("failed to upload ${error}");
      }
    }
  }



  void Upload() async {

    var platform = await getDeviceModel();

    print("estimated birds count: ${_strnadiCountController.toInt()}");
    final rec = Recording(
        createdAt: DateTime.timestamp(),
        estimatedBirdsCount: _strnadiCountController.toInt(),
        device: platform,
        byApp: true,
        note: _commentController.text
    );

    if (await hasInternetAccess() == false) {
      _showMessage('No internet connection');
      insertSound(
          widget.filepath,
          rec.estimatedBirdsCount as String,
          rec.createdAt as double,
          rec.note as double,
          widget.currentPosition!.latitude as int,
          widget.currentPosition!.longitude as String
      );
    }

    final recordingSign =
        Uri.parse('https://strnadiapi.slavetraders.tech/recordings/upload');
    final safeStorage = FlutterSecureStorage();



    var token = await safeStorage.read(key: 'token');


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

  void _showMessage(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
    ));
  }
}
