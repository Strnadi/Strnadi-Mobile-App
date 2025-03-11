import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'dart:convert';
import 'package:logger/logger.dart';

final logger = Logger();

class FetchException implements Exception {
  final String message;
  final int statusCode;

  FetchException(this.message, this.statusCode);
}

class UploadException implements Exception {
  final String message;
  final int statusCode;

  UploadException(this.message, this.statusCode);
}


class Recording{
  int? id;
  int? BEId;
  String mail;
  String createdAt;
  int estimatedBirdsCount;
  String? device;
  bool byApp;
  String? note;
  String? path;
  bool sent;

  Recording({
    this.id,
    this.BEId,
    required this.mail,
    required this.createdAt,
    required this.estimatedBirdsCount,
    this.device,
    required this.byApp,
    this.note,
    this.path,
    this.sent = false,
  });

  factory Recording.fromJson(Map<String, Object?> json){
    return Recording(
        id: json['id'] as int?,
        BEId: json['BEId'] as int?,
        mail: json['mail'] as String,
        createdAt: json['createdAt'] as String,
        estimatedBirdsCount: json['estimatedBirdsCount'] as int,
        device: json['device'] as String?,
        byApp: (json['byApp'] as int) == 1,
        note: json['note'] as String?,
        path: json['path'] as String?,
        sent: (json['sent'] as int) == 1,
    );
  }

  factory Recording.fromBEJson(Map<String, Object?> json, String mail){
    return Recording(
      BEId: json['id'] as int?,
      mail: mail,
      createdAt: json['createdAt'] as String,
      estimatedBirdsCount: json['estimatedBirdsCount'] as int,
      device: json['device'] as String?,
      byApp: json['byApp'] as bool,
      note: json['note'] as String?,
      sent: true
    );
  }

  Map<String, Object?> toJson(){
    return {
      'id': id,
      'BEId': BEId,
      'mail': mail,
      'createdAt': createdAt,
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp ? 1 : 0,
      'note': note,
      'path': path,
      'sent': sent ? 1 : 0,
    };
  }

  Map<String, Object?> toBEJson(){
    return {
      'id': BEId,
      'createdAt': createdAt,
      'estimatedBirdsCount': estimatedBirdsCount,
      'device': device,
      'byApp': byApp,
      'note': note,
    };
  }
  @override
  bool operator ==(Object other) {
    if(identical(this, other)) return true;
    if(other is! Recording) return false;
    bool equal = true;
    if (this.BEId != null && other.BEId != null){
      equal = equal && this.BEId == other.BEId;
    }
    if (this.mail != null && other.mail != null){
      equal = equal && this.mail == other.mail;
    }
    if (this.createdAt != null && other.createdAt != null){
      equal = equal && this.createdAt == other.createdAt;
    }
    if (this.estimatedBirdsCount != null && other.estimatedBirdsCount != null){
      equal = equal && this.estimatedBirdsCount == other.estimatedBirdsCount;
    }
    if (this.device != null && other.device != null){
      equal = equal && this.device == other.device;
    }
    if (this.byApp != null && other.byApp != null){
      equal = equal && this.byApp == other.byApp;
    }
    if (this.note != null && other.note != null){
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

class RecordingPart{
  int? id;
  int? BEId;
  int? recordingId;
  String startTime;
  String endTime;
  double gpsLatitudeStart;
  double gpsLatitudeEnd;
  double gpsLongitudeStart;
  double gpsLongitudeEnd;
  String? square;
  String? path;
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
    this.path,
    this.sent = false,
  });

  factory RecordingPart.fromJson(Map<String, Object?> json){
    return RecordingPart(
      id: json['id'] as int?,
      BEId: json['BEId'] as int?,
      recordingId: json['recordingId'] as int?,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
      square: json['square'] as String?,
      path: json['path'] as String?,
      sent: (json['sent'] as int) == 1,
    );
  }

  factory RecordingPart.fromBEJson(Map<String, Object?> json, int recordingId){
    return RecordingPart(
      BEId: json['id'] as int?,
      recordingId: recordingId,
      startTime: json['start'] as String,
      endTime: json['end'] as String,
      gpsLatitudeStart: (json['gpsLatitudeStart'] as num).toDouble(),
      gpsLatitudeEnd: (json['gpsLatitudeEnd'] as num).toDouble(),
      gpsLongitudeStart: (json['gpsLongitudeStart'] as num).toDouble(),
      gpsLongitudeEnd: (json['gpsLongitudeEnd'] as num).toDouble(),
      square: json['square'] as String?,
      sent: true
    );
  }

  Map<String, Object?> toBEJson(){
    return {
      'id': BEId,
      'recordingId': recordingId,
      'start': startTime,
      'end': endTime,
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'square': square,
    };
  }

  Map<String, Object?> toJson(){
    return {
      'id': id,
      'BEId': BEId,
      'recordingId': recordingId,
      'startTime': startTime,
      'endTime': endTime,
      'gpsLatitudeStart': gpsLatitudeStart,
      'gpsLatitudeEnd': gpsLatitudeEnd,
      'gpsLongitudeStart': gpsLongitudeStart,
      'gpsLongitudeEnd': gpsLongitudeEnd,
      'square': square,
      'path': path,
      'sent': sent ? 1 : 0,
    };
  }
}

class DatabaseNew{
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

