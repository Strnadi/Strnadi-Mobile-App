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
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

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
        String schema =
            await rootBundle.loadString('assets/databaseScheme.sql');

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

  static Future<void> insertRecording(Recording recording, String name,
      int status, String filepath, double latitude, double longitude) async {
    final Database db = await database;


    var id = await db.rawQuery("SELECT MAX(id) as id FROM recordings");
    var lastId = id[0]["id"];

    lastId ??= 0;

    var RecId = lastId as int;

    var map = <String, Object?>{
      'title': name == "" ? 'Záznam cislo ${RecId+1}' : name,
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

  static Future<List<RecordItem>> GetRecordings() async {
    List<RecordItem> records = [];

    var db = await database;


    db.rawQuery("SELECT * FROM recordings").then((value) {
      for (var record in value) {
        var dateTime = DateTime.parse(record["created_at"].toString());
        DateTime onlyDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
        String formattedDate = DateFormat("yyyy-MM-dd").format(onlyDate);


        records.add(RecordItem(
          title: record['title'].toString(),
          date: formattedDate,
          status: record['upload_status'] == 0 ? 'Čeká na Wi-Fi připojení' : 'V databázi',
        ));
      }
    });

    return records;
  }

  static Future<void> UpdateStatus(String filepath) async {
    final Database db = await database;

    await db.rawUpdate(
      'UPDATE recordings SET upload_status = 1 WHERE filepath = ?',
      [filepath],
    );
  }
}
