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

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/PostRecordingForm/addDialect.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/user/settingsManager.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/exceptions.dart';
// Missing import added:
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:strnadi/recording/waw.dart';

import '../notificationPage/notifications.dart';

final logger = Logger();

/// Models
///
///

Future<String> getPath() async {
  final dir = await getApplicationDocumentsDirectory();
  String path = dir.path + 'audio_${DateTime.now().millisecondsSinceEpoch}.wav';
  logger.i('Generated file path: $path');
  return path;
}

class UserData{
  String FirstName;
  String LastName;
  String? NickName;

  String? ProfilePic;

  String? format;

  UserData({
    required this.FirstName,
    required this.LastName,
    this.NickName,
    this.ProfilePic,
    this.format
  });

  factory UserData.fromJson(Map<String, Object?> json){
    return UserData(FirstName: json['firstName'] as String, LastName: json['lastName'] as String, NickName: json['nickname'] as String?);
  }
}

class RecordingDialect{
  int RecordingId;
  String dialect;
  DateTime StartDate;
  DateTime EndDate;

  RecordingDialect({
    required this.RecordingId,
    required this.dialect,
    required this.StartDate,
    required this.EndDate,
  });

  factory RecordingDialect.fromJson(Map<String, Object?> json) {
    // Safely parse the ID, allowing for uppercase or lowercase keys
    final dynamic idValue = json['recordingId'] ?? json['RecordingId'];
    final int recordingId = idValue is int
      ? idValue
      : (idValue != null ? int.tryParse(idValue.toString()) ?? 0 : 0);

    // Determine dialect: prefer first detectedDialects entry (string or map), else fallback to dialectCode
    final List<dynamic> detectedList = (json['detectedDialects'] as List<dynamic>?) ?? [];
    late final String dialectValue;
    if (detectedList.isNotEmpty) {
      final first = detectedList.first;
      if (first is String) {
        dialectValue = first;
      } else if (first is Map<String, dynamic>) {
        dialectValue = (first['dialect'] as String?)
            ?? (first['dialectCode'] as String?)
            ?? 'Nevyhodnoceno';
      } else {
        dialectValue = 'Nevyhodnoceno';
      }
    } else {
      dialectValue = (json['dialectCode'] as String?) ?? 'Nevyhodnoceno';
    }

    // Helper to fetch raw date string from uppercase or lowercase key
    String _getRawDate(String upperKey, String lowerKey) {
      return json[upperKey] as String?
          ?? json[lowerKey] as String?
          ?? '';
    }

    // Robust date parser: empty → epoch; digits → epoch-from-ms; ISO parse otherwise
    DateTime _parseDate(String raw) {
      if (raw.isEmpty) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
      if (RegExp(r'^\d+$').hasMatch(raw)) {
        return DateTime.fromMillisecondsSinceEpoch(int.parse(raw));
      }
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    final DateTime startDate = _parseDate(_getRawDate('StartDate', 'startDate'));
    final DateTime endDate   = _parseDate(_getRawDate('EndDate',   'endDate'));

    return RecordingDialect(
      RecordingId: recordingId,
      dialect: dialectValue,
      StartDate: startDate,
      EndDate: endDate,
    );
  }




  Map<String, Object?> toJson() {
    return {
      'recordingId': RecordingId,
      'dialectCode': dialect,
      'StartDate': StartDate.toString(),
      'EndDate': EndDate.toString(),
    };
  }

  List<RecordingDialect> fromJsonList(List<dynamic> jsonList) {
    return jsonList.map((json) => RecordingDialect.fromJson(json)).toList();
  }
}

class RecordingUnready {
  int? id;
  String? mail;
  DateTime? createdAt;
  int? estimatedBirdsCount;
  String? device;
  bool? byApp;
  String? note;
  String? path;

  RecordingUnready({
    this.id,
    this.mail,
    this.createdAt,
    this.estimatedBirdsCount,
    this.device,
    this.byApp,
    this.note,
    this.path,
  });
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