  static Future<void> insertRecording(Recording recording) async {
    final db = await database;
    await db.insert("recordings", recording.toJson());
    recordings.add(recording);
  }

  static Future<void> insertRecordingPart(RecordingPart recordingPart) async {
    final db = await database;
    await db.insert("recordingParts", recordingPart.toJson());
    recordingParts.add(recordingPart);
  }

  static Future<void> onFetchFinished() async{
    List<Recording> oldRecordings = await getRecordings();

    List<Recording> sentRecordings = oldRecordings.where((recording) => recording.sent).toList();

    List<Recording> newRecordings = fetchedRecordings!.where((recording) => !sentRecordings.contains(recording)).toList();

    for (Recording recording in newRecordings){
      await insertRecording(recording);
    }

    List<RecordingPart> newRecordingParts = List<RecordingPart>.empty(growable: true);
    newRecordings.forEach((recording){
      newRecordingParts.addAll(fetchedRecordingParts!.where((part) => part.recordingId == recording.BEId));
    });

    for (RecordingPart recordingPart in newRecordingParts){
      await insertRecordingPart(recordingPart);
    }

    //TODO: Implement the same for recordingParts
    //TODO: Implement the same for images

    //TODO: Implement update
  }

  static Future<void> syncRecordings() async{
    fetchRecordingsFromBE().then((_) => onFetchFinished(), onError: (error) {
      Logger().e(error);
      throw error;
    });
  }

  static Future<List<Recording>> getRecordings() async{
    final db = await database;
    final List<Map<String, dynamic>> recordings = await db.query("recordings");
    return List.generate(recordings.length, (i) {
      return Recording.fromJson(recordings[i]);
    });
  }

  static Future<List<RecordingPart>> getRecordingParts() async{
    final db = await database;
    final List<Map<String, dynamic>> recordingParts = await db.query("recordingParts");
    return List.generate(recordingParts.length, (i) {
      return RecordingPart.fromJson(recordingParts[i]);
    });
  }

  static Future<void> deleteRecording(int id) async {
    final db = await database;
    List<RecordingPart> recordingPartsCopy = List<RecordingPart>.from(recordingParts);
    for (RecordingPart recording in recordingPartsCopy){
      if (recording.recordingId == id) {
        recordingParts.remove(recording);
        await db.delete("recordingParts", where: "recordingId = ?", whereArgs: [id]);
      }
    }
    await db.delete("recordings", where: "id = ?", whereArgs: [id]);
  }

  static Future<void> sendRecording(Recording recording, List<RecordingPart> recordingParts) async {
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to send recording to backend', 401);
    }
    final http.Response response = await http.post(
      Uri.https('api.strnadi.cz', '/recordings/upload'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(recording.toBEJson()));
    if (response.statusCode == 200) {
      recording.BEId = jsonDecode(response.body);
      final db = await database;
      await db.update('recordings', recording.toJson(), where: 'id = ?', whereArgs: [recording.id]);
      for (RecordingPart part in recordingParts) {
        part.recordingId = recording.BEId;
        await sendRecordingPart(part);
      }
      recording.sent = true;
      updateRecordingInDB(recording);
    } else {
      throw UploadException('Failed to send recording to backend', response.statusCode);
    }
  }

  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    Map<String, Object?> json = recordingPart.toBEJson();
    if (recordingPart.path == null){
      throw UploadException('Recording part path is null', 410);
    }
    Uint8List data = File(recordingPart.path!).readAsBytesSync();
    String dataBase64 = base64Encode(data);
    json.addEntries([MapEntry('data', dataBase64)]);
    if (jwt == null) {
      throw UploadException('Failed to send recording part to backend', 401);
    }
    final http.Response response = await http.post(
        Uri.https('api.strnadi.cz', '/recordingParts/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode(json)
    );
    if(response.statusCode == 200){
      logger.i('Recording part id: ${recordingPart.id} uploaded');
      recordingPart.sent = true;
      updateRecordingPartInDB(recordingPart);
    }
    else{
      throw UploadException('Failed to upload part id: ${recordingPart.id}', response.statusCode);
    }
  }

