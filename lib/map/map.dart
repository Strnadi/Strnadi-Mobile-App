/*
 * Copyright (C) 2024 Marian && Jan Drobílek
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
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:logger/logger.dart';

void _showMessage(String message) {
  var context;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Login'),
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

final logger = new Logger();

class OSMmap extends StatefulWidget {
  const OSMmap({Key? key}) : super(key: key);

  @override
  _OSMmapState createState() => _OSMmapState();
}

class _OSMmapState extends State<OSMmap> {
  LatLng? _currentPosition;
  List<Map<String, dynamic>>? _gridData;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadJson();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage("Please enable location services");
        logger.w("Location services are not enabled");
        print("Location services are not enabled");
        setState(() {
          _currentPosition = LatLng(50.1, 14.4);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w("Location permissions are denied");
          print("Location permissions are denied");
          setState(() {
            _currentPosition = LatLng(50.1, 14.4);
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.w("Location permissions are permanently denied");
        print("Location permissions are permanently denied");
        setState(() {
          _currentPosition = LatLng(50.1, 14.4);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      logger.e(e);
      print("Error retrieving location: $e");
    }
  }

  Future<void> _loadJson() async {
    try {
      final jsonData = await rootBundle.loadString('lib/map/dummy.json');
      final parsedData = jsonDecode(jsonData);
      setState(() {
        _gridData = (parsedData['grid'] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      print("Error loading or parsing JSON: $e");
    }
  }



  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'OpenStreetMap in Flutter',
      content: _currentPosition == null || _gridData == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              center: _currentPosition,
              zoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.navratKrale.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 20.0,
                    height: 20.0,
                    point: _currentPosition!,
                    builder: (ctx) => const Icon(
                      Icons.my_location,
                      color: Colors.blue,
                      size: 30.0,
                    ),
                  ),
                ],
              ),
              PolygonLayer(
                polygons: _gridData!.map((gridSquare) {
                  final lat = gridSquare['lat'] as double;
                  final lng = gridSquare['lng'] as double;
                  final size = gridSquare['size'] as double;
                  return Polygon(
                    points: [
                      LatLng(lat, lng), // Bottom-left
                      LatLng(lat + size, lng), // Top-left
                      LatLng(lat + size, lng + size), // Top-right
                      LatLng(lat, lng + size), // Bottom-right
                    ],
                    isFilled: true,
                    color: Colors.black.withAlpha(50),
                    borderColor: Colors.red,
                    borderStrokeWidth: 1.0,
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}