  RecordingPartUnready({
    this.id,
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

class Recording {
  int? id;
  int? userId;
  int? BEId;
  String? mail;
  DateTime createdAt;
  int estimatedBirdsCount;
  String? device;
  bool byApp;
  String? note;
  String? name;
  String? path;
  bool downloaded;
  bool sent;
  bool sending;

  Recording({
    this.id,
    this.userId,
    this.BEId,
    this.mail,
    required this.createdAt,
    required this.estimatedBirdsCount,
    this.device,
    required this.byApp,
    this.note,
    this.name,
    this.path,
    this.downloaded = true,
    this.sent = false,
    this.sending = false,
  });

  factory Recording.fromJson(Map<String, Object?> json) {
    return Recording(
      id: json['id'] as int?,
      userId: json['userId'] as int?,
      BEId: json['BEId'] as int?,
      mail: json['mail'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      estimatedBirdsCount: json['estimatedBirdsCount'] as int,
      device: json['device'] as String?,
      byApp: (json['byApp'] as int) == 1,
      note: json['note'] as String?,
      name: json['name'] as String?,
      path: json['path'] as String?,
      sent: (json['sent'] as int) == 1,
      downloaded: (json['downloaded'] as int) == 1,
      sending: (json['sending'] as int) == 1,
    );
  }

  factory Recording.fromUnready(RecordingUnready unready) {
    if (unready.id == null ||
        unready.mail == null ||
        unready.createdAt == null ||
        unready.estimatedBirdsCount == null ||
        unready.device == null ||
        unready.byApp == null ||
        unready.path == null) {
      throw UnreadyException('Recording is not ready');
    }
    return Recording(
      id: unready.id,
      BEId: null,
      mail: unready.mail ?? '',
      createdAt: unready.createdAt!,
      estimatedBirdsCount: unready.estimatedBirdsCount ?? 0,
      device: unready.device,
      byApp: unready.byApp ?? true,
      note: unready.note,
      path: unready.path,
      sent: false,
      downloaded: true,
      sending: false,
    );
  }

  factory Recording.fromBEJson(Map<String, Object?> json, int? userId) {

    return Recording(
      BEId: json['id'] as int?,
      userId: userId ?? json['userId'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      estimatedBirdsCount: json['estimatedBirdsCount'] as int,
      device: json['device'] as String?,
      byApp: json['byApp'] as bool,
      note: json['note'] as String?,
      name: json['name'] as String?,
      sent: true,
      downloaded: false,
      path: null,
      sending: false,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'BEId': BEId,
      'mail': mail,
      'createdAt': createdAt.toString(),
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp ? 1 : 0,
      'note': note,
      'name': name,
      'path': path,
      'sent': sent ? 1 : 0,
      'downloaded': downloaded ? 1 : 0,
      'sending': sending ? 1 : 0,
    };
  }

  Map<String, Object?> toBEJson() {
    return {
      'id': BEId,
      'createdAt': createdAt.toIso8601String(),
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp,
      'note': note,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Recording) return false;
    bool equal = true;
    if (mail != null && other.mail != null) {
      equal = equal && mail == other.mail;
    }
    if (createdAt != null && other.createdAt != null) {
      equal = equal && createdAt == other.createdAt;
    }
    if (estimatedBirdsCount != null && other.estimatedBirdsCount != null) {
      equal = equal && estimatedBirdsCount == other.estimatedBirdsCount;
    }
    if (device != null && other.device != null) {
      equal = equal && device == other.device;
    }
    if (byApp != null && other.byApp != null) {
      equal = equal && byApp == other.byApp;
    }
    if (note != null && other.note != null) {
      equal = equal && note == other.note;
    }
    return equal;
  }

  @override
  int get hashCode {
    return Object.hash(
      BEId ?? 0,
      mail,
      createdAt,
      estimatedBirdsCount,
      device ?? '',
      byApp,
      note ?? '',
    );
  }
}

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
      sent:    (json['sent']    as int) == 1,
      sending: (json['sending'] as int) == 1,
      path: json['path'] as String?,
      length: json['length'] as int?
    );
  }

  factory RecordingPart.fromBEJson(Map<String, Object?> json, int backendRecordingId) {
    return RecordingPart(
      BEId: json['id'] as int?,
      recordingId: null, // will be updated later
      startTime: DateTime.parse(json['startDate'] as String),
      endTime: DateTime.parse(json['endDate'] as String),
      gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
      dataBase64Temp: json['dataBase64'] as String?,
      square: json['square'] as String?,
      sent: true,
      length: json['length'] as int?
    )..backendRecordingId = backendRecordingId;
  }

  Future<void> save() async{
    String newPath = (await getApplicationDocumentsDirectory()).path + "/recording_${DateTime.now().millisecondsSinceEpoch}.wav";
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
          'Recording part is not ready. Part id: ${unready.id}, recording id: ${unready.recordingId}, start time: ${unready.startTime}, end time: ${unready.endTime}, gpsLatitudeStart: ${unready.gpsLatitudeStart}, gpsLatitudeEnd: ${unready.gpsLatitudeEnd}, gpsLongitudeStart: ${unready.gpsLongitudeStart}, gpsLongitudeEnd: ${unready.gpsLongitudeEnd}, path: ${unready.path}');
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
      'sent':    sent    ? 1 : 0,
      'sending': sending ? 1 : 0,
      'length': length
    };
  }

  String? get dataBase64{
    if(this.path==null) return null;
    File file = File(this.path!);
    String base64String = base64Encode(file.readAsBytesSync());
    return base64String;
  }
}

/// Database helper class
class DatabaseNew {
  static Database? _database;
  static List<Recording> recordings = List<Recording>.empty(growable: true);
  static List<RecordingPart> recordingParts = List<RecordingPart>.empty(
      growable: true);

  static List<Recording>? fetchedRecordings;
  static List<RecordingPart>? fetchedRecordingParts;

  static bool fetching = false;
  static bool loadedRecordings = false;

  /// Enforces the user-defined maximum number of local recordings by deleting the oldest ones.
  static Future<void> enforceMaxRecordings() async {
    final max = await SettingsService().getLocalRecordingsMax();
    if (max <= 0) return; // no limit or invalid
    final allRecs = await getRecordings();
    if (allRecs.length <= max) return; // under limit
    // Sort by creation date ascending (oldest first)
    allRecs.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final toDelete = allRecs.take(allRecs.length - max);
    for (var rec in toDelete) {
      if (rec.id != null) {
        await deleteRecordingFromCache(rec.id!);
      }
    }
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }


