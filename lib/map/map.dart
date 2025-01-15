import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapyCzApiExample extends StatefulWidget {
  @override
  _MapyCzApiExampleState createState() => _MapyCzApiExampleState();
}

class _MapyCzApiExampleState extends State<MapyCzApiExample> {
  String data = "Loading...";


  Future<void> fetchData() async {
    final response = await http.get(Uri.parse('https://api.mapy.cz/v1/static/map'));
    if (response.statusCode == 200) {
      setState(() {
        data = jsonDecode(response.body).toString();
      });
    } else {
      setState(() {
        data = "Failed to load data";
      });
    }
  }

  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: LatLng(50.0, 14.0),
        zoom: 5.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://api.mapy.cz/base-m/{z}-{x}-{y}',
          subdomains: ['a', 'b', 'c', 'd'],
        ),
        MarkerLayer(
          markers: [
            Marker(
              width: 80.0,
              height: 80.0,
              point: LatLng(50.0, 14.0),
              builder: (ctx) => Container(
                child: FlutterLogo(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
