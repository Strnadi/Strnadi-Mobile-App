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

import 'package:latlong2/latlong.dart';

class Part {
  final int id;
  final int recordingId;
  final DateTime start;
  final DateTime end;
  final double gpsLatitudeStart;
  final double gpsLatitudeEnd;
  final double gpsLongitudeStart;
  final double gpsLongitudeEnd;
  final String? square;
  final String? filePath;
  final String? dataBase64;

  Part({
    required this.id,
    required this.recordingId,
    required this.start,
    required this.end,
    required this.gpsLatitudeStart,
    required this.gpsLatitudeEnd,
    required this.gpsLongitudeStart,
    required this.gpsLongitudeEnd,
    this.square,
    this.filePath,
    this.dataBase64,
  });

  factory Part.fromJson(Map<String, dynamic> json) {
    return Part(
      id: json['id'] ?? -1,
      recordingId: json['recordingId'] ?? -1,
      start: DateTime.parse(json['startDate']),
      end: DateTime.parse(json['endDate']),
      gpsLatitudeStart: (json['gpsLatitudeStart'] ?? 0).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] ?? 0).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] ?? 0).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] ?? 0).toDouble(),
      square: json['square'],
      filePath: json['filePath'],
      dataBase64: json['dataBase64'],
    );
  }
}


class Recording {
  final int id;
  final int userId;
  final DateTime createdAt;
  final int? estimatedBirdsCount;
  final String device;
  final bool byApp;
  final String? note;
  final String? notePost;
  final List<Part> parts;

  Recording({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.estimatedBirdsCount,
    required this.device,
    required this.byApp,
    required this.note,
    this.notePost,
    required this.parts,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] ?? -1,
      userId: json['userId'] ?? -1,
      createdAt: DateTime.parse(json['createdAt']),
      estimatedBirdsCount: (json['estimatedBirdsCount'] ?? 0) as int,
      device: json['device'] ?? '',
      byApp: json['byApp'] ?? false,
      note: json['note']?.toString(),
      notePost: json['notePost']?.toString(),
      parts: (json['parts'] as List<dynamic>? ?? [])
          .map((p) => Part.fromJson(p))
          .toList(),
    );
  }

}


List<Part> getParts(String jsonString) {
  final List<dynamic> decoded = jsonDecode(jsonString);
  final recordings = decoded.map((r) => Recording.fromJson(r)).toList();

  final List<Part> parts = [];

  for (var recording in recordings) {
    parts.addAll(recording.parts);
  }

  return parts;
  }

LatLng? getFirstPartLatLng(String jsonString) {
  final List<dynamic> decoded = jsonDecode(jsonString);
  final recordings = decoded.map((r) => Recording.fromJson(r)).toList();

  if (recordings.isNotEmpty && recordings.first.parts.isNotEmpty) {
    final firstPart = recordings.first.parts.first;
    return LatLng(firstPart.gpsLatitudeStart, firstPart.gpsLongitudeStart);
  }
  return null; // no data
}

List<LatLng> getAllLatLngs(String jsonString) {
  final List<dynamic> decoded = jsonDecode(jsonString);
  final recordings = decoded.map((r) => Recording.fromJson(r)).toList();

  final List<LatLng> latLngList = [];

  for (var recording in recordings) {
    for (var part in recording.parts) {
      latLngList.add(LatLng(part.gpsLatitudeStart, part.gpsLongitudeStart));
    }
  }

  return latLngList;
}
