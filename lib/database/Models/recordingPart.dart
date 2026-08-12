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
  bool uploadAttempted;
  String? uploadKey;
  String? uploadContentSha256;
  int? uploadContentBytes;

  RecordingPart({
    this.id,
    this.BEId,
    required this.recordingId,
    this.backendRecordingId,
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
    this.uploadAttempted = false,
    this.uploadKey,
    this.uploadContentSha256,
    this.uploadContentBytes,
  });

  factory RecordingPart.fromJson(Map<String, Object?> json) {
    return RecordingPart(
        id: json['id'] as int?,
        BEId: json['BEId'] as int?,
        recordingId: json['recordingId'] as int?,
        backendRecordingId: json['backendRecordingId'] as int?,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
        gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
        gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
        gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
        square: json['square'] as String?,
        sent: (json['sent'] as int) == 1,
        sending: (json['sending'] as int) == 1,
        uploadAttempted: (json['uploadAttempted'] as int? ?? 0) == 1,
        uploadKey: json['uploadKey'] as String?,
        uploadContentSha256: json['uploadContentSha256'] as String?,
        uploadContentBytes: json['uploadContentBytes'] as int?,
        path: json['path'] as String?,
        length: json['length'] as int?);
  }

  factory RecordingPart.fromBEJson(
      Map<String, Object?> json, int backendRecordingId) {
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
        "/recording_${DateTime.now().millisecondsSinceEpoch}.wav";
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
        'Recording part is not ready '
        '(id=${unready.id}, recordingId=${unready.recordingId}, '
        'hasStart=${unready.startTime != null}, '
        'hasEnd=${unready.endTime != null}, '
        'hasStartLocation=${unready.gpsLatitudeStart != null && unready.gpsLongitudeStart != null}, '
        'hasEndLocation=${unready.gpsLatitudeEnd != null && unready.gpsLongitudeEnd != null}, '
        'hasPath=${unready.path != null && unready.path!.isNotEmpty}).',
      );
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
      'uploadAttempted': uploadAttempted ? 1 : 0,
      'uploadKey': uploadKey,
      'uploadContentSha256': uploadContentSha256,
      'uploadContentBytes': uploadContentBytes,
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
