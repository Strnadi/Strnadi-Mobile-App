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
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/api/controllers/recording_parts_controller.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/Models/detectedDialect.dart';
import 'package:strnadi/database/Models/filteredRecordingPart.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/fileSize.dart';
import 'package:strnadi/database/src/database_logger.dart' as db_log;
import 'package:strnadi/database/src/upload_progress_bus.dart';
import 'package:strnadi/dialects/ModelHandler.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:strnadi/notificationPage/notifications.dart';
import 'package:strnadi/recording/waw.dart';
import 'package:strnadi/user/settingsManager.dart';
import 'package:strnadi/utils/log_redactor.dart';
import 'package:workmanager/workmanager.dart';

part 'database_repository_api.dart';
part 'database_repository_download.dart';
part 'database_migrations.dart';

final logger = db_log.logger;

/// Database helper class
class DatabaseNew {
  static Database? _database;
  static List<FilteredRecordingPart>? fetchedFilteredRecordingParts;
  static List<DetectedDialect>? fetchedDetectedDialects;

  static List<Recording>? fetchedRecordings;
  static List<RecordingPart>? fetchedRecordingParts;
  static final ValueNotifier<int> unreadNotificationCount =
      ValueNotifier<int>(0);

  static bool fetching = false;
  static bool _durationBackfillNeeded = false;

  // Guard sets to ensure every recording/part is sent only once per app lifetime
  static final Set<int> _inflightPartIds = <int>{};
  static final Set<int> _inflightRecordingIds = <int>{};

  /// Enforces the user-defined maximum number of local recordings by deleting the oldest ones.
  static Future<void> enforceMaxRecordings() async {
    logger.i('Enforcing maximum number of local recordings.');
    final int max = await SettingsService().getLocalRecordingsMax();
    logger.i('Maximum allowed recordings: $max');
    if (max <= 0) return; // no limit or invalid

    // Need user scoping (mail + env) to avoid touching other users/environments
    final Database db = await database;
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null || jwt.isEmpty) return;
    final String email = JwtDecoder.decode(jwt)['sub'];
    final String env = Config.hostEnvironment.name.toString();

    // Count only eligible rows (all parts sent, none sending, downloaded)
    final List<Map<String, Object?>> cntRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ('
      '  SELECT r.id '
      '  FROM recordings r '
      '  LEFT JOIN recordingParts p ON p.recordingId = r.id '
      '  WHERE r.mail = ? AND r.env = ? AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      '  GROUP BY r.id '
      '  HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0'
      ') t',
      [email, env],
    );

    int totalEligible;
    final dynamic cVal = cntRows.first['c'];
    if (cVal is int) {
      totalEligible = cVal;
    } else if (cVal is num) {
      totalEligible = cVal.toInt();
    } else if (cVal is String) {
      totalEligible = int.tryParse(cVal) ?? 0;
    } else {
      totalEligible = 0;
    }

    if (totalEligible <= max) return; // under limit
    final int toDelete = totalEligible - max;

