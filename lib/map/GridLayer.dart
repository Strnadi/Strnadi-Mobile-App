import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GridLayer extends StatelessWidget {
  final LatLngBounds bounds; // Visible map bounds
  final double gridSizeKm;   // Grid size in kilometers

  GridLayer({required this.bounds, this.gridSizeKm = 10.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: GridPainter(bounds: bounds, gridSizeKm: gridSizeKm),
    );
  }
}

class GridPainter extends CustomPainter {
  final LatLngBounds bounds;
  final double gridSizeKm;

  GridPainter({required this.bounds, required this.gridSizeKm});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..strokeWidth = 1.0;

    final double latitudeInterval = gridSizeKm / 111.0;
    final double longitudeInterval = gridSizeKm / (111.0 * cos(bounds.south * pi / 180));

    // Iterate over lat/lon and draw lines
    for (double lat = (bounds.south / latitudeInterval).floor() * latitudeInterval;
    lat <= bounds.north;
    lat += latitudeInterval) {
      final start = Offset(0, _latToY(lat, bounds, size));
      final end = Offset(size.width, _latToY(lat, bounds, size));
      canvas.drawLine(start, end, paint);
    }

    for (double lon = (bounds.west / longitudeInterval).floor() * longitudeInterval;
    lon <= bounds.east;
    lon += longitudeInterval) {
      final start = Offset(_lonToX(lon, bounds, size), 0);
      final end = Offset(_lonToX(lon, bounds, size), size.height);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;

  double _latToY(double lat, LatLngBounds bounds, Size size) {
    return (1 - (lat - bounds.south) / (bounds.north - bounds.south)) * size.height;
  }

  double _lonToX(double lon, LatLngBounds bounds, Size size) {
    return (lon - bounds.west) / (bounds.east - bounds.west) * size.width;
  }
}
