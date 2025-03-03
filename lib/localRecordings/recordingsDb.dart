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

    var map = <String, Object?>{
      'title': name,
      'created_at': recording.createdAt.toIso8601String(),
      'estimated_birds_count': recording.estimatedBirdsCount,
      'by_app': 1,
      'device': recording.device,
      'note': recording.note,
      'filepath': filepath,
      'latitude': latitude,
      'longitude': longitude,
      'upload_status': status,
    };

    logger.d('Inserting recording: $map');

    await db.insert(
      'recordings',
      map,
    );
  }
}
