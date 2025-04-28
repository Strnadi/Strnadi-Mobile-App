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
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;
import 'package:scidart/numdart.dart' as numdart;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/localRecordings/recListItem.dart';
import 'package:strnadi/map/RecordingPage.dart';
import 'package:strnadi/map/mapUtils/recordingParser.dart';
import 'package:strnadi/map/searchBar.dart';
import 'package:strnadi/user/userPage.dart';
import '../config/config.dart';
import 'dart:async';
import 'package:strnadi/locationService.dart'; // Use the location service
import 'package:http/http.dart' as http;

import '../database/databaseNew.dart';


final logger = Logger();
final MAPY_CZ_API_KEY = Config.mapsApiKey;

class MapScreenV2 extends StatefulWidget {
  const MapScreenV2({Key? key}) : super(key: key);

  @override
  State<MapScreenV2> createState() => _MapScreenV2State();
}

class _MapScreenV2State extends State<MapScreenV2> {
  final MapController _mapController = MapController();
  bool _isSatelliteView = false;
  String _recordingAuthorFilter = 'all';
  String _dataFilter = 'new';
  bool _showConqueredSectors = true;
  List<Polyline> _gridLines = [];
  Map<int, String> _dialectMap = {};


  final secureStorage = const FlutterSecureStorage();

  // Store the current camera values.
  LatLng _currentCenter = LatLng(50.0755, 14.4378);
  LatLng _currentPosition = LatLng(50.0755, 14.4378);
  double _currentZoom = 13;

  List<Part> _recordings = [];

  List<Recording> _fullRecordings = [];

  Size? _mapSize;

