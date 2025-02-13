/*
 * Copyright (C) 2024 Marian Pecqueur
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

class GridLayer extends StatelessWidget {
  final List<Map<String, dynamic>> gridData;
  final Color gridColor;
  final double borderWidth;

  const GridLayer({
    Key? key,
    required this.gridData,
    this.gridColor = Colors.blue,
    this.borderWidth = 1.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Generate polygons based on grid data
    final polygons = gridData.map((gridSquare) {
      final lat = gridSquare['lat'];
      final lng = gridSquare['lng'];
      final size = gridSquare['size'];

      return Polygon(
        points: [
          LatLng(lat, lng), // Bottom-left
          LatLng(lat + size, lng), // Top-left
          LatLng(lat + size, lng + size), // Top-right
          LatLng(lat, lng + size), // Bottom-right
        ],
        color: gridColor.withOpacity(0.3),
        borderColor: gridColor,
        borderStrokeWidth: borderWidth,
      );
    }).toList();

    return PolygonLayer(polygons: polygons);
  }
}
