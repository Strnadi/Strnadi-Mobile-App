import 'dart:io';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import '../PostRecordingForm/RecordingForm.dart';

void initDb() async {
  final db = await openDatabase('sound.db', version: 1, onCreate: (Database db, int version) async {
    await db.execute('''
      CREATE TABLE sounds(
        id INTEGER PRIMARY KEY,
        name TEXT,
        path TEXT,
        latitude REAL,
        longitude REAL,
        duration INTEGER,
        created_at DATETIME,
        sent INTEGER DEFAULT 0
      )
    ''');
  });
}

void insertSound(String name, String path, double latitude, double longitude, int duration, String createdAt) async {
  final db = await openDatabase('sound.db');
  await db.insert('sounds', {
    'name': name,
    'path': path,
    'latitude': latitude,
    'longitude': longitude,
    'duration': duration,
    'created_at': createdAt

  });
}

void markAsSent(int id) async {
  final db = await openDatabase('sound.db');
  await db.update('sounds', {
    'sent': 1
  }, where: 'id = ?', whereArgs: [id]);
}

void checkIfDbExists() async {
  final db = await openDatabase('sound.db');
  final tables = await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
  if (tables.isEmpty) {
    initDb();
  }
}

class DatabaseHelper {
  static Database? _database;

  static Future<List<RecordingParts>> trimAudio(
      String audioPath,
      List<int> stopTimesInSeconds,
      List<RecordingParts> recordingParts, // Each trimmed part has a location
      ) async {

    Directory tempDir = await getApplicationDocumentsDirectory();

    List<Duration> stopTimes = stopTimesInSeconds.map((t) => Duration(seconds: t)).toList();

    stopTimes.sort((a, b) => a.inMilliseconds.compareTo(b.inMilliseconds));

    Duration start = Duration.zero;
    for (int i = 0; i < stopTimes.length; i++) {
      Duration end = stopTimes[i];

      String outputPath = '${tempDir.path}/trimmed_part_$i.mp3';
      String command = '-i $audioPath -ss ${start.inSeconds} -to ${end.inSeconds} -c copy $outputPath';
      await FFmpegKit.execute(command);

      String? savedPath = File(outputPath).existsSync() ? outputPath : null;

      var part = recordingParts[i];
      part.path = savedPath;

      recordingParts.add(part);
      start = end;
    }

    return recordingParts;
  }


  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDB();
    return _database!;
  }

  static Future<Database> initDB() async {
    return openDatabase(
      'sound.db',
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            createdAt TEXT,
            estimatedBirdsCount INTEGER,
            device TEXT,
            byApp INTEGER,
            note TEXT
            path TEXT
          )
        ''');
      },
      version: 1,
    );
  }



  static Future<void> insertRecording(Recording recording) async {
    final db = await database;
    await db.insert("recordings", recording.toJson());
  }
}
