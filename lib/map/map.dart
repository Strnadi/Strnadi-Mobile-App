import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled, handle this case
      print("location services are not enabled");
      return;
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, handle this case
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied, handle this case
      return;
    }

    // Get the current location
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'OpenStreetMap in Flutter',
      content: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : FlutterMap(
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
                    builder: (ctx) => Icon(
                      Icons. my_location,
                      color: Colors.blue,
                      size: 30.0,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}