  static DialectModel ToDialectModel(RecordingDialect dialect) {
    final Map<String, Color> dialectColors = {
      'BC': Colors.yellow,
      'BE': Colors.green,
      'BlBh': Colors.lightBlue,
      'BhBl': Colors.blue,
      'XB': Colors.red,
      'Jiné': Colors.white,
      'Nevím': Colors.grey.shade300,
    };

    return DialectModel(
      label: dialect.dialect,
      startTime: Duration(
          milliseconds: dialect.StartDate.millisecondsSinceEpoch).inSeconds
          .toDouble(),
      endTime: Duration(milliseconds: dialect.EndDate.millisecondsSinceEpoch)
          .inSeconds.toDouble(),
      type: dialect.dialect,
      color: dialectColors[dialect.dialect] ?? Colors.white,
    );
  }

  static Future<int> insertRecording(Recording recording) async {
    try {
      final db = await database;
      if (recording.BEId != null) {
        List<Map<String, dynamic>> existing =
        await db.query(
            "recordings", where: "BEId = ?", whereArgs: [recording.BEId]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recording.id = id;
          await updateRecording(recording);
          int index = recordings.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordings[index] = recording;
          } else {
            recordings.add(recording);
          }
          logger.i('Recording with BEId ${recording
              .BEId} updated (id: $id), path: ${recording.path}');
          return id;
        }
      }
      recording.mail = JwtDecoder.decode(
          await FlutterSecureStorage().read(key: 'token') ?? '')['sub'];
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      recordings.add(recording);
      await enforceMaxRecordings();
      logger.i('Recording ${recording.id} inserted, path: ${recording.path}');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<int> insertRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      if (recordingPart.id != null) {
        List<Map<String, dynamic>> existing =
        await db.query(
            "recordingParts", where: "id = ?", whereArgs: [recordingPart.id]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recordingPart.id = id;
          await updateRecordingPart(recordingPart);
          int index = recordingParts.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordingParts[index] = recordingPart;
          } else {
            recordingParts.add(recordingPart);
          }
          logger.i('Recording part with backendRecordingId ${recordingPart
              .backendRecordingId} updated (id: $id).');
          return id;
        }
      }
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      recordingParts.add(recordingPart);
      logger.i('Recording part ${recordingPart.id} inserted.');
      return id;
    } catch (e, stackTrace) {
      logger.e(
          'Failed to insert recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<void> onFetchFinished() async {
    List<Recording> oldRecordings = await getRecordings();
    List<Recording> sentRecordings = oldRecordings.where((
        recording) => recording.sent).toList();

    if (fetchedRecordings == null || fetchedRecordingParts == null) {
      logger.i('No recordings fetched from backend.');
      return;
    }
    if (fetchedRecordings!.isEmpty || fetchedRecordingParts!.isEmpty) {
      logger.i('No recordings fetched from backend.');
      return;
    }

    // Delete sent recordings missing on backend
    for (Recording recording in sentRecordings) {
      if (!fetchedRecordings!.any((f) => f.BEId == recording.BEId)) {
        await deleteRecordingFromCache(recording.id!);
        logger.i('Recording id ${recording.id} deleted locally (missing on backend).');
      }
    }

    List<Recording> newRecordings = fetchedRecordings!
        .where((recording) =>
    !sentRecordings.any((r) =>
    r.BEId == recording.BEId))
        .toList();

    for (Recording recording in newRecordings) {
      recording.sent = true;
      recording.downloaded = false;
      logger.i(
          'Inserting recording with BEId: ${recording.BEId} and name ${recording
              .name}');
      await insertRecording(recording);
    }

    List<RecordingPart> oldRecordingParts = await getRecordingParts();
    List<RecordingPart> newRecordingParts = fetchedRecordingParts!
        .where((newPart) =>
    !oldRecordingParts.any((p) =>
    p.BEId == newPart.BEId))
        .toList();

    for (RecordingPart recordingPart in newRecordingParts) {
      recordingPart.sent = true;
      Recording? localRecording;
      try {
        localRecording = recordings.firstWhere((r) =>
        r.BEId ==
            recordingPart.backendRecordingId);
      } catch (e) {
        localRecording = null;
      }
      if (localRecording != null) {
        recordingPart.recordingId = localRecording.id;
      }
      await insertRecordingPart(recordingPart);
    }
  }

  static Future<void> syncRecordings() async {
    if (fetching) return;
    logger.i("🔄 Syncing recordings...");
    try {
      await fetchRecordingsFromBE();
      final List<Recording> localRecordings = await getRecordings();
      final Set<int?> beIds = fetchedRecordings?.map((r) => r.BEId).toSet() ?? {};
      for (var local in localRecordings) {
        if (local.sent && !beIds.contains(local.BEId)) {
          await deleteRecordingFromCache(local.id!);
          logger.i('Recording id ${local.id} deleted locally (missing on backend, during sync).');
        }
      }
      await onFetchFinished();
      logger.i("✅ Recordings fetched and synced.");
    } catch (e, stackTrace) {
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<List<Recording>> getRecordings() async {
    final db = await database;
    final String jwt = await FlutterSecureStorage().read(key: 'token') ?? '';
    final String email = JwtDecoder.decode(jwt)['sub'];
    final List<Map<String, dynamic>> recs = await db.query(
        "recordings", where: "mail = ?", whereArgs: [email]);
    return List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
  }

  static Future<List<RecordingPart>> getRecordingParts() async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query("recordingParts");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<void> deleteRecording(int id) async {
    try {
      // Try to obtain the in‑memory instance of the recording
      Recording? recording;
      try {
        recording = recordings.firstWhere((r) => r.id == id);
      } catch (_) {
        recording = null;
      }

      /* ------------------------------------------------------------------
       * 1) Delete on backend (only if already sent and BEId is known)
       * ------------------------------------------------------------------ */
      if (recording != null && recording.sent && recording.BEId != null) {
        final String? jwt = await FlutterSecureStorage().read(key: 'token');
        if (jwt != null) {
          final Uri url = Uri(
            scheme: 'https',
            host: Config.host,
            path: '/recordings/${recording.BEId}',
          );
          final http.Response resp = await http.delete(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
          );
          if (resp.statusCode == 200 || resp.statusCode == 204) {
            logger.i('Recording BEId ${recording.BEId} deleted on backend.');
          } else {
            logger.w(
              'Backend deletion failed for BEId ${recording.BEId}. '
                  'Status: ${resp.statusCode} – Body: ${resp.body}',
            );
          }
        } else {
          logger.w(
              'JWT not available – skipping backend delete for BEId ${recording
                  ?.BEId}');
        }
      }

      /* ------------------------------------------------------------------
       * 2) Delete locally (DB rows, cached files, in‑memory lists)
       * ------------------------------------------------------------------ */
      final Database db = await database;

      // Remove audio part files + rows
      for (final RecordingPart part in List<RecordingPart>.from(
          recordingParts)) {
        if (part.recordingId == id) {
          if (part.path != null) {
            try {
              await File(part.path!).delete();
            } catch (_) {
              /* ignore file‑system errors */
            }
          }
          recordingParts.remove(part);
        }
      }
      await db.delete(
          'recordingParts', where: 'recordingId = ?', whereArgs: [id]);

      // Remove main audio file if any
      if (recording?.path != null) {
        try {
          await File(recording!.path!).delete();
        } catch (_) {
          /* ignore file‑system errors */
        }
      }

      // Remove recording row + in‑memory instance
      recordings.removeWhere((r) => r.id == id);
      await db.delete('recordings', where: 'id = ?', whereArgs: [id]);

      logger.i(
          'Recording id $id deleted locally (and on backend if applicable).');
    } catch (e, stackTrace) {
      logger.e('Failed to delete recording id $id', error: e,
          stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> sendRecordingBackground(int recordingId) async {
    await Workmanager().registerOneOffTask(
      (Platform.isIOS)
          ? "com.delta.strnadi.sendRecording"
          : "sendRecording_${DateTime
          .now()
          .microsecondsSinceEpoch}",
      (Platform.isIOS) ? "sendRecording_${DateTime
          .now()
          .microsecondsSinceEpoch}" : "sendRecording",
      inputData: {"recordingId": recordingId},
    );
  }

  static Future<void> sendRecording(Recording recording,
      List<RecordingPart> recordingParts) async {
    if (!await hasInternetAccess()) {
      logger.i('No internet connection. Recording will not be sent.');
      recording.sending = false;
      await updateRecording(recording);
      return;
    }
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      recording.sending = false;
      await updateRecording(recording);
      throw FetchException('Failed to send recording to backend', 401);
    }
    final http.Response response = await http.post(
      Uri.https(Config.host, '/recordings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(recording.toBEJson()),
    );
    if (response.statusCode == 200) {
      logger.i('Recording sent successfully. Sending parts. Response: ${response
          .body}');
      recording.BEId = jsonDecode(response.body);
      await updateRecording(recording);

      for (RecordingPart part in recordingParts) {
        part.recordingId = recording.id;
        part.backendRecordingId = recording.BEId;
        await sendRecordingPart(part);
      }
      recording.sent = true;
      recording.sending = false;
      await updateRecording(recording);
      logger.i('Recording id ${recording.id} sent successfully.');
    } else {
      recording.sending = false;
      await updateRecording(recording);
      throw UploadException(
          'Failed to send recording to backend', response.statusCode);
    }
  }

  static Future<int?> getRecordingBEIDbyID(int id) async {
    var db = await database;
    var value = await db.query("recordings", where: "id = ?", whereArgs: [id]);
    if (value.isNotEmpty) {
      return value.first["BEId"] as int?;
    } else {
      return null;
    }
  }

  /// Deletes a recording and its parts from the local cache.
  static Future<void> deleteRecordingFromCache(int id) async {
    final db = await database;
    // Delete associated part files
    for (final part in recordingParts.where((p) => p.recordingId == id)) {
      if (part.path != null) {
        try {
          await File(part.path!).delete();
        } catch (_) {
          // ignore file-system errors
        }
      }
    }
    // Remove associated parts from in-memory list and DB
    recordingParts.removeWhere((p) => p.recordingId == id);
    await db.delete(
      'recordingParts',
      where: 'recordingId = ?',
      whereArgs: [id],
    );
    // Delete main recording file
    Recording? rec;
    try {
      rec = recordings.firstWhere((r) => r.id == id);
    } catch (_) {
      rec = null;
    }
    if (rec != null && rec.path != null) {
      try {
        await File(rec.path!).delete();
      } catch (_) {
        // ignore file-system errors
      }
    }
    // Remove recording from in-memory list and DB
    recordings.removeWhere((r) => r.id == id);
    await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    logger.i('Recording id $id deleted from cache.');
  }


  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    // mark as sending
    recordingPart.sending = true;
    await updateRecordingPart(recordingPart);
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (recordingPart.dataBase64 == null) {
        throw UploadException('Recording part data is null', 410);
      }
      if (jwt == null) {
        throw UploadException('Failed to send recording part to backend', 401);
      }
      logger.i('Uploading recording part (backendRecordingId: ${recordingPart
          .backendRecordingId}) with data length: ${recordingPart.dataBase64?.length}');
      // Retrieve the parent recording to obtain its backend ID
      // Recording? parentRecording = await getRecordingFromDbById(
      //     recordingPart.recordingId!);
      //recordingPart.backendRecordingId = parentRecording?.BEId ?? 0;
      // Database db = await database;
      // db.update('recordingParts', recordingPart.toJson(), where: 'id = ?',
      //     whereArgs: [recordingPart.id]);
      try {
        final Map<String, Object?> jsonBody = recordingPart.toBEJson();
        final http.Response response = await http.post(
          Uri(scheme: 'https',
              host: Config.host,
              path: '/recordings/part'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode(jsonBody),
        );
        if (response.statusCode == 200) {
          logger.i(response.body);
          int returnedId = jsonDecode(response.body);
          recordingPart.BEId = returnedId;
          recordingPart.sent = true;
          recordingPart.sending = false;
          await updateRecordingPart(recordingPart);
          logger.i('Recording part id: ${recordingPart.id} uploaded successfully.');
        } else {
          // reset sending flag on failure
          recordingPart.sending = false;
          await updateRecordingPart(recordingPart);
          throw UploadException('Failed to upload part id: ${recordingPart.id}',
              response.statusCode);
        }
      } catch (e, stackTrace) {
        // reset sending flag on exception
        //logger.e('Error uploading part: $e' ,error: e, stackTrace: stackTrace);
        //Sentry.captureException(e, stackTrace: stackTrace);
        recordingPart.sending = false;
        await updateRecordingPart(recordingPart);
        rethrow;
      }
    } catch (e, stackTrace) {
      // reset sending flag on exception
      logger.e('Error uploading part: $e' ,error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recordingPart.sending = false;
      await updateRecordingPart(recordingPart);
      rethrow;
    }
  }

  static Future<void> updateRecording(Recording recording) async {
    try {
      int index = recordings.indexWhere((r) => r.id == recording.id);
      if (index != -1) {
        recordings[index] = recording;
      } else {
        recordings.add(recording);
      }
      final db = await database;
      await db.update('recordings', recording.toJson(), where: 'id = ?',
          whereArgs: [recording.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> updateRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      int index = recordingParts.indexWhere((r) => r.id == recordingPart.id);
      if (index != -1) {
        recordingParts[index] = recordingPart;
      } else {
        recordingParts.add(recordingPart);
      }
      await db.update('recordingParts', recordingPart.toJson(), where: 'id = ?',
          whereArgs: [recordingPart.id]);
    } catch (e, stackTrace) {
      logger.e(
          'Failed to update recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Update an existing recording on the backend
  /// Uses PATCH /recordings/[BEId]/edit
  static Future<void> updateRecordingBE(Recording recording) async {
    // Recording must already exist on backend
    if (recording.BEId == null) {
      logger.w('Cannot update recording on backend because BEId is null.');
      return;
    }

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw UploadException('Failed to update recording on backend', 401);
    }

    final Uri url = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/recordings/${recording.BEId}',
    );

    final http.Response response = await http.patch(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'name': recording.name,
        'note': recording.note,
        'estimatedBirdsCount': recording.estimatedBirdsCount,
        'device': recording.device,
      }),
    );

    if (response.statusCode == 200) {
      logger.i(
          'Recording BEId ${recording.BEId} successfully updated on backend.');
      // Keep local DB in sync
      await updateRecording(recording);
    } else {
      throw UploadException(
        'Failed to update recording on backend',
        response.statusCode,
      );
    }
  }

  static Future<void> fetchRecordingsFromBE() async {
    fetching = true;
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (jwt == null) {
        throw FetchException('Failed to fetch recordings from backend', 401);
      }
      // Read userId from secure storage instead of using email
      String? userId = await FlutterSecureStorage().read(key: 'userId');
      if (userId == null) {
        throw FetchException(
            'Failed to fetch recordings from backend: userId not found', 401);
      }
      Uri url = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings',
        query: 'parts=true&userId=$userId',
      );
      final http.Response response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      });
      if (response.statusCode == 200) {
        var body = json.decode(response.body);
        // email is not used anymore, but for backward compatibility, pass null
        List<Recording> recordings = List<Recording>.generate(body.length, (i) {
          return Recording.fromBEJson(body[i], null);
        });
        List<RecordingPart> parts = [];
        for (int i = 0; i < body.length; i++) {
          for (int j = 0; j < body[i]['parts'].length; j++) {
            RecordingPart part = RecordingPart.fromBEJson(body[i]['parts'][j], body[i]['id']);
            parts.add(part);

            logger.i('Added part with ID: ${part.id} and BEID: ${part.BEId}');
          }
        }
        fetchedRecordings = recordings;
        fetchedRecordingParts = parts;

        final db = await database;
        final List<Recording> localRecordings = await getRecordings();
        final Set<int?> beIds = recordings.map((r) => r.BEId).toSet();

        // Delete local recordings marked as sent but no longer present on backend
        for (var local in localRecordings) {
          if (local.sent && !beIds.contains(local.BEId)) {
            await deleteRecordingFromCache(local.id!);
            logger.i('Recording id ${local.id} deleted locally (no longer on backend).');
          }
        }

        // Update any local recordings whose data mismatches backend
        for (var beRec in recordings) {
          try {
            var local = localRecordings.firstWhere((r) => r.BEId == beRec.BEId);
            bool needsUpdate = local.name != beRec.name ||
                               local.note != beRec.note ||
                               local.estimatedBirdsCount != beRec.estimatedBirdsCount ||
                               local.device != beRec.device ||
                               local.byApp != beRec.byApp;
            if (needsUpdate) {
              local.name = beRec.name;
              local.note = beRec.note;
              local.estimatedBirdsCount = beRec.estimatedBirdsCount;
              local.device = beRec.device;
              local.byApp = beRec.byApp;
              await updateRecording(local);
              logger.i('Recording id ${local.id} updated to match backend data.');
            }
          } catch (_) {
            // no local match, skip
          }
        }
      } else if (response.statusCode == 204) {
        logger.i('No recordings found on backend.');
      } else {
        throw FetchException(
            'Failed to fetch recordings from backend', response.statusCode);
      }
    } finally {
      fetching = false;
    }
  }

