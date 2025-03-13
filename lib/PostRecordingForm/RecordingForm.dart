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
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:strnadi/PostRecordingForm/imageUpload.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
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

final MAPY_CZ_API_KEY = Config.mapsApiKey;
final logger = Logger();

/*
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
 */

class RecordingForm extends StatefulWidget {
  final String filepath;
  final LatLng? currentPosition;
  final List<RecordingPartUnready> recordingParts;
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

  late Recording recording;
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

    final safeStorage = FlutterSecureStorage();

    recording = Recording(
      createdAt: DateTime.now(),
      mail: "",
      estimatedBirdsCount: _strnadiCountController.toInt(),
      device: "",
      byApp: true,
      note: _commentController.text,
    );

    safeStorage.read(key: 'token').then((token) async{
      if(token == null){
        _showMessage('You are not logged in');
      }
      while(recording == null){
        await Future.delayed(Duration(seconds: 1));
      }
      recording.mail = JwtDecoder.decode(token!)['sub'];
      logger.i('Mail set to ${recording.mail}');
    });

    getDeviceModel().then((model) async{
      while (recording == null){
        await Future.delayed(Duration(seconds: 1));
      }
      recording.device = model;
      logger.i('Device set to ${recording.device}');
    });

    insertRecordingWhenReady();
  }
  
  Future<void> insertRecordingWhenReady() async{
    while(recording.mail == "" || recording.device == ""){
      await Future.delayed(Duration(seconds: 1));
      logger.i('Waiting for recording to be ready');
    }
    logger.i('Started inserting recording');
    recording.downloaded = true;
    recording.id = await DatabaseNew.insertRecording(recording);
    setState(() {
      _recordingId = recording.id;
    });
    logger.i('ID set to $_recordingId');
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
    List<RecordingPartUnready> trimmedAudioParts = await DatabaseNew.trimAudio(
      widget.filepath,
      widget.recordingPartsTimeList,
      widget.recordingParts,
    );

    List<RecordingPart> partsReady = List<RecordingPart>.empty(growable: true);

    logger.i('Recording: ${recording.id} has been sent');

    int cumulativeSeconds = 0;
    for (int i = 0; i < trimmedAudioParts.length; i++) {
      if (trimmedAudioParts[i].dataBase64?.isEmpty ?? false) {
        logger.e(
            "Trimmed audio segment $i has data; skipping upload for this segment.");
        continue;
      }
      final base64Audio = trimmedAudioParts[i].dataBase64;
      int segmentDuration = widget.recordingPartsTimeList[i];
      final segmentStart = widget.startTime.add(
          Duration(seconds: cumulativeSeconds));
      final segmentEnd = segmentStart.add(Duration(seconds: segmentDuration));
      cumulativeSeconds += segmentDuration;
      try {
        trimmedAudioParts[i].recordingId = id;
        trimmedAudioParts[i].startTime = segmentStart;
        trimmedAudioParts[i].endTime = segmentEnd;
        if(trimmedAudioParts[i].gpsLatitudeStart == null || trimmedAudioParts[i].gpsLongitudeStart == null){
          throw InvalidPartException("Part ${trimmedAudioParts[i].id} has null start latitude or longitude", trimmedAudioParts[i].id??-1);
        }
        if(trimmedAudioParts[i].gpsLongitudeEnd == null || trimmedAudioParts[i].gpsLatitudeEnd == null){
          logger.w('Part ${trimmedAudioParts[i].id} has null end latitude or longitude');
          if(locationService.lastKnownPosition == null){
            try {
              await locationService.checkLocationWorking();
            }
            catch (e){
              if(e is LocationException) {
                if (!e.permission) {
                  logger.e("Error while getting location permissions: $e");
                  _showMessage(
                      'Lokace musí být povolena pro správné fungování aplikace');
                  Navigator.pop(context);
                }
                if(!e.enabled){
                  logger.e("Error while getting location permissions: $e");
                  _showMessage(
                      'Lokace musí být zapnuta pro správné fungování aplikace');
                  while(!await locationService.isLocationEnabled()){
                    await Future.delayed(Duration(seconds: 1));
                    _showMessage('Lokace musí být zapnuta pro správné fungování aplikace');
                  }
                }
              }
              continue;
            }
            await locationService.getCurrentLocation();
          }
          trimmedAudioParts[i].gpsLongitudeEnd = locationService.lastKnownPosition?.longitude;
          trimmedAudioParts[i].gpsLatitudeEnd = locationService.lastKnownPosition?.latitude;
        }
        final part = RecordingPart.fromUnready(trimmedAudioParts[i]);
        part.id = await DatabaseNew.insertRecordingPart(part);
        partsReady.add(part);
      }
      catch(e){
        logger.e("Error while converting RecordingPartUnready to RecordingPart: $e");
        if(e is InvalidPartException){
          _showMessage('Part ${trimmedAudioParts[i].id??-1} was not sent successfully (corrupted metadata)');
        }
        else {
          _showMessage('Part ${trimmedAudioParts[i].id??-1} was not sent successfully (unknown error)');
        }
        Sentry.captureException(e);
        continue;
      }
    }

    await DatabaseNew.sendRecordingBackground(recording.id!);
      /*
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
     */
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
    logger.i("Estimated birds count: ${_strnadiCountController.toInt()}");

    recording.note = _commentController.text == ''? null : _commentController.text;
    recording.name = _recordingNameController.text == ''? null : _recordingNameController.text;
    recording.estimatedBirdsCount = _strnadiCountController.toInt();
    DatabaseNew.insertRecording(recording);

    if (!await hasInternetAccess()) {
      logger.e("No internet connection");
      _showMessage("No internet connection");
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => LiveRec()));
    }

    try {
      await DatabaseNew.sendRecordingBackground(recording.id!);
    }
    catch(e){
      logger.e(e);
      Sentry.captureException(e);
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
    /*
    try {
      final response = await http.post(
        recordingUrl,
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
  */
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

    if(_recordingId == null){
      return Center(
        child: CircularProgressIndicator(),
      );
    }
    List<RecordingPart> recordingParts = DatabaseNew.getPartsById(_recordingId!);

    if(recordingParts.isNotEmpty){
      recordingParts.forEach((part){
        _route.add(LatLng(part.gpsLongitudeStart, part.gpsLatitudeStart));
        _route.add(LatLng(part.gpsLongitudeEnd, part.gpsLatitudeEnd));
      });
    }

    // Determine the map center based on available data.
    LatLng mapCenter;
    if (_route.isNotEmpty) {
      mapCenter = _route.last;
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
                        'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
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
                          ...recordingParts.map(
                                (part) => Marker(
                              width: 20.0,
                              height: 20.0,
                              point: LatLng(part.gpsLatitudeEnd, part.gpsLongitudeEnd),
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
                      currentLocation == null)
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