  static Future<void> updateRecordingInDB(Recording recording) async {
    final db = await database;
    await db.update('recordings', recording.toJson(), where: 'id = ?', whereArgs: [recording.id]);
  }

  static Future<void> updateRecordingPartInDB(RecordingPart recordingPart) async {
    final db = await database;
    await db.update('recordingParts', recordingPart.toJson(), where: 'id = ?', whereArgs: [recordingPart.id]);
  }

  static Future<void> fetchRecordingsFromBE() async {
    fetching = true;
    // Fetch recordings from backend
    Uri url = Uri.https('api.strnadi.cz', '/recordings');
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }
    String? mail = JwtDecoder.decode(jwt)['email'];

    final http.Response response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      }
    );

    var body = json.decode(response.body);


    if (response.statusCode == 200){
      List<Recording> recordings = List<Recording>.generate(body.length, (recordingIndex) {
        return Recording.fromBEJson(body[recordingIndex], mail ?? '');
      });

      List<RecordingPart> parts = List<RecordingPart>.empty(growable: true);
      for (int recordingIndex = 0; recordingIndex < body.length; recordingIndex++){
        for(int partIndex = 0; partIndex < body[recordingIndex]['parts'].length; partIndex++){
          parts.add(RecordingPart.fromBEJson(body[recordingIndex]['parts']![partIndex], body[recordingIndex]['id']));
        }
      }
      fetchedRecordings = recordings;
      fetchedRecordingParts = parts;

      fetching = false;
      return;
    }
    else {
      fetching = false;
      throw FetchException('Failed to fetch recordings from backend', response.statusCode);
    }
  }

  static Future<Database> initDb() async{
    return openDatabase('sound.db', version: 1,
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
        note TEXT,
        path TEXT,
        sent INTEGER
      )
      ''');
          await db.execute('''
      CREATE TABLE recordingParts(
        id INTEGER PRIMARY KEY,
        recordingId INTEGER,
        startTime TEXT,
        endTime TEXT,
        gpsLatitudeStart REAL,
        gpsLatitudeEnd REAL,
        gpsLongitudeStart REAL,
        gpsLongitudeEnd REAL,
        square TEXT,
        path TEXT,
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
        }, onOpen: (Database db) async {
          recordings = await getRecordings();
          recordingParts = await getRecordingParts();
          loadedRecordings = true;
        });
  }

  static Future<List<RecordingPart>> trimAudio(
      String audioPath,
      List<int> stopTimesInMilliseconds,
      List<RecordingPart> recordingParts,
      ) async {
    Directory tempDir = await getApplicationDocumentsDirectory();

    // Convert stop times from milliseconds to Duration and sort them.
    List<Duration> stopTimes =
    stopTimesInMilliseconds.map((t) => Duration(milliseconds: t)).toList();
    stopTimes.sort((a, b) => a.inMilliseconds.compareTo(b.inMilliseconds));

    Duration start = Duration.zero;
    List<RecordingPart> trimmedParts = [];

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
      RecordingPart part;
      if (i < recordingParts.length) {
        part = recordingParts[i];
      } else {
        part = RecordingPart(
          recordingId: 0,
          startTime: "",
          endTime: "",
          gpsLatitudeStart: 0.0,
          gpsLatitudeEnd: 0.0,
          gpsLongitudeStart: 0.0,
          gpsLongitudeEnd: 0.0,
          path: "",
        );
      }
      part.path = savedPath;
      trimmedParts.add(part);

      start = end;
    }

    return trimmedParts;
  }
}