  static Future<List<RecordingPart>> fetchPartsFromDbById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.rawQuery(
        "SELECT * FROM recordingParts WHERE RecordingId = $id");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<List<RecordingPart>> getPartsById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query(
        "recordingParts", where: "recordingId = ?", whereArgs: [id]);
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<RecordingPart?> getRecordingPartByBEID(int id) async {
    final url = Uri(scheme: "https",
        host: Config.host,
        path: "/recordings/$id",
        query: "parts=true&sound=false");

    logger.i(url);

    try {
      final resp = await http.get(url);

      if (resp.statusCode == 200) {
        logger.i("sending req was succesfull");
        var part = RecordingPart.fromBEJson(
            json.decode(resp.body)['parts'][0], id);
        return part;
      }
      else {
        logger.i(
            "req failed with statuscode ${resp.statusCode} -> ${resp.body}");
      }
    }
    catch (e) {
      return null;
    }
  }

  static Future<void> downloadRecording(int id) async {
    Recording? recording = await getRecordingFromDbById(id);
    if (recording == null) {
      throw FetchException('Recording not found in local database', 404);
    }
    if (recording.downloaded) return;

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }

    // Fetch all parts for this recording
    List<RecordingPart> parts = await getRecordingParts();
    Directory tempDir = await getApplicationDocumentsDirectory();
    List<String> paths = [];

