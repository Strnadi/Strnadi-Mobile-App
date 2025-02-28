import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../PostRecordingForm/RecordingForm.dart';
class LocalDb {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'recordings.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Read the schema from the .sql file
        String schema = await rootBundle.loadString('assets/databaseScheme.sql');

        // Execute multiple SQL commands
        List<String> queries = schema.split(';');
        for (var query in queries) {
          if (query.trim().isNotEmpty) {
            await db.execute(query);
          }
        }
      },
    );
  }

  static Future<void> insertRecording(Recording recording, String name, int status, String filepath, double latitude, double longitude) async {
    final Database db = await database;

    var map = Map<String, Object?>.new();

    map = {
      'title': name,
      'created_at': recording.createdAt.toIso8601String(),
      'EstimatedBirdsCount': recording.estimatedBirdsCount,
      'device': recording.device,
      'note': recording.note,
      'filepath': filepath,
      'latitude': latitude,
      'longitude': longitude,
      'status': status,
    };

    logger.d('Inserting recording: $map');

    await db.insert(
      'recordings',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
