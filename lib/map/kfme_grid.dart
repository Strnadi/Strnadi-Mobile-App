import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// KFME fields are 6 minutes latitude by 10 minutes longitude.
/// At zoom 11 each field is split into four equal quadrants (3 by 5 minutes).
List<Polyline> buildKfmeGrid({
  required LatLngBounds bounds,
  required double zoom,
}) {
  if (!zoom.isFinite || zoom < 7) return [];

  const originLat = 56.0;
  const originLon = 5 + 40 / 60;
  final subdivisions = zoom >= 11 ? 2 : 1;
  final height = (6 / 60) / subdivisions;
  final width = (10 / 60) / subdivisions;
  final lines = <Polyline>[];

  void addLine(int index, List<LatLng> points) {
    final major = index % subdivisions == 0;
    lines.add(
      Polyline(
        points: points,
        strokeWidth: 1,
        color: major ? Colors.red : Colors.orange,
      ),
    );
  }

  // Integer indices keep quarter boundaries anchored to the same global grid
  // while panning, including west/north of the origin.
  final firstColumn = ((bounds.west - originLon) / width).ceil();
  final lastColumn = ((bounds.east - originLon) / width).floor();
  for (var column = firstColumn; column <= lastColumn; column++) {
    final lon = originLon + column * width;
    addLine(column, [LatLng(bounds.north, lon), LatLng(bounds.south, lon)]);
  }
  final firstRow = ((originLat - bounds.north) / height).ceil();
  final lastRow = ((originLat - bounds.south) / height).floor();
  for (var row = firstRow; row <= lastRow; row++) {
    final lat = originLat - row * height;
    addLine(row, [LatLng(lat, bounds.west), LatLng(lat, bounds.east)]);
  }
  return lines;
}