  // Subscribe to location updates via the centralized service.
  StreamSubscription? _positionStreamSubscription;

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notification'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage("Please enable location services");
        logger.w("Location services are not enabled");
        setState(() {
          _currentPosition = LatLng(50.0755, 14.4378);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w("Location permissions are denied");
          setState(() {
            _currentPosition = LatLng(50.0755, 14.4378);
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.w("Location permissions are permanently denied");
        setState(() {
          _currentPosition = LatLng(50.0755, 14.4378);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      logger.t('current possition initialized');
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentPosition, _currentZoom);
    } catch (e) {
      logger.e(e);
      print("Error retrieving location: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _currentPosition = LatLng(LocationService().lastKnownPosition?.latitude ?? 0.0, LocationService().lastKnownPosition?.longitude ?? 0.0);

    _getCurrentLocation();

    getRecordings();
    _fetchDialects();

    // Subscribe to the centralized location stream.
    _positionStreamSubscription = LocationService().positionStream.listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    });

    _mapController.mapEventStream.listen((event) {
      if (event is MapEventMoveEnd) {
        setState(() {
          _currentCenter = event.camera.center;
          _currentZoom = event.camera.zoom;
        });
        _updateGrid();
      }
    });
  }

  void getRecordings() async {

    try {
      int? userId;
      //String? email;
      if (_recordingAuthorFilter == 'me') {
        final jwt = await secureStorage.read(key: 'token');
        userId = int.parse((await secureStorage.read(key: 'userId'))!);
      }

      final response = await http.get(
        Uri(
          scheme: 'https',
          host: Config.host,
          path: '/recordings',
          queryParameters: {
            'parts': 'true',
            'sound': 'false',
            if (userId != null) 'userId': userId,
          },
        ),
        headers: {
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        logger.i('Recordings fetched');
        List<dynamic> data = jsonDecode(response.body);
        List<Part> parts = getParts(jsonEncode(data));
        setState(() {
          _recordings = parts;
        });
        List<Recording> recordings = await GetRecordings(response.body);
        setState(() {
          _fullRecordings = recordings;
        });
      }
      else {
        logger.e('Failed to fetch recordings ${response.statusCode}');
      }
    }
    catch (error) {
      logger.e(error);
    }
  }

  Future<void> _fetchDialects() async {
    logger.i('Fetching dialects for all parts');
    try {
      final jwt = await secureStorage.read(key: 'token');
      final url = Uri.https(Config.host, '/recordings/filtered');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      });
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final Map<int, String> dialects = {};
        for (final item in data.cast<Map<String, dynamic>>()) {
          final dialectObj = RecordingDialect.fromJson(item);
          final dynamic idValue = item['recordingId'];
          final int id = idValue is int ? idValue : int.tryParse(idValue.toString()) ?? 0;
          dialects[id] = dialectObj.dialect;
        }
        logger.i('Fetched all dialects');
        setState(() {
          _dialectMap = dialects;
        });
      } else {
        logger.w('Dialect fetch failed: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      logger.e('Failed to fetch dialects for all parts: $e', error: e, stackTrace: stackTrace);
    }
  }

  Future<(String?, String?)?> getProfilePic(int? userId_, String? mail) async {
    //var email;
    int? userId;
    final jwt = await secureStorage.read(key: 'token');

    if (mail == null){
      final jwt = await secureStorage.read(key: 'token');
      userId = int.parse((await secureStorage.read(key: 'userId'))!);
      //email = JwtDecoder.decode(jwt!)['sub'];
    }
    else {
      userId = userId_;
      //email = mail;
    }
    final url = Uri.parse(
        'https://${Config.host}/users/${userId}/get-profile-photo');
    logger.i(url);

    try {
      http.get(url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt'
          }).then((value) {
        if (value.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(value.body);
          return (data['photoBase64'], data['format']);
        }else{
          logger.e("Profile picture download failed with status code ${value.statusCode} $url");
          return null;
        }
      });
    }
    catch (e) {
      return null;
    }
    return null;
  }

  Future<UserData?> getUser(Recording rec) async {
    for (int i = 0; i < _fullRecordings.length; i++) {

      logger.i("rec: ${_fullRecordings[i].mail} ${_fullRecordings[i].name}");

    }
    var mail = rec.mail;

    var url = Uri(scheme: 'https', host: Config.host, path: '/users/$mail');

    var jwt = await FlutterSecureStorage().read(key: 'token');

    logger.i("mail: $mail url: $url");

    try{
      final resp = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt'
      }).then((val) => UserData.fromJson(json.decode(val.body)));
      logger.i(resp.NickName);
      // (String?, String?)? profilePicData = await getProfilePic(mail);
      logger.i(resp.NickName);
      return resp;
      // if (profilePicData!.$1 == null || profilePicData.$2 == null){
      //   logger.i(resp);
      //   return resp;
      // }
      // else{
      //   resp.ProfilePic = profilePicData.$1;
      //   resp.format = profilePicData.$2;
      //   return resp;
      // }
    }
    catch(e){
      Sentry.captureException(e, stackTrace: StackTrace.current);
      return null;
    }
  }

  void getRecordingFromPartId(int id) async {
      for (int rec = 0; rec < _fullRecordings.length; rec++) {
          if (_fullRecordings[rec].BEId == id) {
            UserData? user = await getUser(_fullRecordings[rec]);
            logger.i("user is $user");
            List<RecordingPart?> parts = List.empty(growable: true);
            parts.add(await DatabaseNew.getRecordingPartByBEID(_fullRecordings[rec].BEId!));

            logger.i(parts[0]);

            showCupertinoSheet
              (context: context, pageBuilder: (context) => RecordingFromMap(recording: _fullRecordings[rec], user: user,));
            return;
          }
      }

      showDialog(context: context, builder: (context) => AlertDialog(
        title: const Text('Chyba'),
        content: Text('Nahrávka nenalezena $id'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zavřít'),
          ),
        ],
      ));
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.map,
      appBarTitle: null,
      content: LayoutBuilder(
        builder: (context, constraints) {
          Size newSize = constraints.biggest;
          if (_mapSize == null || _mapSize != newSize) {
            _mapSize = newSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateGrid();
            });
          }
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,

