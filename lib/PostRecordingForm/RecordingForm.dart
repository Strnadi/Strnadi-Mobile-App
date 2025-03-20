/*
 * RecordingForm.dart
 */

import 'dart:ffi';
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
  Duration currentPosition = Duration.zero;
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
      while (recording.mail.isEmpty) {
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
  }

  void _showDialectSelectionDialog() {
    var position = spectogramKey.currentState!.currentPositionPx;
    var spect = spectogram;
    setState(() {
      spectogram = null;
    });
    showDialog(
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

  Future<void> insertRecordingWhenReady() async {
    while (recording.mail.isEmpty || (recording.device?.isEmpty ?? true)) {
      await Future.delayed(const Duration(seconds: 1));
      logger.i('Waiting for recording to be ready');
    }
    logger.i('Started inserting recording');
    recording.downloaded = true;
    recording.id = await DatabaseNew.insertRecording(recording);
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
    logger.i("Recording before insertion: path=${recording.path}");
    _recordingId = await DatabaseNew.insertRecording(recording);
    logger.i("Recording inserted with ID: $_recordingId, file path: ${recording.path}");
    if (!await hasInternetAccess()) {
      logger.w("No internet connection");
      _showMessage("No internet connection");
      Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
      return;
    }
    // Log number of parts to insert
    logger.i("Uploading ${recordingParts.length} recording parts.");
    for (RecordingPart part in recordingParts) {
      part.recordingId = _recordingId;
      int partId = await DatabaseNew.insertRecordingPart(part);
      logger.i("Inserted part with id: $partId for recording $_recordingId");
    }
    try {
      await DatabaseNew.sendRecordingBackground(recording.id!);
    } catch (e, stackTrace) {
      logger.e("Error sending recording: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
    spectogramKey = GlobalKey();
    Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
  }

  void _onNewPosition(Position position) {
    final newPoint = LatLng(position.latitude, position.longitude);
    setState(() {
      markerPosition = newPoint;
      // Removed currentLocation update to avoid unnecessary rerendering
    });
  }

  void seekRelative(int seconds) {
    final newPosition = currentPosition + Duration(seconds: seconds);
    _audioPlayer.seek(newPosition);
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
    LatLng mapCenter;
    if (recordingParts.isNotEmpty) {
      mapCenter = LatLng(recordingParts[0].gpsLatitudeStart, recordingParts[0].gpsLongitudeStart);
    } else {
      mapCenter = LatLng(0.0, 0.0);
    }
    markerPosition = locationService.lastKnownPosition != null
        ? LatLng(locationService.lastKnownPosition!.latitude, locationService.lastKnownPosition!.longitude)
        : null;
    final halfScreen = MediaQuery.of(context).size.width * 0.45;
    return PopScope(
      canPop: false,
      //onPopInvokedWithResult: Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LiveRec())),
      child: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 300,
                width: double.infinity,
                child: spectogram,
              ),
              Text(_formatDuration(totalDuration), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    FlutterMap(
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
                        // MarkerLayer(
                        //   markers: [
                        //     if (markerPosition != null)
                        //       Marker(
                        //         width: 20.0,
                        //         height: 20.0,
                        //         point: markerPosition!,
                        //         child: const Icon(
                        //           Icons.my_location,
                        //           color: Colors.blue,
                        //           size: 30.0,
                        //         ),
                        //       ),
                        //     ...recordingParts.map(
                        //           (part) => Marker(
                        //         width: 20.0,
                        //         height: 20.0,
                        //         point: LatLng(part.gpsLatitudeEnd, part.gpsLongitudeEnd),
                        //         child: const Icon(
                        //           Icons.location_on,
                        //           color: Colors.red,
                        //           size: 30.0,
                        //         ),
                        //       ),
                        //     ),
                        //   ],
                        // ),
                      ],
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
                        validator: (value) => (value == null || value.isEmpty) ? 'Please enter some text' : null,
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
                        validator: (value) => (value == null || value.isEmpty) ? 'Please enter some text' : null,
                      ),
                      const SizedBox(height: 20),
                      Slider(
                        value: _strnadiCountController,
                        min: 1,
                        max: 3,
                        divisions: 2,
                        label: "Pocet Strnadi",
                        onChanged: (value) => setState(() => _strnadiCountController = value),
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
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
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
                                  shape: MaterialStateProperty.all<RoundedRectangleBorder>(
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                                  ),
                                ),
                                onPressed: () {
                                  spectogramKey = GlobalKey();
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => LiveRec()));
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
      )
    );
  }

  void _showMessage(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
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
    // Compute zoom level based on full world (360°) divided by the extent
    double idealZoom = math.log(360 / maxDiff) / math.ln2;
    // Clamp zoom between 10 and 16 for example
    if (idealZoom < 10) idealZoom = 10;
    if (idealZoom > 16) idealZoom = 16;
    return idealZoom;
  }
}