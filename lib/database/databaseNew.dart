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
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/main.dart';
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:workmanager/workmanager.dart';

final logger = Logger();

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
    this.path
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
      sent: true,
      downloaded: false,
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

  Map<String, Object?> toBEJson(){
    return {
      'id': BEId,
      'createdAt': createdAt.toIso8601String(),
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp,
      'note': note,
      'name': name
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Recording) return false;
    bool equal = true;
    if (this.BEId != null && other.BEId != null) {
      equal = equal && this.BEId == other.BEId;
    }
    if (this.mail != null && other.mail != null) {
      equal = equal && this.mail == other.mail;
    }
    if (this.createdAt != null && other.createdAt != null) {
      equal = equal && this.createdAt == other.createdAt;
    }
    if (this.estimatedBirdsCount != null && other.estimatedBirdsCount != null) {
      equal = equal && this.estimatedBirdsCount == other.estimatedBirdsCount;
    }
    if (this.device != null && other.device != null) {
      equal = equal && this.device == other.device;
    }
    if (this.byApp != null && other.byApp != null) {
      equal = equal && this.byApp == other.byApp;
    }
    if (this.note != null && other.note != null) {
      equal = equal && this.note == other.note;
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
        note ?? ''
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
    );
  }

  factory RecordingPart.fromBEJson(Map<String, Object?> json, int recordingId) {
    return RecordingPart(
      BEId: json['id'] as int?,
      recordingId: recordingId,
      startTime: DateTime.parse(json['start'] as String),
      endTime: DateTime.parse(json['end'] as String),
      gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
      square: json['square'] as String?,
      sent: true
    );
  }

  factory RecordingPart.fromUnready(RecordingPartUnready unready) {
    if (unready.id == null ||
        unready.recordingId == null ||
        unready.startTime == null ||
        unready.endTime == null ||
        unready.gpsLatitudeStart == null ||
        unready.gpsLatitudeEnd == null ||
        unready.gpsLongitudeStart == null ||
        unready.gpsLongitudeEnd == null ||
        unready.dataBase64 == null) {
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
        sent: false);
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
      'square': square,
      'sent': sent ? 1 : 0,
    };
  }
}

class DatabaseNew {
  static Database? _database;