                options: MapOptions(
                  initialCenter: _currentPosition,
                  initialZoom: 13,
                  interactionOptions: InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  minZoom: 1,
                  maxZoom: 19,
                  initialRotation: 0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                    'https://api.mapy.cz/v1/maptiles/${_isSatelliteView ? 'aerial' : 'outdoor'}/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                    userAgentPackageName: 'cz.delta.strnadi',
                  ),
                  if (_isSatelliteView)
                    TileLayer(
                      urlTemplate:
                      'https://api.mapy.cz/v1/maptiles/names-overlay/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                      userAgentPackageName: 'cz.delta.strnadi',
                    ),
                  PolylineLayer(
                    polylines: _gridLines,
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 20.0,
                        height: 20.0,
                        point: _currentPosition,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 30.0,
                        ),
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: _recordings
                        .map((part) => Marker(
                      width: 30.0,
                      height: 30.0,
                      point: LatLng(part.gpsLatitudeStart, part.gpsLongitudeStart),
                      child: GestureDetector(
                        onTap: () {
                          getRecordingFromPartId(part.recordingId);
                        },
                        child: Image.asset(
                          'assets/dialects/${_dialectMap[part.recordingId] ?? 'Nevyhodnoceno'}.png',
                          width: 30.0,
                          height: 30.0,
                        ),
                      ),
                    ))
                        .toList(),
                  )

                ],
              ),
              Positioned(
                top: 36,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final height = 48.0; // match the SearchBar height
                        return SizedBox(
                          width: height,
                          height: height,
                          child: FloatingActionButton(
                            heroTag: 'info',
                            mini: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: Colors.white,
                              onPressed: _showLegendDialog,
                            child: Image.asset('assets/icons/info.png', width: 30, height: 30),
                            tooltip: 'Info',
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SearchBarWidget(
                        onLocationSelected: (LatLng location) {
                          _mapController.move(location, _currentZoom);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: FloatingActionButton(
                        heroTag: 'mapSettings',
                        mini: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset('assets/icons/sort.png', width: 24, height: 24),
                        backgroundColor: Colors.white,
                        onPressed: _openMapFilter,
                        tooltip: 'Map Settings',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: FloatingActionButton(
                        heroTag: 'reset',
                        mini: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tooltip: 'Reset orientation & recenter',
                        onPressed: () async {
                          await _getCurrentLocation();
                          _mapController.move(_currentPosition, _currentZoom);
                          _updateGrid();
                        },
                        child: Image.asset('assets/icons/location.png', width: 24, height: 24),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 2, horizontal: 4),
                  color: Colors.white70,
                  child: const Text(
                    'Mapy.cz © Seznam.cz, a.s.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Offset latLngToPixel(LatLng latlng, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double x = (latlng.longitude + 180) / 360 * nTiles * tileSize;
    double latRad = latlng.latitude * math.pi / 180;
    double y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            nTiles *
            tileSize;
    return Offset(x, y);
  }

  LatLng pixelToLatLng(Offset pixel, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double lon = pixel.dx / (nTiles * tileSize) * 360 - 180;
    double yTile = pixel.dy / (nTiles * tileSize);
    double latRad = math.atan(numdart.sinh(math.pi * (1 - 2 * yTile)));
    double lat = latRad * 180 / math.pi;
    return LatLng(lat, lon);
  }

  LatLngBounds calculateBounds() {
    if (_mapSize == null) return LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    Offset centerPixel = latLngToPixel(_currentCenter, _currentZoom);
    double width = _mapSize!.width;
    double height = _mapSize!.height;
    Offset topLeftPixel = centerPixel - Offset(width / 2, height / 2);
    Offset bottomRightPixel = centerPixel + Offset(width / 2, height / 2);
    LatLng topLeft = pixelToLatLng(topLeftPixel, _currentZoom);
    LatLng bottomRight = pixelToLatLng(bottomRightPixel, _currentZoom);
    return LatLngBounds(
      LatLng(bottomRight.latitude, topLeft.longitude),
      LatLng(topLeft.latitude, bottomRight.longitude),
    );
  }

  void _updateGrid() {
    if (_currentZoom < 7) {
      setState(() {
        _gridLines = [];
      });
      return;
    }
    if (_mapSize == null) return;
    final bounds = calculateBounds();
    final double northBound = bounds.north;
    final double southBound = bounds.south;
    final double westBound = bounds.west;
    final double eastBound = bounds.east;

    const double gridCellHeight = 6 / 60;
    const double gridCellWidth = 10 / 60;
    // The fixed top left (origin) of the grid:
    const double originLat = 56.0; // 56°0'N
    const double originLon = 5 + 40 / 60; // 5°40'E, i.e. ~5.666667

    List<Polyline> newGridLines = [];

    int kStartLon = ((westBound - originLon) / gridCellWidth).ceil();
    for (int k = kStartLon;; k++) {
      double gridLon = originLon + k * gridCellWidth;
      if (gridLon > eastBound) break;
      newGridLines.add(Polyline(
        points: [LatLng(northBound, gridLon), LatLng(southBound, gridLon)],
        strokeWidth: 1.0,
        color: Colors.red,
      ));
    }

    int kStartLat = ((originLat - northBound) / gridCellHeight).floor();
    for (int k = kStartLat;; k++) {
      double gridLat = originLat - k * gridCellHeight;
      if (gridLat < southBound) break;
      newGridLines.add(Polyline(
        points: [LatLng(gridLat, westBound), LatLng(gridLat, eastBound)],
        strokeWidth: 1.0,
        color: Colors.red,
      ));
    }

    setState(() {
      _gridLines = newGridLines;
    });
  }


  void _openMapFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.2,
          maxChildSize: 0.9,
          builder: (BuildContext context, ScrollController controller) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setModalState) {
                  return ListView(
                    controller: controller,
                    children: [
                      Container(
                        alignment: Alignment.center,
                        child: Container(
                          width: 80,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text(
                          'Nastavení mapy',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Zobrazení mapy:'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _isSatelliteView = false;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(color: !_isSatelliteView ? Colors.black : Colors.grey.shade200),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                  ),
                                  child: const Text('Klasické'),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _isSatelliteView = true;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(color: _isSatelliteView ? Colors.black : Colors.grey.shade200),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                  ),
                                  child: const Text('Letecké'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Autor nahrávky:'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _recordingAuthorFilter = 'all';
                                    });
                                    setState(() {
                                      _recordings.clear();
                                      _fullRecordings.clear();
                                    });
                                    getRecordings();
                                  },
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(color: _recordingAuthorFilter == 'all' ? Colors.black : Colors.grey.shade200),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                  ),
                                  child: const Text('Všichni'),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _recordingAuthorFilter = 'me';
                                    });
                                    setState(() {
                                      _recordings.clear();
                                      _fullRecordings.clear();
                                    });
                                    getRecordings();
                                  },
                                  style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(color: _recordingAuthorFilter == 'me' ? Colors.black : Colors.grey.shade200),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                  ),
                                  child: const Text('Pouze já'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // const SizedBox(height: 8),
                      // Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                      //     const Text('Data:'),
                      //     const SizedBox(height: 8),
                      //     Row(
                      //       children: [
                      //         Padding(
                      //           padding: EdgeInsets.only(right: 8),
                      //           child: OutlinedButton(
                      //             onPressed: () {
                      //               setModalState(() {
                      //                 _dataFilter = 'new';
                      //               });
                      //             },
                      //             style: OutlinedButton.styleFrom(
                      //                 backgroundColor: Colors.transparent,
                      //                 side: BorderSide(color: _dataFilter == 'new' ? Colors.black : Colors.grey.shade200),
                      //                 foregroundColor: Colors.black,
                      //                 shape: RoundedRectangleBorder(
                      //                   borderRadius: BorderRadius.circular(12),
                      //                 ),
                      //             ),
                      //             child: const Text('Nová'),
                      //           ),
                      //         ),
                      //         Padding(
                      //           padding: EdgeInsets.only(right: 8),
                      //           child: OutlinedButton(
                      //             onPressed: () {
                      //               setModalState(() {
                      //                 _dataFilter = '2017';
                      //               });
                      //             },
                      //             style: OutlinedButton.styleFrom(
                      //                 backgroundColor: Colors.transparent,
                      //                 side: BorderSide(color: _dataFilter == '2017' ? Colors.black : Colors.grey.shade200),
                      //                 foregroundColor: Colors.black,
                      //                 shape: RoundedRectangleBorder(
                      //                   borderRadius: BorderRadius.circular(12),
                      //                 ),
                      //             ),
                      //             child: const Text('2017'),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ],
                      // ),
                      // Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                      //     const Text('Dobyté sektory:'),
                      //     const SizedBox(height: 8),
                      //     Row(
                      //       children: [
                      //         Padding(
                      //           padding: EdgeInsets.only(right: 8),
                      //           child: OutlinedButton(
                      //             onPressed: () {
                      //               setModalState(() {
                      //                 _showConqueredSectors = true;
                      //               });
                      //             },
                      //             style: OutlinedButton.styleFrom(
                      //                 backgroundColor: Colors.transparent,
                      //                 side: BorderSide(color: _showConqueredSectors == true ? Colors.black : Colors.grey.shade200),
                      //                 foregroundColor: Colors.black,
                      //                 shape: RoundedRectangleBorder(
                      //                   borderRadius: BorderRadius.circular(12),
                      //                 ),
                      //             ),
                      //             child: const Text('Zobrazit'),
                      //           ),
                      //         ),
                      //         Padding(
                      //           padding: EdgeInsets.only(right: 8),
                      //           child: OutlinedButton(
                      //             onPressed: () {
                      //               setModalState(() {
                      //                 _showConqueredSectors = false;
                      //               });
                      //             },
                      //             style: OutlinedButton.styleFrom(
                      //                 backgroundColor: Colors.transparent,
                      //                 side: BorderSide(color: _showConqueredSectors == false ? Colors.black : Colors.grey.shade200),
                      //                 foregroundColor: Colors.black,
                      //                 shape: RoundedRectangleBorder(
                      //                   borderRadius: BorderRadius.circular(12),
                      //                 ),
                      //             ),
                      //             child: const Text('Skrýt'),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ],
                      // ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () {
                                setModalState(() {
                                  _isSatelliteView = false;
                                  _recordingAuthorFilter = 'all';
                                });
                              },
                              child: const Text('Resetovat'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                shadowColor: Colors.transparent,
                                backgroundColor: const Color(0xFFFFD641),
                                foregroundColor: const Color(0xFF2D2B18),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.0),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  // Apply filters if needed.
                                });
                                Navigator.pop(context);
                              },
                              child: const Text('Filtrovat'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  int _latToTileY(double lat, int zoom) {
    double latRad = lat * math.pi / 180;
    double nTiles = math.pow(2, zoom).toDouble();
    double y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            nTiles;
    return y.floor();
  }

  double _tileYToLat(int y, int zoom) {
    double nTiles = math.pow(2, zoom).toDouble();
    double n = math.pi * (1 - 2 * y / nTiles);
    double latRad = math.atan(numdart.sinh(n));
    return latRad * 180 / math.pi;
  }

  void _showLegendDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                const Text(
                  'Legenda',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 16),

                Center(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildDialectLegendItem('BC'),
                      _buildDialectLegendItem('BE'),
                      _buildDialectLegendItem('BlBh'),
                      _buildDialectLegendItem('BhBl'),
                      _buildDialectLegendItem('XB'),
                      _buildDialectLegendItem('Vzácné'),
                      _buildDialectLegendItem('Přechodný'),
                      _buildSymbolLegendItem('Mix', 'Mix'),
                      _buildSymbolLegendItem('Atypický', 'Atypický'),
                      _buildSymbolLegendItem('Nedokončený', 'Nedokončený'),
                      _buildSymbolLegendItem('Nevyhodnoceno', 'Nevyhodnoceno'),
                      _buildCircleLegendItem(Colors.black, 'Nepoužitelný'),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: const Color(0xFFFFD641),
                        foregroundColor: const Color(0xFF2D2B18),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: const Text('Zavřít'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegendItem(IconData icon, String description) {
    return Row(
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 8),
        Text(description),
      ],
    );
  }

  Widget _buildColoredLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(right: 8, bottom: 8),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.black), // Added black border
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        Text(label),
      ],
    );
  }

  Widget _buildSymbolLegendItem(String assetName, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            "assets/dialects/$assetName.png",
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildDialectLegendItem(String dialectName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            "assets/dialects/${dialectName}.png",
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 6),
          Text(dialectName),
        ],
      ),
    );
  }

  Widget _buildCircleLegendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Text(label),
        ],
      ),
    );
  }
}