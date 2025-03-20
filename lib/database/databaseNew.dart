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
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/exceptions.dart';
// Missing import added:
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:strnadi/recording/waw.dart';

import '../notificationPage/notifications.dart';

final logger = Logger();

/// Models

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
  String? dataBase64;

  RecordingPartUnready({
    this.id,
    this.recordingId,
    this.startTime,
    this.endTime,
    this.gpsLatitudeStart,
    this.gpsLatitudeEnd,
    this.gpsLongitudeStart,
    this.gpsLongitudeEnd,
    this.dataBase64,
  });
}

class Recording {
  int? id;
  int? BEId;
  String mail;
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
    this.BEId,
    required this.mail,
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
      BEId: json['BEId'] as int?,
      mail: json['mail'] as String,
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

  factory Recording.fromBEJson(Map<String, Object?> json, String mail) {
    return Recording(
      BEId: json['id'] as int?,
      mail: mail,
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
  DateTime startTime;
  DateTime endTime;
  double gpsLatitudeStart;
  double gpsLatitudeEnd;
  double gpsLongitudeStart;
  double gpsLongitudeEnd;
  String? square;
  String? dataBase64;
  bool sent;

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
    this.dataBase64,
    this.sent = false,
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
      dataBase64: json['dataBase64'] as String?,
    );
  }

  factory RecordingPart.fromBEJson(Map<String, Object?> json, int recordingId) {
    return RecordingPart(
      BEId: json['id'] as int?,
      recordingId: recordingId,
      startTime: DateTime.parse(json['startDate'] as String),
      endTime: DateTime.parse(json['endDate'] as String),
      gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
      dataBase64: json['dataBase64'] as String?,
      square: json['square'] as String?,
      sent: true,
    );
  }

  factory RecordingPart.fromUnready(RecordingPartUnready unready) {
    if (unready.startTime == null ||
        unready.endTime == null ||
        unready.gpsLatitudeStart == null ||
        unready.gpsLatitudeEnd == null ||
        unready.gpsLongitudeStart == null ||
        unready.gpsLongitudeEnd == null ||
        unready.dataBase64 == null) {
      logger.i(
          'Recording part is not ready. Part id: ${unready.id}, recording id: ${unready.recordingId}, start time: ${unready.startTime}, end time: ${unready.endTime}, gpsLatitudeStart: ${unready.gpsLatitudeStart}, gpsLatitudeEnd: ${unready.gpsLatitudeEnd}, gpsLongitudeStart: ${unready.gpsLongitudeStart}, gpsLongitudeEnd: ${unready.gpsLongitudeEnd}, dataBase64: ${unready.dataBase64}');
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
      dataBase64: unready.dataBase64,
      square: null,
      sent: false,
    );
  }

  Map<String, Object?> toBEJson() {
    return {
      'id': BEId,
      'recordingId': recordingId,
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
      'recordingId': recordingId,
      'startTime': startTime.toString(),
      'endTime': endTime.toString(),
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'dataBase64': dataBase64,
      'square': square,
      'sent': sent ? 1 : 0,
    };
  }
}

/// Database helper class
class DatabaseNew {
  static Database? _database;
  static List<Recording> recordings = List<Recording>.empty(growable: true);
  static List<RecordingPart> recordingParts = List<RecordingPart>.empty(growable: true);

  static List<Recording>? fetchedRecordings;
  static List<RecordingPart>? fetchedRecordingParts;

