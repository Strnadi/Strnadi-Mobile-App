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

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;
import 'package:scidart/numdart.dart' as numdart;
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/map/mapUtils/recordingParser.dart';
import 'package:strnadi/map/searchBar.dart';
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
  List<Polyline> _gridLines = [];

  // Store the current camera values.
  LatLng _currentCenter = LatLng(50.0755, 14.4378);
  LatLng _currentPosition = LatLng(50.0755, 14.4378);
  double _currentZoom = 13;

  List<Part> _recordings = [];

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
      final response = await http.get(
        Uri.parse('https://api.strnadi.cz/recordings?parts=true&sound=false'),
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
      }
      else {
        logger.e('Failed to fetch recordings ${response.statusCode}');
      }
    }
    catch (error) {
      logger.e(error);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: "Mapa Strnadu",
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
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Part ID: ${part.id}'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Recording ID: ${part.recordingId}'),
                                  Text('Start: ${part.start}'),
                                  Text('End: ${part.end}'),
                                  if (part.filePath != null)
                                    Text('File: ${part.filePath}'),
                                  if (part.square != null)
                                    Text('Square: ${part.square}'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 30.0,
                        ),
                      ),
                    ))
                        .toList(),
                  )

                ],
              ),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SearchBarWidget(
                  onLocationSelected: (LatLng location) {
                    _mapController.move(location, _currentZoom);
                  },
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Reset button: recenter the map to current location and reset orientation to north.
                    FloatingActionButton(
                      heroTag: 'reset',
                      mini: true,
                      tooltip: 'Reset orientation & recenter',
                      onPressed: () async {
                        // Update current location.
                        await _getCurrentLocation();
                        // Recenter the map to the updated current location with the current zoom level.
                        _mapController.move(_currentPosition, _currentZoom);
                        // If your map supports rotation (and you’ve enabled it in MapOptions),
                        // you can reset the orientation to north by uncommenting the next line.
                        // _mapController.rotate(0);
                        _updateGrid();
                      },
                      child: const Icon(Icons.gps_fixed),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'zoomIn',
                      mini: true,
                      child: const Icon(Icons.add),
                      tooltip: 'Zoom In',
                      onPressed: () {
                        _mapController.move(_currentPosition, _currentZoom + 1);
                        _currentZoom += 1;
                        _updateGrid();
                      },
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'zoomOut',
                      mini: true,
                      child: const Icon(Icons.remove),
                      tooltip: 'Zoom Out',
                      onPressed: () {
                        _mapController.move(_currentPosition, _currentZoom - 1);
                        _currentZoom -= 1;
                        _updateGrid();
                      },
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'toggleSatellite',
                      mini: true,
                      child: Icon(_isSatelliteView ? Icons.map : Icons.satellite),
                      onPressed: () {
                        setState(() {
                          _isSatelliteView = !_isSatelliteView;
                        });
                      },
                      tooltip: _isSatelliteView
                          ? 'Switch to Map View'
                          : 'Switch to Satellite View',
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
}