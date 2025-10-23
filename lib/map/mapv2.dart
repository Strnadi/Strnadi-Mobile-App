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

import 'package:strnadi/localization/localization.dart';
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
import '../dialects/ModelHandler.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';

final logger = Logger();
final MAPY_CZ_API_KEY = Config.mapsApiKey;

/// Global switch that decides whether recordings whose dialect is still
/// unconfirmed (“Nevyhodnoceno”) are shown on the map.
bool showUnconfirmedDialects = false;

class MapScreenV2 extends StatefulWidget {
  const MapScreenV2({Key? key}) : super(key: key);

  @override
  State<MapScreenV2> createState() => _MapScreenV2State();
}

class _MapScreenV2State extends State<MapScreenV2> {

  /// Loads filtered recording parts from the public BE endpoint instead of the local DB cache.
  /// When [verified] is true, the BE returns only FRPs with workflow states indicating verification (1 or 2).
  /// When false, the BE can return also unverified FRPs.
  Future<({List<FilteredRecordingPart> frps, List<DetectedDialect> dds})> _fetchFilteredPartsFromApi({
    int? recordingId,
    required bool verified,
  }) async {
    try {
      final uri = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/filtered',
        queryParameters: {
          if (recordingId != null) 'recordingId': recordingId.toString(),
          'verified': verified.toString(),
        },
      );
      logger.i('[MapV2] GET ' + uri.toString());
      final resp = await http.get(uri, headers: {
        'Content-Type': 'application/json',
      });

      if (resp.statusCode == 204) {
        logger.i('[MapV2] /recordings/filtered returned 204 No Content');
        return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
      }
      if (resp.statusCode != 200) {
        logger.e('[MapV2] /recordings/filtered failed: ' + resp.statusCode.toString() + ' body=' + resp.body);
        return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
      }

      final List<dynamic> jsonArr = jsonDecode(resp.body) as List<dynamic>;
      final frps = <FilteredRecordingPart>[];
      final dds = <DetectedDialect>[];

      for (final item in jsonArr) {
        if (item is! Map<String, dynamic>) continue;
        final frp = FilteredRecordingPart.fromBEJson(item);
        frps.add(frp);

        final List<dynamic>? dialects = item['detectedDialects'] as List<dynamic>?;
        if (dialects != null) {
          for (final d in dialects) {
            if (d is! Map<String, dynamic>) continue;
            final row = DetectedDialect.fromBEJson(d, parentFilteredPartBEID: frp.BEId ?? -1);
            dds.add(row);
          }
        }
      }

      logger.i('[MapV2] /recordings/filtered parsed: FRPs=' + frps.length.toString() + ', DDs=' + dds.length.toString());
      return (frps: frps, dds: dds);
    } catch (e, st) {
      logger.e('[MapV2] /recordings/filtered exception: ' + e.toString(), error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
      return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
    }
  }
  final MapController _mapController = MapController();
  bool _isSatelliteView = false;
  String _recordingAuthorFilter = 'all';
  String _dataFilter = 'new';
  bool _showConqueredSectors = true;
  bool _showUnconfirmedDialects = showUnconfirmedDialects;
  List<Polyline> _gridLines = [];
  Map<int, List<String>> _dialectsByRecording = {};

  final secureStorage = const FlutterSecureStorage();

  // Store the current camera values.
  LatLng _currentCenter = LatLng(50.0755, 14.4378);
  LatLng _currentPosition = LatLng(50.0755, 14.4378);
  double _currentZoom = 13;

  List<Part> _recordings = [];

  List<Recording> _fullRecordings = [];

  late int length = 0;

  Size? _mapSize;

  late bool _isGuestUser = false;

  // Subscribe to location updates via the centralized service.
  StreamSubscription? _positionStreamSubscription;