  static bool fetching = false;
  static bool loadedRecordings = false;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<int> insertRecording(Recording recording) async {
    try {
      final db = await database;
      if (recording.BEId != null) {
        List<Map<String, dynamic>> existing =
        await db.query("recordings", where: "BEId = ?", whereArgs: [recording.BEId]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recording.id = id;
          await db.update("recordings", recording.toJson(), where: "id = ?", whereArgs: [id]);
          int index = recordings.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordings[index] = recording;
          } else {
            recordings.add(recording);
          }
          logger.i('Recording with BEId ${recording.BEId} updated (id: $id), path: ${recording.path}');
          return id;
        }
      }
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      recordings.add(recording);
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
      if (recordingPart.BEId != null) {
        List<Map<String, dynamic>> existing =
        await db.query("recordingParts", where: "BEId = ?", whereArgs: [recordingPart.BEId]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recordingPart.id = id;
          await db.update("recordingParts", recordingPart.toJson(), where: "id = ?", whereArgs: [id]);
          int index = recordingParts.indexWhere((r) => r.id == id);
          if (index != -1) {
            recordingParts[index] = recordingPart;
          } else {
            recordingParts.add(recordingPart);
          }
          logger.i('Recording part with BEId ${recordingPart.BEId} updated (id: $id). Data length: ${recordingPart.dataBase64?.length}');
          return id;
        }
      }
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      recordingParts.add(recordingPart);
      logger.i('Recording part ${recordingPart.id} inserted. Data length: ${recordingPart.dataBase64?.length}');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<void> onFetchFinished() async {
    List<Recording> oldRecordings = await getRecordings();
    List<Recording> sentRecordings = oldRecordings.where((recording) => recording.sent).toList();

    if(fetchedRecordings == null || fetchedRecordingParts == null) {
      logger.i('No recordings fetched from backend.');
      return;
    }
    if(fetchedRecordings!.isEmpty || fetchedRecordingParts!.isEmpty) {
      logger.i('No recordings fetched from backend.');
      return;
    }

    List<Recording> newRecordings = fetchedRecordings!
        .where((recording) => !sentRecordings.any((r) => r.BEId == recording.BEId))
        .toList();

    for (Recording recording in newRecordings) {
      recording.sent = true;
      recording.downloaded = false;
      logger.i('Inserting recording with BEId: ${recording.BEId} and name ${recording.name}');
      await insertRecording(recording);
    }

    List<RecordingPart> oldRecordingParts = await getRecordingParts();
    List<RecordingPart> newRecordingParts = fetchedRecordingParts!
        .where((newPart) => !oldRecordingParts.any((p) => p.BEId == newPart.BEId))
        .toList();

    for (RecordingPart recordingPart in newRecordingParts) {
      recordingPart.sent = true;
      await insertRecordingPart(recordingPart);
    }
  }

  static Future<void> syncRecordings() async {
    if (fetching) return;
    try {
      await fetchRecordingsFromBE();
      await onFetchFinished();
      logger.i('Recordings fetched and synced.');
    } catch (e, stackTrace) {
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<List<Recording>> getRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> recs = await db.query("recordings");
    return List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
  }

  static Future<List<RecordingPart>> getRecordingParts() async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query("recordingParts");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<void> deleteRecording(int id) async {
    final db = await database;
    List<RecordingPart> recordingPartsCopy = List<RecordingPart>.from(recordingParts);
    for (RecordingPart part in recordingPartsCopy) {
      if (part.recordingId == id) {
        recordingParts.remove(part);
        await db.delete("recordingParts", where: "recordingId = ?", whereArgs: [id]);
      }
    }
    await db.delete("recordings", where: "id = ?", whereArgs: [id]);
    logger.i('Recording id: $id deleted.');
  }

  static Future<void> sendRecordingBackground(int recordingId) async {

    await Workmanager().registerOneOffTask(
      (Platform.isIOS)? "com.delta.strnadi.sendRecording" : "sendRecording_${DateTime.now().microsecondsSinceEpoch}",
      (Platform.isIOS)? "sendRecording_${DateTime.now().microsecondsSinceEpoch}": "sendRecording",
      inputData: {"recordingId": recordingId},
    );
  }

  static Future<void> sendRecording(Recording recording, List<RecordingPart> recordingParts) async {
    if (!await hasInternetAccess()) {
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
      Uri.https('api.strnadi.cz', '/recordings/upload'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(recording.toBEJson()),
    );
    if (response.statusCode == 200) {
      recording.BEId = jsonDecode(response.body);
      final db = await database;
      await db.update('recordings', recording.toJson(), where: 'id = ?', whereArgs: [recording.id]);
      for (RecordingPart part in recordingParts) {
        part.recordingId = recording.BEId;
        await sendRecordingPart(part);
      }
      recording.sent = true;
      recording.sending = false;
      await updateRecording(recording);
      logger.i('Recording id ${recording.id} sent successfully.');
    } else {
      recording.sending = false;
      await updateRecording(recording);
      throw UploadException('Failed to send recording to backend', response.statusCode);
    }
  }

  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (recordingPart.dataBase64 == null) {
      throw UploadException('Recording part data is null', 410);
    }
    if (jwt == null) {
      throw UploadException('Failed to send recording part to backend', 401);
    }
    logger.i('Uploading recording part (BEId: ${recordingPart.BEId}) with data length: ${recordingPart.dataBase64?.length}');
    final Map<String, Object?> jsonBody = recordingPart.toBEJson();
    final http.Response response = await http.post(
      Uri(scheme: 'https', host: 'api.strnadi.cz', path: '/recordings/upload-part'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(jsonBody),
    );
    if (response.statusCode == 200) {
      recordingPart.sent = true;
      await updateRecordingPart(recordingPart);
      logger.i('Recording part id: ${recordingPart.id} uploaded successfully.');
    } else {
      throw UploadException('Failed to upload part id: ${recordingPart.id}', response.statusCode);
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
      await db.update('recordings', recording.toJson(), where: 'id = ?', whereArgs: [recording.id]);
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
      await db.update('recordingParts', recordingPart.toJson(), where: 'id = ?', whereArgs: [recordingPart.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> fetchRecordingsFromBE() async {
    fetching = true;
    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      if (jwt == null) {
        throw FetchException('Failed to fetch recordings from backend', 401);
      }
      final String email = JwtDecoder.decode(jwt)['sub'];
      Uri url = Uri(
        scheme: 'https',
        host: 'api.strnadi.cz',
        path: '/recordings',
        queryParameters: {'parts': 'true', 'email': email},
      );
      final http.Response response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      });
      if (response.statusCode == 200) {
        var body = json.decode(response.body);
        List<Recording> recordings = List<Recording>.generate(body.length, (i) {
          return Recording.fromBEJson(body[i], email);
        });
        List<RecordingPart> parts = [];
        for (int i = 0; i < body.length; i++) {
          for (int j = 0; j < body[i]['parts'].length; j++) {
            parts.add(RecordingPart.fromBEJson(body[i]['parts'][j], body[i]['id']));
          }
        }
        fetchedRecordings = recordings;
        fetchedRecordingParts = parts;
      } else if (response.statusCode == 204) {
        logger.i('No recordings found on backend.');
      } else {
        throw FetchException('Failed to fetch recordings from backend', response.statusCode);
      }
    } finally {
      fetching = false;
    }
  }

  static List<RecordingPart> getPartsById(int id) {
    return recordingParts.where((part) => part.recordingId == id).toList();
  }

  static Future<void> downloadRecording(int id) async {
    Recording recording = recordings.firstWhere((r) => r.id == id);
    if (recording.downloaded) return;
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }
    Uri url = Uri(
      scheme: 'https',
      host: 'api.strnadi.cz',
      path: '/recordings/${recording.BEId}',
      queryParameters: {'parts': 'true', 'sound': 'true'},
    );
    final http.Response response = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    });
    if (response.statusCode != 200) {
      throw FetchException('Failed to download recording', response.statusCode);
    }
    final Map<String, dynamic> responseData = jsonDecode(response.body);
    final List<dynamic> partsJson = responseData['parts'];
    Directory tempDir = await getApplicationDocumentsDirectory();
    List<String> paths = [];
    for (int i = 0; i < partsJson.length; i++) {
      final partData = partsJson[i];
      RecordingPart part = RecordingPart.fromBEJson(partData, recording.BEId!);
      part.dataBase64 = partData['dataBase64'];
      part.sent = true;
      await updateRecordingPart(part);
      String partFilePath = '${tempDir.path}/recording_${DateTime.now().microsecondsSinceEpoch}.wav';
      File partFile = File(partFilePath);
      await partFile.writeAsBytes(base64Decode(part.dataBase64!));
      paths.add(partFilePath);
    }
    String outputPath = '${tempDir.path}/recording_${DateTime.now().microsecondsSinceEpoch}.wav';
    await concatWavFiles(paths, outputPath, 44100, 44100 * 16);
    recording.path = outputPath;
    recording.downloaded = true;
    await updateRecording(recording);
    logger.i('Downloaded recording id: $id. File saved to: $outputPath');
  }

  static Future<Database> initDb() async {
    return openDatabase('soundNew.db', version: 1, onCreate: (Database db, int version) async {
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
        startTime TEXT,
        endTime TEXT,
        gpsLatitudeStart REAL,
        gpsLatitudeEnd REAL,
        gpsLongitudeStart REAL,
        gpsLongitudeEnd REAL,
        dataBase64 TEXT,
        square TEXT,
        sent INTEGER,
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
    }, onOpen: (Database db) async {
      final List<Map<String, dynamic>> recs = await db.query("recordings");
      recordings = List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
      final List<Map<String, dynamic>> parts = await db.query("recordingParts");
      recordingParts = List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
      loadedRecordings = true;
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
  static Future<void> sendLocalNotification(String title, String message) async {
    final String fcmToken = ((await FlutterSecureStorage().read(key: 'fcmToken'))) ?? '';
    if(fcmToken == ''){
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
    final List<Map<String, dynamic>> notifications = await db.query('Notifications');
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
}