  static List<Recording> recordings = List<Recording>.empty(growable: true);
  static List<RecordingPart> recordingParts =
      List<RecordingPart>.empty(growable: true);

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
      logger.i('Getting database');
      final db = await database;
      logger.i('Inserting recording');
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      recordings.add(recording);
      logger.i('Recording ${recording.id} inserted');
      return id;
    }
    catch(e, stackTrace){
      logger.e('Failed to insert recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<int> insertRecordingPart(RecordingPart recordingPart) async {
    try {
      logger.i('Getting database');
      final db = await database;
      logger.i('Inserting recording part');
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      recordingParts.add(recordingPart);
      logger.i('Recording part ${recordingPart.id} inserted');
      return id;
    }
    catch(e, stackTrace){
      logger.e('Failed to insert recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<void> onFetchFinished() async {
    List<Recording> oldRecordings = await getRecordings();

    List<Recording> sentRecordings =
        oldRecordings.where((recording) => recording.sent).toList();

    List<Recording> newRecordings = fetchedRecordings!
        .where((recording) => !sentRecordings.contains(recording))
        .toList();

    for (Recording recording in newRecordings) {
      recording.sent = true;
      recording.downloaded = false;
      await insertRecording(recording);
    }

    List<RecordingPart> newRecordingParts =
        List<RecordingPart>.empty(growable: true);
    newRecordings.forEach((recording) {
      newRecordingParts.addAll(fetchedRecordingParts!
          .where((part) => part.recordingId == recording.BEId));
    });

    for (RecordingPart recordingPart in newRecordingParts) {
      recordingPart.sent = true;
      await insertRecordingPart(recordingPart);
    }

    //TODO: Implement the same for images

    //TODO: Implement update
  }

  static Future<void> syncRecordings() async {
    if (fetching) {
      return;
    }
    try {
      await fetchRecordingsFromBE();
      await onFetchFinished();
      logger.i('Recordings fetched');
    }
    catch (e, stackTrace){
      logger.e("An error has eccured $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    } catch (e) {
      logger.e(e);
      Sentry.captureException(e);
    }
  }

  static Future<List<Recording>> getRecordings() async {
    logger.i('Getting recordings');
    final db = await database;
    final List<Map<String, dynamic>> recordings = await db.query("recordings");
    return List.generate(recordings.length, (i) {
      return Recording.fromJson(recordings[i]);
    });
  }

  static Future<List<RecordingPart>> getRecordingParts() async {
    logger.i('Getting recording parts');
    final db = await database;
    final List<Map<String, dynamic>> recordingParts =
        await db.query("recordingParts");
    return List.generate(recordingParts.length, (i) {
      return RecordingPart.fromJson(recordingParts[i]);
    });
  }

  static Future<void> deleteRecording(int id) async {
    logger.i('Deleting recording id: $id');
    final db = await database;
    List<RecordingPart> recordingPartsCopy =
        List<RecordingPart>.from(recordingParts);
    for (RecordingPart recording in recordingPartsCopy) {
      if (recording.recordingId == id) {
        logger.i('Deleting recording part id: ${recording.id}');
        recordingParts.remove(recording);
        await db.delete("recordingParts",
            where: "recordingId = ?", whereArgs: [id]);
      }
    }
    await db.delete("recordings", where: "id = ?", whereArgs: [id]);
    logger.i('Recording id: $id deleted');
  }

  static Future<void> sendRecordingBackground(int recordingId) async {
    await Workmanager().registerOneOffTask(
      "sendRecording_$recordingId", // A unique name for the task.
      "sendRecording", // The task identifier used in the callback.
      inputData: {
        "recordingId": recordingId,
      },
    );
  }

  static Future<void> sendRecording(
      Recording recording, List<RecordingPart> recordingParts) async {
    if (!await hasInternetAccess()) {
      recording.sending = false;
      updateRecording(recording);
      return;
    }
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      recording.sending = false;
      updateRecording(recording);
      throw FetchException('Failed to send recording to backend', 401);
    }
    final http.Response response =
        await http.post(Uri.https('api.strnadi.cz', '/recordings/upload'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode(recording.toBEJson()));
    if (response.statusCode == 200) {
      recording.BEId = jsonDecode(response.body);
      final db = await database;
      await db.update('recordings', recording.toJson(),
          where: 'id = ?', whereArgs: [recording.id]);
      for (RecordingPart part in recordingParts) {
        part.recordingId = recording.BEId;
        await sendRecordingPart(part);
      }
      recording.sent = true;
      recording.sending = false;
      updateRecording(recording);
    } else {
      recording.sending = false;
      updateRecording(recording);
      throw UploadException('Failed to send recording to backend', response.statusCode);
      throw UploadException(
          'Failed to send recording to backend', response.statusCode);
    }
  }

  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    Map<String, Object?> json = recordingPart.toBEJson();
    if (recordingPart.dataBase64 == null) {
      throw UploadException('Recording part data is null', 410);
    }
    if (jwt == null) {
      throw UploadException('Failed to send recording part to backend', 401);
    }
    final http.Response response =
        await http.post(Uri.https('api.strnadi.cz', '/recordingParts/upload'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $jwt',
            },
            body: jsonEncode(json));
    if (response.statusCode == 200) {
      logger.i('Recording part id: ${recordingPart.id} uploaded');
      recordingPart.sent = true;
      updateRecordingPart(recordingPart);
    } else {
      throw UploadException(
          'Failed to upload part id: ${recordingPart.id}', response.statusCode);
    }
  }

  static Future<void> updateRecording(Recording recording) async {
    try{
      recordings[recordings.indexWhere((element) => element.id == recording.id)] = recording;
      final db = await database;
      await db.update('recordings', recording.toJson(), where: 'id = ?', whereArgs: [recording.id]);
    }
    catch(e, stackTrace){
      logger.e('Failed to update recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> updateRecordingPart(RecordingPart recordingPart) async {
    try {
      recordingParts[recordingParts.indexWhere((element) =>
      element.id == recordingPart.id)] = recordingPart;
      final db = await database;
      await db.update('recordingParts', recordingPart.toJson(), where: 'id = ?',
          whereArgs: [recordingPart.id]);
    }
    catch(e, stackTrace){
      logger.e('Failed to update recording part', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> fetchRecordingsFromBE() async {
    fetching = true;
    // Fetch recordings from backend



    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      fetching = false;
      throw FetchException('Failed to fetch recordings from backend', 401);
    }
    final String email = JwtDecoder.decode(jwt)['sub'];
    // Fetch recordings from backend
    Uri url = Uri(scheme: 'https',host: 'api.strnadi.cz', path: '/recordings', queryParameters: {
      'parts': 'true',
      'email': email
    });

    final http.Response response = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    });

    var body = json.decode(response.body);

    if (response.statusCode == 200){
      List<Recording> recordings = List<Recording>.generate(body.length, (recordingIndex) {
        return Recording.fromBEJson(body[recordingIndex], email ?? '');
      });

      List<RecordingPart> parts = List<RecordingPart>.empty(growable: true);
      for (int recordingIndex = 0;
          recordingIndex < body.length;
          recordingIndex++) {
        for (int partIndex = 0;
            partIndex < body[recordingIndex]['parts'].length;
            partIndex++) {
          parts.add(RecordingPart.fromBEJson(
              body[recordingIndex]['parts']![partIndex],
              body[recordingIndex]['id']));
        }
      }
      fetchedRecordings = recordings;
      fetchedRecordingParts = parts;

      fetching = false;
      return;
    }
    else if(response.statusCode == 204){ //No content
      fetching = false;
      logger.i('No recordings');
      return;
    }
    else {
      fetching = false;
      throw FetchException(
          'Failed to fetch recordings from backend', response.statusCode);
    }
  }

  static List<RecordingPart> getPartsById(int id) {
    return recordingParts.where((part) => part.recordingId == id).toList();
  }

  static Future<void> downloadRecording(int id) async {
    if (recordings.firstWhere((element) => element.id == id).downloaded) {
      return;
    }

    throw UnimplementedError(); //TODO: Wait for stasik to implement this

    Recording recording = recordings.firstWhere((element) => element.id == id);

    List<RecordingPart> parts = recordingParts
        .where((element) => element.recordingId == recording.BEId)
        .toList();

    Uri url = Uri(
        scheme: 'https',
        host: 'api.strnadi.cz',
        path: '/recordings/${recording.BEId}/download');

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }

    final http.Response response = await http.get(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    });
    if (response.statusCode == 200) {
      Directory tempDir = await getApplicationDocumentsDirectory();
      File file = File('${tempDir.path}/recording_${recording.BEId}.wav');
      file.writeAsBytesSync(response.bodyBytes);
      recording.path = file.path;
      recording.downloaded = true;
      updateRecording(recording);
    } else {
      throw FetchException('Failed to download recording', response.statusCode);
    }
  }

  static Future<Database> initDb() async {
    return openDatabase('soundNew.db', version: 1,
        onCreate: (Database db, int version) async {
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
      recordings =
          List.generate(recs.length, (i) => Recording.fromJson(recs[i]));

      final List<Map<String, dynamic>> parts = await db.query("recordingParts");
      recordingParts =
          List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));

      loadedRecordings = true;
    });
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


  static Future<List<NotificationItem>> getNotificationList() async {
    final db = await database;

    final List<Map<String, dynamic>> notifications =
        await db.query('Notifications');

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
    // TODO add the notification retrieval
  }

  static Future<List<RecordingPartUnready>> trimAudio(
    String audioPath,
    List<int> stopTimesInMilliseconds,
    List<RecordingPartUnready> recordingParts,
  ) async {
    Directory tempDir = await getApplicationDocumentsDirectory();

    // Convert stop times from milliseconds to Duration and sort them.
    List<Duration> stopTimes =
        stopTimesInMilliseconds.map((t) => Duration(milliseconds: t)).toList();
    stopTimes.sort((a, b) => a.inMilliseconds.compareTo(b.inMilliseconds));

    Duration start = Duration.zero;
    List<RecordingPartUnready> trimmedParts = [];

    for (int i = 0; i < stopTimes.length; i++) {
      Duration end = stopTimes[i];
      // Updated output file extension to .wav
      String outputPath = '${tempDir.path}/trimmed_part_$i.wav';

      // Calculate the duration of this segment with fractional seconds.
      double segmentDurationSec = (end - start).inMilliseconds / 1000.0;

      // If segment duration is zero or negative, skip this segment.
      if (segmentDurationSec <= 0) {
        print("Segment $i duration is zero or negative, skipping.");
        continue;
      }

      // Calculate start time in seconds (with fractional precision)
      double startSec = start.inMilliseconds / 1000.0;

      // Updated FFmpeg command to output WAV file using PCM 16-bit little-endian encoding.
      String command =
          '-y -i "$audioPath" -ss ${startSec.toStringAsFixed(2)} -t ${segmentDurationSec.toStringAsFixed(2)} -c:a pcm_s16le "$outputPath"';
      print("Executing FFmpeg command: $command");

      await FFmpegKit.execute(command);

      // Check if the trimmed file was successfully created.
      String savedPath = File(outputPath).existsSync() ? outputPath : "";
      if (savedPath.isEmpty) {
        print("Trimmed file not created: $outputPath");
      }

      // Use the corresponding recording part for location info if available,
      // otherwise create a default one.
      RecordingPartUnready part;
      if (i < recordingParts.length) {
        part = recordingParts[i];
      } else {
        throw InvalidPartException('part $i is invalid', i);
      }
      part.dataBase64 = base64Encode(File(savedPath).readAsBytesSync());
      trimmedParts.add(part);

      start = end;
    }

    return trimmedParts;
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