  Future<void> _loadGuestStatus() async {
    final storage = const FlutterSecureStorage();
    final userId = await storage.read(key: 'userId');
    if (!mounted) return;
    setState(() {
      _isGuestUser = userId == null || userId.isEmpty;
    });
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.notification.title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('auth.buttons.ok')),
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
    } catch (e,stackTrace) {
      logger.e("Error retrieving location: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e ,stackTrace: stackTrace);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGuestStatus();
    _currentPosition = LatLng(
        LocationService().lastKnownPosition?.latitude ?? 0.0,
        LocationService().lastKnownPosition?.longitude ?? 0.0);

    _getCurrentLocation();

    getRecordings().then((_) => _fetchDialects());

    // Subscribe to the centralized location stream.
    _positionStreamSubscription =
        LocationService().positionStream.listen((Position position) {
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

  Future<void> getRecordings() async {
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
            if (userId != null) 'userId': userId.toString(),
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

        for (int i = 0; i < parts.length; i++) {
          length += parts[i].length ?? 0;
        }
        setState(() {
          _recordings = parts;
        });
        logger.i('[MapV2] getRecordings(): parts=${parts.length}, totalLength=$length');
        List<Recording> recordings = await GetRecordings(response.body);
        setState(() {
          _fullRecordings = recordings;
        });
        logger.i('[MapV2] getRecordings(): fullRecordings=${recordings.length}');
        await _fetchDialects();
      }
      else {
        logger.e('Failed to fetch recordings ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      logger.e("Error generariong map ${error}",error:error, stackTrace: stackTrace);
    }
  }

  Future<void> _fetchDialects() async {
    try {
      // Snapshot sizes for quick diagnosis
      logger.i('[MapV2] _fetchDialects(): start; fullRecs=' + _fullRecordings.length.toString() +
          ', showUnconfirmed=' + _showUnconfirmedDialects.toString());

      // Pull filtered parts from BE (global), not from local DB cache
      final bool verifiedOnly = !_showUnconfirmedDialects; // hide unconfirmed => ask BE for verified only
      final api = await _fetchFilteredPartsFromApi(
        // We call once globally to avoid N calls per recording. If needed, we can later scope by recordingId.
        verified: verifiedOnly,
      );
      final frps = api.frps; // List<FilteredRecordingPart>
      final dds = api.dds;   // List<DetectedDialect>

      logger.i('[MapV2] _fetchDialects(): fetched from BE; FRPs=' + frps.length.toString() + ', DDs=' + dds.length.toString());

      final Map<int, List<String>> byRecording = {};
      int recsWithNoCodes = 0;

      for (final rec in _fullRecordings) {
        final int? beId = rec.BEId;
        if (beId == null) {
          logger.w('[MapV2] rec has null BEId, skipping');
          continue;
        }

        // Only representative filtered parts for this recording (by BE id)
        final reps = frps.where((f) => f.recordingBEID == beId && f.isRepresentant).toList();
        logger.d('[MapV2] recBE=' + beId.toString() + ': representative FRPs=' + reps.length.toString());

        final codes = <String>{};
        for (final frp in reps) {
          final frpDesc = 'FRP be=' + (frp.BEId?.toString() ?? 'null') +
              ' state=' + frp.state.toString();

          // Join detected dialects by BE link
          final rows = dds.where((d) => (frp.BEId != null && d.filteredPartBEID == frp.BEId)).toList();
          logger.d('[MapV2]   ' + frpDesc + ' -> dialectRows=' + rows.length.toString());

          for (final d in rows) {
            final String? confirmed = d.confirmedDialect;
            final String? guessed = d.userGuessDialect;
            final String? chosen = _showUnconfirmedDialects ? (confirmed ?? guessed) : confirmed;
            logger.v('[MapV2]     dialectRow be=' + (d.BEId?.toString() ?? 'null') +
                ' confirmed=' + (confirmed ?? '-') + ' guessed=' + (guessed ?? '-') +
                ' chosen=' + (chosen ?? '-'));
            if (chosen != null && chosen.trim().isNotEmpty) {
              codes.add(chosen.trim());
            }
          }
        }

        // Fallback when no codes collected
        List<String> out;
        if (codes.isEmpty) {
          recsWithNoCodes++;
          logger.w('[MapV2] recBE=' + beId.toString() + ': no dialect codes collected; fallback=Neurceno (repFRPs=' + reps.length.toString() + ')');
          out = <String>['Neurceno'];
        } else {
          out = codes
              .map((c) => (c == 'Neurceno' || c == 'Nevyhodnoceno') ? 'Neznámý' : c)
              .where((c) => c.trim().isNotEmpty)
              .toSet()
              .toList();
          logger.i('[MapV2] recBE=' + beId.toString() + ': codes=[' + out.join(',') + ']');
        }

        byRecording[beId] = out.isEmpty ? <String>['Neznámý'] : out;
      }

      setState(() {
        _dialectsByRecording = byRecording;
      });
      logger.i('[MapV2] _fetchDialects(): done; records=' + byRecording.length.toString() +
          ', emptyOrUnknown=' + recsWithNoCodes.toString());
    } catch (e, stackTrace) {
      logger.e('Failed to fetch representative dialects: ' + e.toString(), error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  List<String> _dialectsForRecordingId(int recordingBEId) {
    final list = _dialectsByRecording[recordingBEId];
    if (list == null || list.isEmpty) return const ['Neznámý'];
    return list
        .map((c) => (c == 'Neurceno' || c == 'Nevyhodnoceno') ? 'Neznámý' : c)
        .toSet()
        .toList();
  }

  List<Marker> _buildRecordingMarkers() {
    logger.i('[MapV2] _buildRecordingMarkers(): parts=' + _recordings.length.toString());
    // Keep only the last part we saw for each recordingId (assuming parts arrive in chronological order)
    final Map<int, Part> lastPartByRecording = {};
    for (final p in _recordings) {
      lastPartByRecording[p.recordingId] = p; // last wins
    }
    logger.i('[MapV2] unique recordings for markers=' + lastPartByRecording.length.toString());

    final markers = <Marker>[];
    lastPartByRecording.forEach((recId, part) {
      final point = LatLng(part.gpsLatitudeStart, part.gpsLongitudeStart);
      final dList = _dialectsForRecordingId(recId);
      logger.i('[MapV2] marker recId=' + recId.toString() + ' lat=' + part.gpsLatitudeStart.toString() + ' lon=' + part.gpsLongitudeStart.toString() + ' dialects=' + dList.join(','));
      final dialects = dList;
      markers.add(
        Marker(
          width: 30.0,
          height: 30.0,
          point: point,
          child: GestureDetector(
            onTap: () {
              getRecordingFromPartId(recId);
            },
            child: SizedBox(
              width: 30.0,
              height: 30.0,
              child: Center(
                child: DynamicIcon(
                  key: ValueKey('rec_${recId}_${dialects.join('+')}'),
                  icon: Icons.circle,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  dialects: dialects, // <- array, e.g. ['BC','XB'] or ['Neznámý']
                ),
              ),
            ),
          ),
        ),
      );
    });

    return markers;
  }

  Future<(String?, String?)?> getProfilePic(int? userId_) async {
    //var email;
    int? userId;
    final jwt = await secureStorage.read(key: 'token');

    userId = userId_;
    final url =
        Uri.parse('https://${Config.host}/users/${userId}/get-profile-photo');
    logger.i(url);

    try {
      http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt'
      }).then((value) {
        if (value.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(value.body);
          return (data['photoBase64'], data['format']);
        } else {
          logger.e(
              "Profile picture download failed with status code ${value.statusCode} $url");
          return null;
        }
      });
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<UserData?> getUser(Recording rec) async {
    for (int i = 0; i < _fullRecordings.length; i++) {

      logger.i("rec: ${_fullRecordings[i].mail} ${_fullRecordings[i].name} ${_fullRecordings[i].id}");

    }
    var mail = rec.userId;

    var url = Uri(scheme: 'https', host: Config.host, path: '/users/$mail');

    var jwt = await FlutterSecureStorage().read(key: 'token');

    logger.i("mail: $mail url: $url");

    try {
      final resp = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt'
      }).then((val) => UserData.fromJson(json.decode(val.body)));
      (String?, String?)? profilePicData = await getProfilePic(mail);
      logger.i(resp);
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
    } catch (e) {
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
        parts.add(await DatabaseNew.getRecordingPartByBEID(
            _fullRecordings[rec].BEId!));

        logger.i(parts[0]);

        showCupertinoSheet(
            context: context,
            pageBuilder: (context) => RecordingFromMap(
                  recording: _fullRecordings[rec],
                  user: user,
                ));
        return;
      }
    }

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(t('map.dialogs.error.title')),
              content: Text('${t('Nahrávka nenalezena')} $id'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('map.dialogs.error.close')),
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
      isGuestUser: _isGuestUser,
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
                  interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
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
                    markers: _buildRecordingMarkers(),
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
                            tooltip: 'Info',
                            child: Image.asset('assets/icons/info.png',
                                width: 30, height: 30),
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
                        backgroundColor: Colors.white,
                        onPressed: _openMapFilter,
                        tooltip: 'Map Settings',
                        child: Image.asset('assets/icons/sort.png',
                            width: 24, height: 24),
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
                        backgroundColor: Colors.white,
                        child: Image.asset('assets/icons/location.png',
                            width: 24, height: 24),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  color: Colors.white70,
                  child: Text(
                    t('map.legend.mapyCz'),
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
                      Center(
                        child: Text(
                          t('Nastavení mapy'),
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
                          Text(t('Zobrazení mapy:')),
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
                                    side: BorderSide(
                                        color: !_isSatelliteView
                                            ? Colors.black
                                            : Colors.grey.shade200),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(t('map.filters.mapView.classic')),
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
                                    side: BorderSide(
                                        color: _isSatelliteView
                                            ? Colors.black
                                            : Colors.grey.shade200),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      Text(t('map.filters.mapView.satellite')),
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
                          Text(t('Autor nahrávky:')),
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
                                    side: BorderSide(
                                        color: _recordingAuthorFilter == 'all'
                                            ? Colors.black
                                            : Colors.grey.shade200),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                      t('map.filters.recordingAuthor.all')),
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
                                    side: BorderSide(
                                        color: _recordingAuthorFilter == 'me'
                                            ? Colors.black
                                            : Colors.grey.shade200),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      Text(t('map.filters.recordingAuthor.me')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('Zobrazovat i nepotvrzené dialekty:')),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _showUnconfirmedDialects = false;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                        color: !_showUnconfirmedDialects
                                            ? Colors.black
                                            : Colors.grey),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(t('Skrýt')),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      _showUnconfirmedDialects = true;
                                    });
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                        color: _showUnconfirmedDialects
                                            ? Colors.black
                                            : Colors.grey),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(t('Zobrazit')),
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
                      //     Text(t('Data:')),
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
                      //             child: Text(t('Nová')),
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
                      //             child: Text(t('2017')),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ],
                      // ),
                      // Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                      //     Text(t('Dobyté sektory:')),
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
                      //             child: Text(t('Zobrazit')),
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
                      //             child: Text(t('Skrýt')),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              onPressed: () {
                                setModalState(() {
                                  _isSatelliteView = false;
                                  _recordingAuthorFilter = 'all';
                                  _showUnconfirmedDialects = false;
                                });
                              },
                              child: Text(t('map.buttons.resetFilters')),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                textStyle: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.0),
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  // Apply filters if needed.
                                  showUnconfirmedDialects =
                                      _showUnconfirmedDialects;
                                });
                                _fetchDialects(); // refetch dialect data after the setting changes
                                Navigator.pop(context);
                              },
                              child: Text(t('map.buttons.set')),
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
                Text(
                  t('map.legend.title'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildAutoDialectLegend(),                           // <-- auto dialects
                      // _buildSymbolLegendItem('Vzácné', 'Vzácné'),
                      // _buildSymbolLegendItem('Přechodný', 'Přechodný'),
                      // _buildSymbolLegendItem('Mix', 'Mix'),
                      // _buildSymbolLegendItem('Atypický', 'Atypický'),
                      // _buildSymbolLegendItem('Nedokončený', 'Nedokončený'),
                      // _buildCircleLegendItem(Colors.black, 'Nepoužitelný'),
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
                        textStyle: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: Text(t('map.dialogs.error.close')),
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

  Widget _buildAutoDialectLegend() {
    return FutureBuilder<Map<String, Color>>(
      future: DynamicIcon.getLegendDialectColors(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final entries = snapshot.data!; // key -> Color (DynamicIcon resolves colors itself)
        final items = <Widget>[];

        for (final key in entries.keys) {
          // Show label "Nevyhodnoceno" but color as "Neznámý"
          final display = key == 'Neznámý' ? 'Nevyhodnoceno' : key;
          items.add(_buildDialectLegendItem(display));
        }

        return Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: items,
        );
      },
    );
  }

  Widget _buildDialectLegendItem(String dialectName) {
    // Map BE label used in backend to color key used by DynamicIcon
    final String key = (dialectName == 'Nevyhodnoceno') ? 'Neznámý' : dialectName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DynamicIcon(
            icon: Icons.circle,
            iconSize: 18,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            dialects: [key],
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
