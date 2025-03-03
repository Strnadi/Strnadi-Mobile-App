/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'dart:io';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import '../PostRecordingForm/RecordingForm.dart';

void initDb() async {
  final db = await openDatabase('sound.db', version: 1,
      onCreate: (Database db, int version) async {
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

void insertSound(String name, String path, double latitude, double longitude,
    int duration, String createdAt) async {
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
  await db.update('sounds', {'sent': 1}, where: 'id = ?', whereArgs: [id]);
}

void checkIfDbExists() async {
  final db = await openDatabase('sound.db');
  final tables =
      await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']);
  if (tables.isEmpty) {
    initDb();
  }
}

class DatabaseHelper {
  static Database? _database;

  /// Trims the audio into segments using FFmpeg.
  /// The stop times are expected to be in milliseconds.
  /// The output segments are saved as .wav files using PCM 16-bit little-endian encoding.
  static Future<List<RecordingParts>> trimAudio(
    String audioPath,
    List<int> stopTimesInMilliseconds,
    List<RecordingParts> recordingParts,
  ) async {
    Directory tempDir = await getApplicationDocumentsDirectory();

    // Convert stop times from milliseconds to Duration and sort them.
    List<Duration> stopTimes =
        stopTimesInMilliseconds.map((t) => Duration(milliseconds: t)).toList();
    stopTimes.sort((a, b) => a.inMilliseconds.compareTo(b.inMilliseconds));

    Duration start = Duration.zero;
    List<RecordingParts> trimmedParts = [];

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
      RecordingParts part;
      if (i < recordingParts.length) {
        part = recordingParts[i];
      } else {
        part = RecordingParts(path: "", longitude: 0.0, latitude: 0.0);
      }
      part.path = savedPath;
      trimmedParts.add(part);

      start = end;
    }

    return trimmedParts;
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
            note TEXT,
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
