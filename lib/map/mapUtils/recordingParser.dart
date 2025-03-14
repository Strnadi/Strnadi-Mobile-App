import 'dart:convert';

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
      id: json['id'],
      recordingId: json['recordingId'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
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
  final int estimatedBirdsCount;
  final String device;
  final bool byApp;
  final String note;
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
      id: json['id'],
      userId: json['userId'],
      createdAt: DateTime.parse(json['createdAt']),
      estimatedBirdsCount: json['estimatedBirdsCount'],
      device: json['device'] ?? '',
      byApp: json['byApp'],
      note: json['note'] ?? '',
      notePost: json['notePost'],
      parts: (json['parts'] as List<dynamic>)
          .map((p) => Part.fromJson(p))
          .toList(),
    );
  }
}

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);
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
