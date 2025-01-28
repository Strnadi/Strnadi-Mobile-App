import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:strnadi/bottomBar.dart';

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
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print("Location services are not enabled");
      return;
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    // Get the current location
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
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
      content: MaterialApp(
        home: Scaffold(
          body: _currentPosition == null || _gridData == null
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
                    urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.navratKrale.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 20.0,
                        height: 20.0,
                        point: _currentPosition!,
                        builder: (ctx) => Icon(
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
        ),
      ),
    );
  }
}