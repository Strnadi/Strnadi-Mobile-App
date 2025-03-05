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
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'package:scidart/numdart.dart' as numdart;
import '../config/config.dart';

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
  double _currentZoom = 13;

  // We'll capture the rendered map size via LayoutBuilder.
  Size? _mapSize;

  @override
  void initState() {
    super.initState();
    // Listen to move-end events.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapy.cz Flutter Map V2'),
        actions: [
          IconButton(
            icon: Icon(_isSatelliteView ? Icons.map : Icons.satellite),
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
      // Use LayoutBuilder to determine the map widget size.
      body: LayoutBuilder(
        builder: (context, constraints) {
          Size newSize = constraints.biggest;
          if (_mapSize == null || _mapSize != newSize) {
            _mapSize = newSize;
            // Update grid after the frame so we use the new size.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateGrid();
            });
          }
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(50.0755, 14.4378),
                  initialZoom: 13,
                  minZoom: 1,
                  maxZoom: 19,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                    'https://api.mapy.cz/v1/maptiles/${_isSatelliteView ? 'aerial' : 'basic'}/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
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
                        point: _currentCenter,
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
              // Zoom controls.
              Positioned(
                bottom: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'zoomIn',
                      mini: true,
                      child: const Icon(Icons.add),
                      onPressed: () {
                        _mapController.move(_currentCenter, _currentZoom + 1);
                        _updateGrid();
                      },
                      tooltip: 'Zoom In',
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      heroTag: 'zoomOut',
                      mini: true,
                      child: const Icon(Icons.remove),
                      onPressed: () {
                        _mapController.move(_currentCenter, _currentZoom - 1);
                        _updateGrid();
                      },
                      tooltip: 'Zoom Out',
                    ),
                  ],
                ),
              ),
              // Attribution text.
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
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

  // Convert a LatLng to pixel coordinates at a given zoom.
  Offset latLngToPixel(LatLng latlng, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double x = (latlng.longitude + 180) / 360 * nTiles * tileSize;
    double latRad = latlng.latitude * math.pi / 180;
    double y = (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        nTiles *
        tileSize;
    return Offset(x, y);
  }

  // Convert pixel coordinates at a given zoom back to a LatLng.
  LatLng pixelToLatLng(Offset pixel, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double lon = pixel.dx / (nTiles * tileSize) * 360 - 180;
    double yTile = pixel.dy / (nTiles * tileSize);
    double latRad = math.atan(numdart.sinh(math.pi * (1 - 2 * yTile)));
    double lat = latRad * 180 / math.pi;
    return LatLng(lat, lon);
  }

  // Calculate the visible bounds of the map using the current center, zoom, and widget size.
  LatLngBounds calculateBounds() {
    if (_mapSize == null) return LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    Offset centerPixel = latLngToPixel(_currentCenter, _currentZoom);
    double width = _mapSize!.width;
    double height = _mapSize!.height;
    Offset topLeftPixel = centerPixel - Offset(width / 2, height / 2);
    Offset bottomRightPixel = centerPixel + Offset(width / 2, height / 2);
    LatLng topLeft = pixelToLatLng(topLeftPixel, _currentZoom);
    LatLng bottomRight = pixelToLatLng(bottomRightPixel, _currentZoom);
    // Construct bounds with southwest and northeast corners.
    return LatLngBounds(
      LatLng(bottomRight.latitude, topLeft.longitude),
      LatLng(topLeft.latitude, bottomRight.longitude),
    );
  }

  // Update grid lines based on the current visible bounds.
  // Update grid lines based on the current visible bounds using the specified grid intervals.
  void _updateGrid() {
    if (_mapSize == null) return;
    final bounds = calculateBounds();
    final double northBound = bounds.north;
    final double southBound = bounds.south;
    final double westBound = bounds.west;
    final double eastBound = bounds.east;

    // Grid specification:
    // Grid cell height: 6 minutes = 6/60 = 0.1 degrees (latitude)
    // Grid cell width: 10 minutes = 10/60 ≈ 0.166667 degrees (longitude)
    const double gridCellHeight = 6 / 60;
    const double gridCellWidth = 10 / 60;
    // The fixed top left (origin) of the grid:
    const double originLat = 56.0;       // 56°0'N
    const double originLon = 5 + 40 / 60;  // 5°40'E, i.e. ~5.666667

    List<Polyline> newGridLines = [];

    // --- Vertical grid lines (constant longitude) ---
    // They occur at: lon = originLon + k * gridCellWidth, for integer k.
    // Find the first k so that the grid line is >= westBound.
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

    // --- Horizontal grid lines (constant latitude) ---
    // They occur at: lat = originLat - k * gridCellHeight, for integer k.
    // Find the first k so that the grid line is <= northBound.
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

  // Helper: convert latitude to a tile Y coordinate (in tile units, not pixels).
  int _latToTileY(double lat, int zoom) {
    double latRad = lat * math.pi / 180;
    double nTiles = math.pow(2, zoom).toDouble();
    double y = (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2 *
        nTiles;
    return y.floor();
  }

  // Helper: convert a tile Y coordinate back to a latitude.
  double _tileYToLat(int y, int zoom) {
    double nTiles = math.pow(2, zoom).toDouble();
    double n = math.pi * (1 - 2 * y / nTiles);
    double latRad = math.atan(numdart.sinh(n));
    return latRad * 180 / math.pi;
  }
}