    for (final part in parts.where((p) => p.recordingId == id)) {
      // Download each part's full sound
      final Uri url = Uri(
        scheme: 'https',
        host: Config.host,
        path: '/recordings/part/${recording.BEId}/${part.BEId}/sound',
      );
      try{
        final http.Response response = await http.get(url, headers: {
          'Authorization': 'Bearer $jwt',
        });
        if (response.statusCode != 200) {
          throw FetchException('Failed to download recording part: /recordings/part/${recording.BEId}/${part.BEId}/sound', response.statusCode);
        }
        // Save part to disk
        final String partFilePath = '${tempDir.path}/recording_${recording.BEId}_${part.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
        File file = await File(partFilePath).create();
        await file.writeAsBytes(response.bodyBytes);

        // Update part path and mark as sent
        part.path = partFilePath;
        part.sent = true;
        await updateRecordingPart(part);

        paths.add(partFilePath);
      }
      catch(e, stackTrace){
        if(e is FetchException){
          rethrow;
        }
        else{
          logger.e('Error downloading part BEID: ${part.BEId}: $e', error: e, stackTrace: stackTrace);
          Sentry.captureException(e, stackTrace: stackTrace);
        }
      }
    }

    logger.i('Dowloaded all parts');

    // Concatenate all parts into one file
    final String outputPath = '${tempDir.path}/recording_${recording.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
    await concatWavFiles(paths, outputPath);