    // Fetch the oldest eligible recording ids (and paths) using SQLite ordering/limit with all parts sent, none sending, downloaded
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT r.id, r.path '
      'FROM recordings r '
      'LEFT JOIN recordingParts p ON p.recordingId = r.id '
      'WHERE r.mail = ? AND r.env = ? AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      'GROUP BY r.id '
      'HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0 '
      'ORDER BY datetime(r.createdAt) ASC LIMIT ?',
      [email, env, toDelete],
    );

    // Delete the chosen ids using our existing helper (ensures parts + files are cleaned up)
    for (final Map<String, Object?> row in rows) {
      final dynamic idVal = row['id'];
      final int id = idVal is int
          ? idVal
          : (idVal is num ? idVal.toInt() : int.parse(idVal.toString()));
      try {
        await deleteRecordingFromCache(id);
        logger.i('Auto-pruned recording id $id due to max limit=$max');
      } catch (e, st) {
        logger.e('Failed to auto-prune recording id $id',
            error: e, stackTrace: st);
        Sentry.captureException(e, stackTrace: st);
      }
    }
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initDb();
    return _database!;
  }

  static Future<int> insertRecording(Recording recording) async {
    try {
      final db = await database;
      if (recording.BEId != null) {
        List<Map<String, dynamic>> existing = await db.query("recordings",
            where: "BEId = ?", whereArgs: [recording.BEId]);
        if (existing.isNotEmpty) {
          final Recording current = Recording.fromJson(existing.first);
          int id = existing.first["id"];
          recording.id = id;
          if ((recording.path == null || recording.path!.isEmpty) &&
              current.path != null &&
              current.path!.isNotEmpty) {
            recording.path = current.path;
          }
          if (!recording.downloaded && current.downloaded) {
            recording.downloaded = true;
          }
          if (recording.totalSeconds == null ||
              recording.totalSeconds == 0 ||
              recording.totalSeconds == -1) {
            recording.totalSeconds = current.totalSeconds;
          }
          if ((recording.mail == null || recording.mail!.isEmpty) &&
              current.mail != null &&
              current.mail!.isNotEmpty) {
            recording.mail = current.mail;
          }
          await updateRecording(recording);
          logger.i(
              'Recording with BEId ${recording.BEId} updated (id: $id), path: ${recording.path}');
          return id;
        }
      }
      String? token = await FlutterSecureStorage().read(key: 'token');
      final String? userIdS = await FlutterSecureStorage().read(key: 'userId');
      final int? currentUserId = int.tryParse((userIdS ?? '').trim());

      logger.i('Token available: ${token != null && token.isNotEmpty}');

      if (token == null || token == '') {
        recording.mail ??= '';
      } else {
        final String currentEmail = JwtDecoder.decode(token)['sub'];
        final bool belongsToDifferentUser = recording.sent &&
            recording.userId != null &&
            currentUserId != null &&
            recording.userId != currentUserId;
        if (belongsToDifferentUser) {
          // Keep foreign recordings out of "My recordings" while still cached locally.
          recording.mail = '';
        } else {
          recording.mail = currentEmail;
        }
      }
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      if (token != null && token != '') {
        await enforceMaxRecordings();
      }
      logger.i('Recording ${recording.id} inserted, path: ${recording.path}');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  // static method to select all
  static Future<List<Map<String, dynamic>>> getAllRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> recs =
        await db.rawQuery("SELECT * FROM recordings");
    return recs;
  }

  // Backfill owner mail only for local-unsent rows with empty mail.
  // Sent rows may belong to other users and must stay out of "My recordings".
  static Future<void> updateRecordingsMail() async {
    final db = await database;
    final String? token = await FlutterSecureStorage().read(key: 'token');
    if (token == null || token == '') return;
    final String email = JwtDecoder.decode(token)['sub'];
    await db.rawUpdate(
      'UPDATE recordings SET mail = ? '
      'WHERE (mail IS NULL OR TRIM(mail) = \'\') AND COALESCE(sent, 0) = 0',
      [email],
    );
  }

  static Future<int> insertRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      if (recordingPart.id != null) {
        List<Map<String, dynamic>> existing = await db.query("recordingParts",
            where: "id = ?", whereArgs: [recordingPart.id]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          recordingPart.id = id;
          await updateRecordingPart(recordingPart);
          logger.i(
              'Recording part with backendRecordingId ${recordingPart.backendRecordingId} updated (id: $id).');
          return id;
        }
      }
      if (recordingPart.BEId != null) {
        List<Map<String, dynamic>> existingByBeId = await db.query(
            "recordingParts",
            where: "BEId = ?",
            whereArgs: [recordingPart.BEId]);
        if (existingByBeId.isNotEmpty) {
          final RecordingPart existing =
              RecordingPart.fromJson(existingByBeId.first);
          recordingPart.id = existing.id;
          recordingPart.recordingId ??= existing.recordingId;
          recordingPart.backendRecordingId ??= existing.backendRecordingId;
          recordingPart.path ??= existing.path;
          recordingPart.length ??= existing.length;
          recordingPart.sent = recordingPart.sent || existing.sent;
          recordingPart.sending = recordingPart.sending || existing.sending;
          await updateRecordingPart(recordingPart);
          logger.i(
              'Recording part with BEId ${recordingPart.BEId} updated (id: ${recordingPart.id}).');
          return recordingPart.id ?? -1;
        }
      }
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      logger.i('Recording part ${recordingPart.id} inserted.');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return -1;
    }
  }

  static Future<void> onFetchFinished() async {
    List<Recording> oldRecordings = await getRecordings();
    final Map<int, int> beIdToLocalId = {
      for (final rec in oldRecordings)
        if (rec.BEId != null && rec.id != null) rec.BEId!: rec.id!
    };
    List<Recording> sentRecordings =
        oldRecordings.where((recording) => recording.sent).toList();

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
        logger.i(
            'Recording id ${recording.id} deleted locally (missing on backend).');
      }
    }

    List<Recording> newRecordings = fetchedRecordings!
        .where(
            (recording) => !sentRecordings.any((r) => r.BEId == recording.BEId))
        .toList();

    for (Recording recording in newRecordings) {
      recording.sent = true;
      recording.downloaded = false;
      logger.i(
          'Inserting recording with BEId: ${recording.BEId} and name ${recording.name}');
      await insertRecording(recording);
      if (recording.BEId != null && recording.id != null) {
        beIdToLocalId[recording.BEId!] = recording.id!;
      }
    }

    List<RecordingPart> oldRecordingParts = await getRecordingParts();
    List<RecordingPart> newRecordingParts = fetchedRecordingParts!
        .where(
            (newPart) => !oldRecordingParts.any((p) => p.BEId == newPart.BEId))
        .toList();

    for (RecordingPart recordingPart in newRecordingParts) {
      recordingPart.sent = true;
      if (recordingPart.backendRecordingId != null) {
        final localId = beIdToLocalId[recordingPart.backendRecordingId!];
        if (localId != null) {
          recordingPart.recordingId = localId;
        }
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
      final Set<int?> beIds =
          fetchedRecordings?.map((r) => r.BEId).toSet() ?? {};
      for (var local in localRecordings) {
        if (local.sent && !beIds.contains(local.BEId)) {
          await deleteRecordingFromCache(local.id!);
          logger.i(
              'Recording id ${local.id} deleted locally (missing on backend, during sync).');
        }
      }
      await onFetchFinished();
      if (fetchedRecordings != null && fetchedRecordings!.isNotEmpty) {
        await fetchFilteredPartsForRecordingsFromBE(fetchedRecordings!);
        await persistFetchedFilteredParts();
      }
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
    final List<Map<String, dynamic>> recs = await db.query("recordings",
        where: "mail = ? AND env = ?",
        whereArgs: [email, Config.hostEnvironment.name.toString()]);
    return List.generate(recs.length, (i) => Recording.fromJson(recs[i]));
  }

  /// Returns downloaded recordings present in local cache across environments.
  /// Used by settings cache manager so users can clean local storage reliably,
  /// including items downloaded in a different environment/account.
  static Future<List<Recording>> getDownloadedRecordingsForCurrentUser() async {
    final db = await database;
    final List<String> where = <String>[
      'downloaded = 1',
      "("
          "(path IS NOT NULL AND path <> '') OR "
          "EXISTS ("
          "  SELECT 1 FROM recordingParts p "
          "  WHERE p.recordingId = recordings.id "
          "    AND p.path IS NOT NULL "
          "    AND p.path <> ''"
          ")"
          ")",
    ];

    final List<Map<String, dynamic>> recs = await db.query(
      'recordings',
      where: where.join(' AND '),
      orderBy: 'datetime(createdAt) DESC',
    );
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
        recording = await getRecordingFromDbById(id);
      } catch (_) {
        recording = null;
      }

      /* ------------------------------------------------------------------
       * 1) Delete on backend (only if already sent and BEId is known)
       * ------------------------------------------------------------------ */
      if (recording != null && recording.sent && recording.BEId != null) {
        final String? jwt = await FlutterSecureStorage().read(key: 'token');
        if (jwt != null) {
          final resp = await _recordingsApi.deleteRecording(recording.BEId!);
          if (resp.statusCode == 200 || resp.statusCode == 204) {
            logger.i('Recording BEId ${recording.BEId} deleted on backend.');
          } else {
            logger.w(
              'Backend deletion failed for BEId ${recording.BEId}. '
              'Status: ${resp.statusCode} - Body: ${resp.data}',
            );
          }
        } else {
          logger.w(
              'JWT not available – skipping backend delete for BEId ${recording?.BEId}');
        }
      }

      /* ------------------------------------------------------------------
       * 2) Delete locally (DB rows, cached files, in‑memory lists)
       * ------------------------------------------------------------------ */
      final Database db = await database;

      // Remove audio part files + rows
      final List<Map<String, dynamic>> partRows = await db.query(
        'recordingParts',
        where: 'recordingId = ?',
        whereArgs: [id],
      );
      for (final row in partRows) {
        final part = RecordingPart.fromJson(row);
        if (part.path != null) {
          try {
            await File(part.path!).delete();
          } catch (_) {
            /* ignore file-system errors */
          }
        }
      }
      await db
          .delete('recordingParts', where: 'recordingId = ?', whereArgs: [id]);

      // Remove main audio file if any
      Recording? localRecording = recording;
      if (localRecording == null) {
        final List<Map<String, dynamic>> recRows = await db.query(
          'recordings',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (recRows.isNotEmpty) {
          localRecording = Recording.fromJson(recRows.first);
        }
      }
      if (localRecording?.path != null) {
        try {
          await File(localRecording!.path!).delete();
        } catch (_) {
          /* ignore file-system errors */
        }
      }

      await db.delete('recordings', where: 'id = ?', whereArgs: [id]);

      logger.i(
          'Recording id $id deleted locally (and on backend if applicable).');
    } catch (e, stackTrace) {
      logger.e('Failed to delete recording id $id',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> sendRecordingBackground(int recordingId) async {
    await Workmanager().registerOneOffTask(
      (Platform.isIOS)
          ? "com.delta.strnadi.sendRecording"
          : "sendRecording_${DateTime.now().microsecondsSinceEpoch}",
      (Platform.isIOS)
          ? "sendRecording_${DateTime.now().microsecondsSinceEpoch}"
          : "sendRecording",
      inputData: {"recordingId": recordingId},
    );
  }

  static Future<void> sendRecording(
      Recording recording, List<RecordingPart> recordingParts) async {
    await _sendRecording(recording, recordingParts);
  }

  static Future<void> sendRecordingNew(
      Recording recording, List<RecordingPart> recordingParts) async {
    await _sendRecordingNew(recording, recordingParts);
  }

  static Future<bool> handleDeletedPath(RecordingPart recordingPart) async {
    return _handleDeletedPath(recordingPart);
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
    final List<Map<String, dynamic>> partRows = await db.query(
      'recordingParts',
      where: 'recordingId = ?',
      whereArgs: [id],
    );
    for (final row in partRows) {
      final part = RecordingPart.fromJson(row);
      if (part.path != null) {
        try {
          await File(part.path!).delete();
        } catch (_) {
          // ignore file-system errors
        }
      }
    }
    await db.delete(
      'recordingParts',
      where: 'recordingId = ?',
      whereArgs: [id],
    );
    final List<Map<String, dynamic>> recRows = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (recRows.isNotEmpty) {
      final rec = Recording.fromJson(recRows.first);
      if (rec.path != null) {
        try {
          await File(rec.path!).delete();
        } catch (_) {
          // ignore file-system errors
        }
      }
    }
    await db.delete(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
    );
    logger.i('Recording id $id deleted from cache.');
  }

  static Future<void> sendRecordingPart(RecordingPart recordingPart) async {
    await _sendRecordingPart(recordingPart);
  }

  static Future<void> sendRecordingPartNew(RecordingPart recordingPart,
      {UploadProgress? onProgress}) async {
    await _sendRecordingPartNew(recordingPart, onProgress: onProgress);
  }

  static Future<void> updateRecording(Recording recording) async {
    try {
      final db = await database;
      await db.update('recordings', recording.toJson(),
          where: 'id = ?', whereArgs: [recording.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<void> updateRecordingPart(RecordingPart recordingPart) async {
    try {
      final db = await database;
      await db.update('recordingParts', recordingPart.toJson(),
          where: 'id = ?', whereArgs: [recordingPart.id]);
    } catch (e, stackTrace) {
      logger.e('Failed to update recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Update an existing recording on the backend
  /// Uses PATCH /recordings/[BEId]/edit
  static Future<void> updateRecordingBE(Recording recording) async {
    await _updateRecordingBE(recording);
  }

  static Future<void> fetchRecordingsFromBE() async {
    await _fetchRecordingsFromBE();
  }

  static Future<void> fetchFilteredPartsForRecordingsFromBE(
      List<Recording> recs,
      {bool verified = false}) async {
    await _fetchFilteredPartsForRecordingsFromBE(recs, verified: verified);
  }

  static Future<void> persistFetchedFilteredParts() async {
    if (fetchedFilteredRecordingParts == null ||
        fetchedFilteredRecordingParts!.isEmpty) return;

    // Build recording BEId -> local id map
    final localRecs = await getRecordings();
    final Map<int, int> recBeToLocal = {
      for (final r in localRecs)
        if (r.BEId != null && r.id != null) r.BEId!: r.id!
    };

    // Insert/update filtered parts first
    final Map<int, int> frpBeToLocal = <int, int>{};
    for (final frp in fetchedFilteredRecordingParts!) {
      if (frp.recordingBEID != null) {
        frp.recordingLocalId = recBeToLocal[frp.recordingBEID!];
      }
      if (frp.parentBEID != null && frpBeToLocal.containsKey(frp.parentBEID)) {
        frp.parentLocalId = frpBeToLocal[frp.parentBEID!];
      }
      final id = await insertFilteredRecordingPart(frp);
      if (frp.BEId != null && id > 0) {
        frpBeToLocal[frp.BEId!] = id;
      }
    }

    // Insert/update detected dialects, linked to local FRP ids
    if (fetchedDetectedDialects != null &&
        fetchedDetectedDialects!.isNotEmpty) {
      for (final dd in fetchedDetectedDialects!) {
        if (dd.filteredPartBEID != null &&
            frpBeToLocal.containsKey(dd.filteredPartBEID)) {
          dd.filteredPartLocalId = frpBeToLocal[dd.filteredPartBEID!];
        }
        await insertDetectedDialect(dd);
      }
    }
  }

  static Future<List<RecordingPart>> fetchPartsFromDbById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db
        .rawQuery("SELECT * FROM recordingParts WHERE RecordingId = $id");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<List<RecordingPart>> getPartsByRecordingId(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db
        .query("recordingParts", where: "recordingId = ?", whereArgs: [id]);
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<RecordingPart?> getRecordingPartByBEID(int id) async {
    return _getRecordingPartByBEID(id);
  }

  static Future<int?> downloadRecording(
    int recordingBeId, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    return _downloadRecording(
      recordingBeId,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Future<void> concatRecordingParts(int recordingId) async {
    List<RecordingPart> parts = await getPartsByRecordingId(recordingId);
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

    try {
      await concatWavFiles(paths, outputPath);
    } catch (e, stackTrace) {
      logger.e('Failed to concatenate recording parts for id: $recordingId',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      return;
    }

    logger.i('Supposed file path: $outputPath');

    final Recording? recording =
        await getRecordingFromDbByIdNoMail(recordingId);
    if (recording == null) {
      logger.w('Recording $recordingId not found when concatenating parts.');
      return;
    }
    recording
      ..path = outputPath
      ..downloaded = true;
    await updateRecording(recording);

    logger.i(
        'Concatenated recording parts for id: $recordingId. File saved to: $outputPath');
  }

  static Future<Database> initDb() async {
    return openDatabase('soundNew.db', version: 12,
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
        sending INTEGER,
        totalSeconds REAL,
        partCount INTEGER,
        env STRING DEFAULT \'prod\'
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
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        BEID INTEGER UNIQUE,
        recordingId INTEGER,
        recordingBEID INTEGER,
        userGuessDialect TEXT,
        adminDialect TEXT,
        startDate TEXT,
        endDate TEXT
      )
      ''');
      await db.execute('''
    CREATE TABLE FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
    ''');

      await db.execute('''
    CREATE TABLE DetectedDialects(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      predictedDialectId INTEGER,
      predictedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
    ''');
    }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
      if (oldVersion <= 1) {
        await _ensureColumn(
            db, 'recordingParts', 'backendRecordingId', 'INTEGER');
        await db.setVersion(2);
      }
      if (oldVersion <= 2) {
        logger.w(
            'Old version detected (<=2). Ensuring schema without dropping user data...');
        await _ensureBaseTables(db);
        await db.setVersion(newVersion);
      }
      // Upgrade from v3 → v4: add the 'sending' column to recordingParts
      if (oldVersion <= 3) {
        await _ensureColumn(
            db, 'recordingParts', 'sending', 'INTEGER DEFAULT 0');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 4) {
        await _renameColumnIfExists(db, 'Dialects', 'dialect', 'dialectCode');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 5) {
        try {
          await _ensureColumn(db, 'recordingParts', 'length', 'INTEGER');
        } catch (e, stackTrace) {
          logger.w('Failed to add length column to recordingParts: $e',
              error: e, stackTrace: stackTrace);
          Sentry.captureException(e, stackTrace: stackTrace);
        }
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 6) {
        await _migrateLegacyDialectsTable(db);
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 7) {
        await db.execute('''
    CREATE TABLE IF NOT EXISTS FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
  ''');
        await db.execute('''
    CREATE TABLE IF NOT EXISTS DetectedDialects(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
  ''');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 8) {
        await _ensureColumn(db, 'recordings', 'partCount', 'INTEGER');
        await db.execute('''UPDATE recordings AS r
            SET partCount = COALESCE((
            SELECT COUNT(*)
        FROM recordingParts AS p
        WHERE p.recordingId = r.id
          ), 0);''');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 9) {
        await _ensureColumn(db, 'recordings', 'env', 'STRING DEFAULT \'prod\'');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 10) {
        await _ensureColumn(db, 'recordings', 'totalSeconds', 'REAL');
        _durationBackfillNeeded = true;
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 11) {
        await _ensureColumn(
            db, 'DetectedDialects', 'predictedDialectId', 'INTEGER');
        await _ensureColumn(db, 'DetectedDialects', 'predictedDialect', 'TEXT');
        await db.setVersion(newVersion);
      }
    });
  }

  static Future<void> runPostMigrationBackfills() async {
    if (!_durationBackfillNeeded) return;
    try {
      await fetchAndUpdateDurationsFromBackend(DatabaseNew());
      await updateAllRecordingsDurations(DatabaseNew());
    } catch (e, stackTrace) {
      logger.w('Post-migration duration backfill failed',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    } finally {
      _durationBackfillNeeded = false;
    }
  }

  static Future<bool> hasInternetAccess() async {
    return _hasInternetAccess();
  }

  static Future<void> insertNotification(RemoteMessage message) async {
    final db = await database;
    await db.insert('Notifications', {
      'title': message.notification?.title,
      'type': int.parse(message.messageType!),
      'body': message.data.toString(),
      'receivedAt': message.sentTime,
    });
    await refreshUnreadNotificationCount();
  }

  // New helper method to insert a custom local notification.
  static Future<void> sendLocalNotification(
      String title, String message) async {
    final String fcmToken =
        ((await FlutterSecureStorage().read(key: 'fcmToken'))) ?? '';
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
  }

  static Future<int> getUnreadNotificationCount() async {
    final db = await database;
    final List<Map<String, Object?>> result = await db.rawQuery(
      'SELECT COUNT(*) AS unreadCount FROM Notifications WHERE read = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  static Future<void> refreshUnreadNotificationCount() async {
    unreadNotificationCount.value = await getUnreadNotificationCount();
  }

  static Future<void> markAllNotificationsAsRead() async {
    final db = await database;
    await db.update(
      'Notifications',
      {'read': 1},
      where: 'read = 0',
    );
    await refreshUnreadNotificationCount();
  }

  static Future<Recording?> getRecordingFromDbById(int recordingId) async {
    final db = await database;
    final String? email = JwtDecoder.decode(
        (await FlutterSecureStorage().read(key: 'token'))!)['sub'];
    final List<Map<String, dynamic>> results = await db.query("recordings",
        where: "id = ? AND mail = ? AND env = ?",
        whereArgs: [
          recordingId,
          email,
          Config.hostEnvironment.name.toString()
        ]);
    if (results.isNotEmpty) {
      return Recording.fromJson(results.first);
    }
    return null;
  }

  static Future<Recording?> getRecordingFromDbByIdNoMail(
      int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query("recordings",
        where: "id = ? AND env = ?",
        whereArgs: [recordingId, Config.hostEnvironment.name.toString()]);
    if (results.isNotEmpty) {
      return Recording.fromJson(results.first);
    }
    return null;
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
    // Only pick parts that are truly idle (not sent and not currently sending)
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where: 'sent = ? AND (sending IS NULL OR sending = 0)',
      whereArgs: [0],
    );

    await _resendUnsentPartRows(unsent);
  }

  /// Attempts to resend idle unsent parts for a single local recording.
  static Future<void> resendUnsentPartsForRecording(int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> unsent = await db.query(
      'recordingParts',
      where:
          'recordingId = ? AND sent = ? AND (sending IS NULL OR sending = 0)',
      whereArgs: [recordingId, 0],
    );

    await _resendUnsentPartRows(unsent);
  }

  static Future<void> _resendUnsentPartRows(
      List<Map<String, dynamic>> unsent) async {
    if (unsent.isEmpty) return;

    // Group parts by local recordingId to make sure we send the parent recording at most once
    final Map<int, List<Map<String, dynamic>>> byRecording =
        <int, List<Map<String, dynamic>>>{};
    for (final row in unsent) {
      final int recId = (row['recordingId'] as num).toInt();
      byRecording.putIfAbsent(recId, () => <Map<String, dynamic>>[]).add(row);
    }

    final List<Future<void>> tasks = <Future<void>>[];

    byRecording.forEach((int recId, List<Map<String, dynamic>> partRows) {
      tasks.add(() async {
        try {
          final Recording? recording = await getRecordingFromDbById(recId);

          // If we have no local recording AND the part has no backendRecordingId, we can't proceed.
          // Log and skip (keeps your original error handling intent).
          if (recording == null &&
              partRows.every((r) => r['backendRecordingId'] == null)) {
            logger.i(
                'resendUnsentParts: cannot find recording $recId and parts have no backendRecordingId; skipping group.');
            return;
          }

          // If the recording exists but hasn't been created on BE yet, send it ONCE with its unsent parts.
          if (recording != null && recording.BEId == null) {
            // Build the set of local parts for this recording that are not sent yet.
            final List<RecordingPart> toSend = partRows
                .map((m) => RecordingPart.fromJson(m))
                .where((p) => p.sent != true)
                .toList(growable: false);

            if (toSend.isNotEmpty) {
              // Respect single-flight guard for the recording
              if (recording.sending == true ||
                  (recording.id != null &&
                      _inflightRecordingIds.contains(recording.id))) {
                logger.i(
                    'resendUnsentParts: recording ${recording.id} already in-flight.');
              } else {
                await sendRecordingNew(recording, toSend);
              }
            }
          }

          // Now (whether BEId exists already or has just been created) try sending each idle part at most once.
          for (final m in partRows) {
            final part = RecordingPart.fromJson(m);
            if (part.sent == true) {
              continue;
            }
            if (part.sending == true ||
                (part.id != null && _inflightPartIds.contains(part.id))) {
              continue;
            }
            if (part.backendRecordingId == null && recording?.BEId != null) {
              part.backendRecordingId = recording!.BEId;
            }

            // Persist the sending flag immediately to avoid concurrent retries picking it up again.
            part.sending = true;
            await updateRecordingPart(part);
            await sendRecordingPartNew(part);
          }
        } catch (e, st) {
          logger.e('resendUnsentParts: failure in group for recordingId=$recId',
              error: e, stackTrace: st);
          Sentry.captureException(e, stackTrace: st);
        }
      }());
    });

    await Future.wait(tasks, eagerError: false);
  }

  // Dialects
  static Future<int> insertDialect(Dialect dialect) async {
    final db = await database;

    logger.i('dialect: ${dialect.toJson()}');
    int id = await db.insert("Dialects", dialect.toJson());
    logger.i('Dialect ${dialect.id} inserted.');
    return id;
  }

  static Future<void> updateDialect(Dialect dialect) async {
    final db = await database;
    await db.update("Dialects", dialect.toJson(),
        where: "id = ?", whereArgs: [dialect.id]);
    logger.i('Dialect ${dialect.id} updated.');
  }

  static Future<void> deleteDialect(int id) async {
    final db = await database;
    await db.delete("Dialects", where: "id = ?", whereArgs: [id]);
    logger.i('Dialect $id deleted.');
  }

  static Future<List<Dialect>> getDialectsByRecordingId(int recordingId) async {
    logger.i('Loading dialects for recording: $recordingId');
    final db = await database;
    final List<Map<String, dynamic>> results = await db
        .query("Dialects", where: "recordingId = ?", whereArgs: [recordingId]);
    if (results.isEmpty) {
      logger.i('No dialects found for recording: $recordingId');
      return [];
    }
    return List.generate(results.length, (i) => Dialect.fromJson(results[i]));
  }

  static Future<List<Dialect>> getDialectsByRecordingBEID(
      int recordingBEID) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query("Dialects",
        where: "recordingBEID = ?", whereArgs: [recordingBEID]);
    return List.generate(results.length, (i) => Dialect.fromJson(results[i]));
  }

  // === Filtered Recording Parts CRUD ===
  static Future<int> insertFilteredRecordingPart(
      FilteredRecordingPart frp) async {
    final db = await database;
    if (frp.BEId != null) {
      final existing = await db.query('FilteredRecordingParts',
          where: 'BEId = ?', whereArgs: [frp.BEId], limit: 1);
      if (existing.isNotEmpty) {
        frp.id = existing.first['id'] as int?;
        await db.update('FilteredRecordingParts', frp.toDbJson(),
            where: 'id = ?', whereArgs: [frp.id]);
        return frp.id ?? -1;
      }
    }
    final id = await db.insert('FilteredRecordingParts', frp.toDbJson());
    frp.id = id;
    return id;
  }

  static Future<void> updateFilteredRecordingPart(
      FilteredRecordingPart frp) async {
    final db = await database;
    await db.update('FilteredRecordingParts', frp.toDbJson(),
        where: 'id = ?', whereArgs: [frp.id]);
  }

// === Detected Dialects CRUD ===
  static Future<int> insertDetectedDialect(DetectedDialect dd) async {
    final db = await database;
    if (dd.BEId != null) {
      final existing = await db.query('DetectedDialects',
          where: 'BEId = ?', whereArgs: [dd.BEId], limit: 1);
      if (existing.isNotEmpty) {
        dd.id = existing.first['id'] as int?;
        await db.update('DetectedDialects', dd.toDbJson(),
            where: 'id = ?', whereArgs: [dd.id]);
        return dd.id ?? -1;
      }
    }
    final id = await db.insert('DetectedDialects', dd.toDbJson());
    dd.id = id;
    return id;
  }

  static Future<void> updateDetectedDialect(DetectedDialect dd) async {
    final db = await database;
    await db.update('DetectedDialects', dd.toDbJson(),
        where: 'id = ?', whereArgs: [dd.id]);
  }

  static Future<List<DetectedDialect>> getDetectedDialectsByRecordingLocalId(
      int recordingLocalId) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery('''
    SELECT dd.*, frp.startDate AS filteredPartStartDate, frp.endDate AS filteredPartEndDate
    FROM FilteredRecordingParts frp
    JOIN DetectedDialects dd ON dd.filteredPartLocalId = frp.id
    WHERE frp.recordingLocalId = ?
    ORDER BY frp.startDate ASC, dd.id ASC
  ''', [recordingLocalId]);

    return rows.map((row) => DetectedDialect.fromDb(row)).toList();
  }

  /// Representative dialects for a local recording (prefers confirmed, else user guess)
  static Future<List<String>> getRepresentativeDialectCodesForRecording(
      int recordingLocalId) async {
    final db = await database;
    final rows = await db.rawQuery('''
    SELECT DISTINCT COALESCE(dd.confirmedDialect, dd.userGuessDialect) AS code
    FROM FilteredRecordingParts frp
    JOIN DetectedDialects dd ON dd.filteredPartLocalId = frp.id
    WHERE frp.recordingLocalId = ?
      AND frp.representant = 1
      AND COALESCE(dd.confirmedDialect, dd.userGuessDialect) IS NOT NULL
      AND COALESCE(dd.confirmedDialect, dd.userGuessDialect) <> ''
  ''', [recordingLocalId]);

    final codes = rows
        .map((r) =>
            DialectKeywordTranslator.toEnglish(r['code'] as String?) ?? '')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => s.trim())
        .toSet()
        .toList();

    return codes.isEmpty ? <String>['Unknown'] : codes;
  }

  /// Returns all parts for a given recordingId from the DB.
  static Future<List<RecordingPart>> getRecordingPartsByRecordingId(
      int recordingId) async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query(
      'recordingParts',
      where: 'recordingId = ?',
      whereArgs: [recordingId],
    );
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<int?> fetchRecordingFromBE(int id) async {
    return _fetchRecordingFromBE(id);
  }

  static Future<Recording?> getRecordingFromDbByBEId(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query("recordings",
        where: "BEId = ? AND env = ?",
        whereArgs: [id, Config.hostEnvironment.name.toString()]);
    if (results.isNotEmpty) {
      return Recording.fromJson(results.first);
    }
    return null;
  }

  static Future<void> checkSendingRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> result =
        await db.query("recordings", where: "sending = 1");
    List<Recording> recordings =
        result.map((row) => Recording.fromJson(row)).toList();
    for (Recording recording in recordings) {
      final String portName = '/upload/rec/${recording.id}';
      final SendPort? port = IsolateNameServer.lookupPortByName(portName);

      if (port == null) {
        // Health-check server not running — mark as idle
        recording.sending = false;
        await updateRecording(recording);
        _inflightRecordingIds.remove(recording.id);
        List<RecordingPart> parts =
            await getRecordingPartsByRecordingId(recording.id!);

        final List<Future<void>> tasks = <Future<void>>[];

        for (RecordingPart part in parts) {
          tasks.add(() async {
            part.sending = false;
            await updateRecordingPart(part);
            _inflightPartIds.remove(part.id);
          }());
        }
        await Future.wait(tasks);

        logger.i(
            'Recording ${recording.id} marked as not sending (health server not active).');
      } else {
        // Optionally ping it
        final receive = ReceivePort();
        port.send({'replyTo': receive.sendPort, 'cmd': 'ping'});
        try {
          final response =
              await receive.first.timeout(const Duration(seconds: 2));
          if (response is Map && response['status'] == 'uploading') {
            logger.i('Recording ${recording.id} still uploading.');
          } else {
            recording.sending = false;
            await updateRecording(recording);
            logger.i(
                'Recording ${recording.id} status unclear; marking not sending.');
            _inflightRecordingIds.remove(recording.id);
            List<RecordingPart> parts =
                await getRecordingPartsByRecordingId(recording.id!);

            final List<Future<void>> tasks = <Future<void>>[];

            for (RecordingPart part in parts) {
              tasks.add(() async {
                part.sending = false;
                await updateRecordingPart(part);
                _inflightPartIds.remove(part.id);
              }());
            }
            await Future.wait(tasks);
          }
        } catch (_) {
          recording.sending = false;
          await updateRecording(recording);
          logger.i(
              'Recording ${recording.id} did not respond to health ping; marked not sending.');
          _inflightRecordingIds.remove(recording.id);
          List<RecordingPart> parts =
              await getRecordingPartsByRecordingId(recording.id!);

          final List<Future<void>> tasks = <Future<void>>[];

          for (RecordingPart part in parts) {
            tasks.add(() async {
              part.sending = false;
              await updateRecordingPart(part);
              _inflightPartIds.remove(part.id);
            }());
          }
          await Future.wait(tasks);
        } finally {
          receive.close();
        }
      }
    }
  }
}
