import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../exceptions.dart';

import 'package:logger/logger.dart';

Logger logger = Logger();

class RecordingPart {
  int? id;
  int? BEId;
  int? recordingId;
  int? backendRecordingId;
  DateTime startTime;
  DateTime endTime;
  double gpsLatitudeStart;
  double gpsLatitudeEnd;
  double gpsLongitudeStart;
  double gpsLongitudeEnd;
  String? square;
  String? dataBase64Temp;
  String? path;
  int? length;
  bool sent;
  bool sending;

  RecordingPart({
    this.id,
    this.BEId,
    required this.recordingId,
    required this.startTime,
    required this.endTime,
    required this.gpsLatitudeStart,
    required this.gpsLatitudeEnd,
    required this.gpsLongitudeStart,
    required this.gpsLongitudeEnd,
    this.square,
    this.path,
    this.length,
    this.dataBase64Temp,
    this.sent = false,
    this.sending = false,
  });

  factory RecordingPart.fromJson(Map<String, Object?> json) {
    return RecordingPart(
        id: json['id'] as int?,
        BEId: json['BEId'] as int?,
        recordingId: json['recordingId'] as int?,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
        gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
        gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
        gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
        square: json['square'] as String?,
        sent: (json['sent'] as int) == 1,
        sending: (json['sending'] as int) == 1,
        path: json['path'] as String?,
        length: json['length'] as int?);
  }

  factory RecordingPart.fromBEJson(Map<String, Object?> json,
      int backendRecordingId) {
    return RecordingPart(
        BEId: json['id'] as int?,
        recordingId: null,
        // will be updated later
        startTime: DateTime.parse(json['startDate'] as String),
        endTime: DateTime.parse(json['endDate'] as String),
        gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
        gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
        gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
        gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
        dataBase64Temp: json['dataBase64'] as String?,
        square: json['square'] as String?,
        sent: true,
        length: json['length'] as int?)
      ..backendRecordingId = backendRecordingId;
  }

  Future<void> save() async {
    String newPath = (await getApplicationDocumentsDirectory()).path +
        "/recording_${DateTime
            .now()
            .millisecondsSinceEpoch}.wav";
    File file = await File(newPath).create();
    await file.writeAsBytes(base64Decode(dataBase64Temp!));
    this.path = newPath;
  }

  factory RecordingPart.fromUnready(RecordingPartUnready unready) {
    if (unready.startTime == null ||
        unready.endTime == null ||
        unready.gpsLatitudeStart == null ||
        unready.gpsLatitudeEnd == null ||
        unready.gpsLongitudeStart == null ||
        unready.gpsLongitudeEnd == null ||
        unready.path == null) {
      logger.i(
          'Recording part is not ready. Part id: ${unready
              .id}, recording id: ${unready.recordingId}, start time: ${unready
              .startTime}, end time: ${unready
              .endTime}, gpsLatitudeStart: ${unready
              .gpsLatitudeStart}, gpsLatitudeEnd: ${unready
              .gpsLatitudeEnd}, gpsLongitudeStart: ${unready
              .gpsLongitudeStart}, gpsLongitudeEnd: ${unready
              .gpsLongitudeEnd}, path: ${unready.path}');
      throw UnreadyException('Recording part is not ready');
    }
    return RecordingPart(
      id: unready.id,
      BEId: null,
      recordingId: unready.recordingId,
      startTime: unready.startTime!,
      endTime: unready.endTime!,
      gpsLatitudeStart: unready.gpsLatitudeStart ?? 0.0,
      gpsLatitudeEnd: unready.gpsLatitudeEnd ?? 0.0,
      gpsLongitudeStart: unready.gpsLongitudeStart ?? 0.0,
      gpsLongitudeEnd: unready.gpsLongitudeEnd ?? 0.0,
      path: unready.path,
      //dataBase64Temp: unready.dataBase64,
      square: null,
      sent: false,
    );
  }

  Map<String, Object?> toBEJson() {
    return {
      'id': BEId,
      'recordingId': backendRecordingId,
      'startDate': startTime.toIso8601String(),
      'endDate': endTime.toIso8601String(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'dataBase64': dataBase64,
    };
  }

  Map<String, Object?> toBEJsonWithoutData() {
    return {
      'id': BEId,
      'recordingId': backendRecordingId,
      'startDate': startTime.toIso8601String(),
      'endDate': endTime.toIso8601String(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
    };
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'BEId': BEId,
      'backendRecordingId': backendRecordingId, // new field
      'recordingId': recordingId,
      'startTime': startTime.toString(),
      'endTime': endTime.toString(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'path': path,
      'square': square,
      'sent': sent ? 1 : 0,
      'sending': sending ? 1 : 0,
      'length': length
    };
  }

  String? get dataBase64 {
    if (this.path == null) return null;
    File file = File(this.path!);
    String base64String = base64Encode(file.readAsBytesSync());
    return base64String;
  }
}

class RecordingPartUnready {
  int? id;
  int? recordingId;
  DateTime? startTime;
  DateTime? endTime;
  double? gpsLatitudeStart;
  double? gpsLatitudeEnd;
  double? gpsLongitudeStart;
  double? gpsLongitudeEnd;
  //String? dataBase64;
  String? path;

  RecordingPartUnready(
      {this.id,
        this.recordingId,
        this.startTime,
        this.endTime,
        this.gpsLatitudeStart,
        this.gpsLatitudeEnd,
        this.gpsLongitudeStart,
        this.gpsLongitudeEnd,
        this.path
        //this.dataBase64,
      });
}