    recording.path = outputPath;
    recording.downloaded = true;
    await updateRecording(recording);

    logger.i('Downloaded recording id: $id. File saved to: $outputPath');
  }

  static Future<void> concatRecordingParts(int recordingId) async {
    List<RecordingPart> parts = await getPartsById(recordingId);
    if (parts.isEmpty) {
      logger.i('No parts found for recording id: $recordingId');
      return;
    }

    // Ensure parts are processed in chronological order
    parts.sort((a, b) => a.startTime.compareTo(b.startTime));

    final dir = await getApplicationDocumentsDirectory();
    final List<String> paths = [];

    for (final part in parts) {
      if (part.path != null) {
        // Re‑use the existing on‑disk file
        paths.add(part.path!);
      } else {
        logger.w('Part id: ${part.id} has no path on disk. Skipping.');
      }
    }

    if (paths.isEmpty) {
      logger.w('No valid parts found for recording id: $recordingId');
      return;
    }

    final String outputPath =
        '${dir.path}/recording_${DateTime.now().microsecondsSinceEpoch}.wav';

    try{
      await concatWavFiles(paths, outputPath);
    }
    catch(e, stackTrace){
      logger.e('Failed to concatenate recording parts for id: $recordingId', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return;
    }


    logger.i('Supposed file path: $outputPath');

    final Recording recording =
        recordings.firstWhere((r) => r.id == recordingId);
    recording
      ..path = outputPath
      ..downloaded = true;
    await updateRecording(recording);

    logger.i(
        'Concatenated recording parts for id: $recordingId. File saved to: $outputPath');
  }

  static Future<Database> initDb() async {
    return openDatabase(
        'soundNew.db', version: 5, onCreate: (Database db, int version) async {
      await db.execute('''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY,
        BEId INTEGER UNIQUE,
        mail TEXT,
        createdAt TEXT,
        estimatedBirdsCount INTEGER,
        device TEXT,
        byApp INTEGER,
        name TEXT,
        note TEXT,
        path TEXT,
        sent INTEGER,
        downloaded INTEGER,
        sending INTEGER
      )
      ''');
      await db.execute('''
      CREATE TABLE recordingParts(
        id INTEGER PRIMARY KEY,
        BEId INTEGER UNIQUE,
        recordingId INTEGER,
        backendRecordingId INTEGER,
        startTime TEXT,
        endTime TEXT,
        gpsLatitudeStart REAL,
        gpsLatitudeEnd REAL,
        gpsLongitudeStart REAL,
        gpsLongitudeEnd REAL,
        length INTEGER,
        path TEXT,
        square TEXT,
        sent INTEGER,
        sending INTEGER DEFAULT 0,
        FOREIGN KEY(recordingId) REFERENCES recordings(id)
      )
      ''');
      await db.execute('''
      CREATE TABLE images(
        id INTEGER PRIMARY KEY,
        recordingId INTEGER,
        path TEXT,
        sent INTEGER,
        FOREIGN KEY(recordingId) REFERENCES recordings(id)
      )
      ''');
      await db.execute('''
      CREATE TABLE Notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        type INTEGER NOT NULL,
        read INTEGER DEFAULT 0
      )
      ''');
      await db.execute('''
      CREATE TABLE Dialects (
        RecordingId INTEGER PRIMARY KEY AUTOINCREMENT,
        BEId INTEGER UNIQUE,
        dialect TEXT NOT NULL,
        StartDate TEXT NOT NULL,
        EndDate TEXT NOT NULL,
        FOREIGN KEY(RecordingId) REFERENCES recordings(id)
      )
      ''');
    }, onOpen: (Database db) async {
      final String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (jwt == null) {
        logger.i('No JWT token found. Skipping loading recordings.');
        return;
      }
      final String email = JwtDecoder.decode(jwt)['sub'];
      final List<Map<String, dynamic>> recs = await db.query(
          "recordings", where: "mail = ?", whereArgs: [email]);
      recordings =
          List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
      final List<Map<String, dynamic>> parts = await db.query("recordingParts");
      recordingParts =
          List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
      loadedRecordings = true;
      enforceMaxRecordings();           // ← this blocks the open
    }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion <= 1) {
        // Add the new backendRecordingId column to recordingParts table
        await db.execute(
            'ALTER TABLE recordingParts ADD COLUMN backendRecordingId INTEGER;');
        await db.setVersion(2);
      }
      if (oldVersion <= 2) {
        logger.w(
            'Old version detected (<=2). Recreating entire database schema...');
        // Drop existing tables
        await db.execute('DROP TABLE IF EXISTS recordings');
        await db.execute('DROP TABLE IF EXISTS recordingParts');
        await db.execute('DROP TABLE IF EXISTS images');
        await db.execute('DROP TABLE IF EXISTS Notifications');
        await db.execute('DROP TABLE IF EXISTS Dialects');

        // Recreate tables as defined in the onCreate callback
        await db.execute('''
          CREATE TABLE recordings(
            id INTEGER PRIMARY KEY,
            BEId INTEGER UNIQUE,
            mail TEXT,
            createdAt TEXT,
            estimatedBirdsCount INTEGER,
            device TEXT,
            byApp INTEGER,
            name TEXT,
            note TEXT,
            path TEXT,
            sent INTEGER,
            downloaded INTEGER,
            sending INTEGER
          )
        ''');
        await db.execute('''
            CREATE TABLE recordingParts(
            id INTEGER PRIMARY KEY,
            BEId INTEGER UNIQUE,
            recordingId INTEGER,
            backendRecordingId INTEGER,
            startTime TEXT,
            endTime TEXT,
            gpsLatitudeStart REAL,
            gpsLatitudeEnd REAL,
            gpsLongitudeStart REAL,
            gpsLongitudeEnd REAL,
            path TEXT,
            length INTEGER DEFAULT 0,
            square TEXT,
            sent INTEGER,
            sending INTEGER DEFAULT 0,
            FOREIGN KEY(recordingId) REFERENCES recordings(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE images(
            id INTEGER PRIMARY KEY,
            recordingId INTEGER,
            path TEXT,
            sent INTEGER,
            FOREIGN KEY(recordingId) REFERENCES recordings(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE Notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            body TEXT NOT NULL,
            receivedAt TEXT NOT NULL,
            type INTEGER NOT NULL,
            read INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE Dialects (
            RecordingId INTEGER PRIMARY KEY AUTOINCREMENT,
            BEId INTEGER UNIQUE,
            dialectCode TEXT NOT NULL,
            StartDate TEXT NOT NULL,
            EndDate TEXT NOT NULL,
            FOREIGN KEY(RecordingId) REFERENCES recordings(id)
          )
        ''');
        await db.setVersion(newVersion);
      }
      // Upgrade from v3 → v4: add the 'sending' column to recordingParts
      if (oldVersion <= 3) {
      await db.execute(
        'ALTER TABLE recordingParts ADD COLUMN sending INTEGER DEFAULT 0;'
      );
      await db.setVersion(newVersion);
      }
      if(oldVersion<=4){
        await db.execute(
          'ALTER TABLE Dialects RENAME COLUMN dialect TO dialectCode;'
        );
        await db.setVersion(newVersion);
      }
      if(oldVersion<=5){
        await db.execute(
            'ALTER TABLE recordingParts ADD COLUMN length INTEGER'
        );
        await db.setVersion(newVersion);
      }
    });
  }
  static Future<bool> hasInternetAccess() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  static Future<void> insertNotification(RemoteMessage message) async {
    final db = await database;
    await db.insert('Notifications', {
      'title': message.notification?.title,
      'type': int.parse(message.messageType!),
      'body': message.notification?.body,
      'receivedAt': DateTime.now().toIso8601String(),
    });
  }

  // New helper method to insert a custom local notification.
  static Future<void> sendLocalNotification(String title,
      String message) async {
    final String fcmToken = ((await FlutterSecureStorage().read(
        key: 'fcmToken'))) ?? '';
    if (fcmToken == '') {
      logger.w("Failed to send local notification: FCM token is empty");
      return;
    }
    await sendPushNotificationDirectly(fcmToken, title, message);
    // final db = await database;
    // await db.insert('Notifications', {
    //   'title': title,
    //   'body': message,
    //   'receivedAt': DateTime.now().toIso8601String(),
    //   'type': 0, // 0 for local notifications
    //   'read': 0,
    // });
    // logger.i("Local notification inserted: $title - $message");
  }

  static Future<List<NotificationItem>> getNotificationList() async {
    final db = await database;
    final List<Map<String, dynamic>> notifications = await db.query(
        'Notifications');
    List<NotificationItem> messages = [];
    for (Map<String, dynamic> notification in notifications) {
      messages.add(NotificationItem(
        title: notification['title'],
        message: notification['body'],
        time: notification['receivedAt'],
        unread: notification['read'] == 0,
      ));
    }
    return messages;
  }

  static Future<Recording?> getRecordingFromDbById(int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> results =
    await db.query("recordings", where: "id = ?", whereArgs: [recordingId]);
    if (results.isNotEmpty) {
      return Recording.fromJson(results.first);
    }
    return null;
  }

  static Future<void> insertRecordingDialect(
      RecordingDialect recordingDialect) async {
    final db = await database;
    await db.insert("Dialects", recordingDialect.toJson());
    logger.i('Recording dialect ${recordingDialect.RecordingId} inserted.');
  }

  static Future<List<RecordingDialect>> getRecordingDialects(
      int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> results =
    await db.query(
        "Dialects", where: "RecordingId = ?", whereArgs: [recordingId]);
    return List.generate(
        results.length, (i) => RecordingDialect.fromJson(results[i]));
  }

  static Future<List<RecordingDialect>> getRecordingDialectsBE(int recordingBEID) async{
    logger.i('Loading dialects for recording: ${recordingBEID}');
    http.Response response;
    try {
      final String jwt = await FlutterSecureStorage().read(key: 'token') ?? '';
      final Uri url = Uri(
          scheme: 'https',
          host: Config.host,
          path: '/recordings/filtered/$recordingBEID',
          query: 'verified=true');
      response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt'
      },);
    }
    catch(e, stackTrace){
      logger.e('Failed to load dialects for recording: ${recordingBEID} :$e', error: e, stackTrace: stackTrace);
      return [];
    }
    try {
      if (response.statusCode == 200) {
        logger.i('Loaded dialects for recording: ${recordingBEID}');
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded.map((item) =>
            RecordingDialect.fromJson(item as Map<String, dynamic>)
          ).toList();
        } else {
          return [];
        }
      }
      else {
        logger.e('Failed to load $recordingBEID dialects: ${response.statusCode} | ${response.body}');
        return [];
      }
    }
    catch(e, stackTrace){
      logger.e('Failed to load $recordingBEID dialects: $e', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Checks whether *all* parts of the given recording have been sent.
  /// Throws [UnsentPartsException] if any part remains unsent.
  static Future<void> checkRecordingPartsSent(int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where: 'recordingId = ? AND sent = ?',
      whereArgs: [recordingId, 0],
    );
    if (unsent.isNotEmpty) {
      throw UnsentPartsException();
    }
  }

  /// Attempts to resend any recording parts that were not sent previously.
  static Future<void> resendUnsentParts() async {
    final db = await database;
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where: 'sent = ?',
      whereArgs: [0],
    );
    for (final partMap in unsent) {
      try {
        RecordingPart part = RecordingPart.fromJson(partMap);
        part.sending = true;
        await updateRecordingPart(part);
        await sendRecordingPart(part);
      } catch (e, stackTrace) {
        logger.e(
            'Failed to resend recording part id: ${partMap['id']}', error: e,
            stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
  }
}