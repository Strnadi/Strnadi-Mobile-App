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
import 'dart:math';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
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
import 'package:strnadi/api/immutable_upload_file.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/Models/detectedDialect.dart';
import 'package:strnadi/database/Models/filteredRecordingPart.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'package:strnadi/database/recording_cache_access.dart';
import 'package:strnadi/database/recording_download_service.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/database/recording_upload_scheduling.dart';
import 'package:strnadi/database/recording_update_fields.dart';
import 'package:strnadi/database/upload_protocol.dart';
import 'package:strnadi/database/fileSize.dart';
import 'package:strnadi/database/src/database_logger.dart' as db_log;
import 'package:strnadi/database/src/upload_progress_bus.dart';
import 'package:strnadi/dialects/ModelHandler.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/firebase/local_notifications.dart';
import 'package:strnadi/firebase/notification_cache_isolation.dart';
import 'package:strnadi/firebase/notification_persistence.dart';
import 'package:strnadi/localRecordings/upload_integration_helpers.dart';
import 'package:strnadi/notificationPage/notifList.dart';
import 'package:strnadi/recording/waw.dart';
import 'package:strnadi/user/settingsManager.dart';
import 'package:workmanager/workmanager.dart';

part 'database_repository_api.dart';
part 'database_repository_download.dart';
part 'database_migrations.dart';

final logger = db_log.logger;
final Random _uploadKeyRandom = Random.secure();

String _newUploadKey(String kind) {
  final String entropy = List<String>.generate(
    24,
    (_) => _uploadKeyRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$kind-${DateTime.now().microsecondsSinceEpoch}-$entropy';
}

class IncompleteRecordingUpload {
  IncompleteRecordingUpload({
    required this.recording,
    required this.expectedPartsCount,
    required this.uploadedPartsCount,
    required this.localPartsCount,
    required this.resendablePartsCount,
    required this.hasExactBackendPartCounts,
    required this.reconcileAllBackendParts,
    required Set<int>? uploadedBackendPartIds,
    required RecordingOwnerSnapshot ownerSnapshot,
  })  : uploadedBackendPartIds = uploadedBackendPartIds == null
            ? null
            : Set<int>.unmodifiable(uploadedBackendPartIds),
        _ownerSnapshot = ownerSnapshot;

  final Recording recording;
  final int expectedPartsCount;
  final int uploadedPartsCount;
  final int localPartsCount;
  final int resendablePartsCount;
  final bool hasExactBackendPartCounts;
  final bool reconcileAllBackendParts;
  final Set<int>? uploadedBackendPartIds;
  final RecordingOwnerSnapshot _ownerSnapshot;

  int get missingPartsCount {
    final int missing = expectedPartsCount - uploadedPartsCount;
    return missing > 0 ? missing : 0;
  }

  bool get canResend => resendablePartsCount > 0;

  Future<void> resendMissingParts() =>
      DatabaseNew._resendMissingPartsForRecording(this);
}

class _RecordingDeletionClaim {
  const _RecordingDeletionClaim({
    required this.recording,
    required this.leaseId,
    required this.filePaths,
  });

  final Recording recording;
  final String leaseId;
  final List<String> filePaths;
}

/// Database helper class
class DatabaseNew {
  static const Duration _deletionLeaseTimeout = Duration(minutes: 5);

  static Database? _database;
  static List<FilteredRecordingPart>? fetchedFilteredRecordingParts;
  static List<DetectedDialect>? fetchedDetectedDialects;

  static List<Recording>? fetchedRecordings;
  static List<RecordingPart>? fetchedRecordingParts;
  static RecordingUploadSession? _fetchedRecordingSession;
  static final ValueNotifier<int> unreadNotificationCount =
      ValueNotifier<int>(0);

  static bool fetching = false;
  static bool _durationBackfillNeeded = false;

  static NotificationCacheIsolation _notificationCacheIsolation() {
    return NotificationCacheIsolation(
      captureActivatedSession: activatedAuthSessions.capture,
      isActivatedSessionCurrent: activatedAuthSessions.isCurrent,
      currentEnvironment: () =>
          Config.isHostEnvironmentLoaded ? Config.hostEnvironment.name : '',
    );
  }

  // Legacy in-memory hint retained for stale UI state cleanup. Upload
  // exclusivity itself is enforced by the durable recording lease.
  static final Set<int> _inflightRecordingIds = <int>{};

  /// Enforces the user-defined maximum number of local recordings by deleting the oldest ones.
  static Future<void> enforceMaxRecordings() async {
    logger.i('Enforcing maximum number of local recordings.');
    final int max = await SettingsService().getLocalRecordingsMax();
    logger.i('Maximum allowed recordings: $max');
    if (max <= 0) return; // no limit or invalid

    // Pruning is destructive, so pin it to one fully activated logical login
    // instead of trusting independently written secure-storage keys.
    const _SecureStorageRecordingUploadSessions sessionProvider =
        _SecureStorageRecordingUploadSessions();
    final RecordingUploadSession? session = await sessionProvider.capture();
    if (session == null) return;
    validateRecordingUploadSession(session);
    final String email = session.accountEmail?.trim() ?? '';
    final int? userId = int.tryParse(session.userId.trim());
    if (email.isEmpty || userId == null || userId <= 0) return;
    await _requireRecordingSessionCurrent(sessionProvider, session);

    final Database db = await database;

    // Count only eligible rows (all parts sent, none sending, downloaded)
    final List<Map<String, Object?>> cntRows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ('
      '  SELECT r.id '
      '  FROM recordings r '
      '  LEFT JOIN recordingParts p ON p.recordingId = r.id '
      '  WHERE r.mail = ? AND r.env = ? '
      '    AND (r.userId IS NULL OR r.userId = ?) '
      '    AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      '  GROUP BY r.id '
      '  HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0'
      ') t',
      <Object?>[email, session.environment, userId],
    );
    await _requireRecordingSessionCurrent(sessionProvider, session);

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
      'WHERE r.mail = ? AND r.env = ? '
      'AND (r.userId IS NULL OR r.userId = ?) '
      'AND r.sent = 1 AND COALESCE(r.sending, 0) = 0 AND COALESCE(r.downloaded, 0) = 1 '
      'GROUP BY r.id '
      'HAVING COALESCE(SUM(CASE WHEN COALESCE(p.sent, 0) = 0 OR COALESCE(p.sending, 0) = 1 THEN 1 ELSE 0 END), 0) = 0 '
      'ORDER BY datetime(r.createdAt) ASC LIMIT ?',
      <Object?>[email, session.environment, userId, toDelete],
    );
    await _requireRecordingSessionCurrent(sessionProvider, session);

    // Delete the chosen ids using our existing helper (ensures parts + files are cleaned up)
    for (final Map<String, Object?> row in rows) {
      await _requireRecordingSessionCurrent(sessionProvider, session);
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

  static Future<int> insertRecording(
    Recording recording, {
    RecordingUploadSession? capturedSession,
  }) async {
    try {
      final int? capturedUserId = capturedSession == null
          ? null
          : int.tryParse(capturedSession.userId.trim());
      final String? capturedEmail = capturedSession?.accountEmail?.trim();
      if (capturedSession != null &&
          (capturedUserId == null ||
              capturedUserId <= 0 ||
              capturedEmail == null ||
              capturedEmail.isEmpty ||
              recording.env != capturedSession.environment)) {
        throw const RecordingUploadSessionChangedException();
      }

      final db = await database;
      if (recording.BEId != null) {
        List<Map<String, dynamic>> existing = await db.query("recordings",
            where: "BEId = ? AND env = ?",
            whereArgs: [recording.BEId, recording.env]);
        if (existing.isNotEmpty) {
          final Recording current = Recording.fromJson(existing.first);
          final int id = existing.first["id"] as int;
          if (capturedSession != null) {
            final bool belongsToCapturedAccount =
                recordingBelongsToCapturedAccount(
              sent: recording.sent,
              ownerUserId: recording.userId,
              capturedUserId: capturedUserId!,
            );
            final String desiredMail =
                belongsToCapturedAccount ? capturedEmail! : '';
            final int? desiredUserId =
                belongsToCapturedAccount ? capturedUserId : recording.userId;
            if (current.env != capturedSession.environment) {
              throw const RecordingUploadSessionChangedException();
            }

            final String currentMail = (current.mail ?? '').trim();
            if (currentMail.toLowerCase() != desiredMail.toLowerCase() ||
                current.userId != desiredUserId) {
              final int ownershipChanged = await db.update(
                'recordings',
                <String, Object?>{
                  'mail': desiredMail,
                  'userId': desiredUserId,
                },
                where: 'id = ? AND BEId = ? AND env = ? '
                    'AND (uploadLease IS NULL OR TRIM(uploadLease) = ?)',
                whereArgs: <Object?>[
                  id,
                  recording.BEId,
                  capturedSession.environment,
                  '',
                ],
              );
              if (ownershipChanged != 1) {
                throw const RecordingUploadSessionChangedException();
              }
            }
            current
              ..mail = desiredMail
              ..userId = desiredUserId;
            recording
              ..mail = desiredMail
              ..userId = desiredUserId;
          }
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
          recording
            ..userId ??= current.userId
            ..uploadKey ??= current.uploadKey;
          await updateRecording(recording);
          await updateRecordingCacheState(recording);
          await updateRecordingDuration(recording);
          logger.i(
            'Recording with BEId ${recording.BEId} updated (id: $id).',
          );
          return id;
        }
      }
      final String? token = capturedSession == null
          ? await FlutterSecureStorage().read(key: 'token')
          : capturedSession.accessToken;
      final String? userIdS = capturedSession == null
          ? await FlutterSecureStorage().read(key: 'userId')
          : capturedSession.userId;
      final int? currentUserId =
          capturedUserId ?? int.tryParse((userIdS ?? '').trim());

      logger.i('Token available: ${token != null && token.isNotEmpty}');

      if (token == null || token == '') {
        recording.mail ??= '';
      } else {
        final String currentEmail =
            capturedEmail ?? JwtDecoder.decode(token)['sub'];
        final bool belongsToCapturedAccount = recordingBelongsToCapturedAccount(
          sent: recording.sent,
          ownerUserId: recording.userId,
          capturedUserId: currentUserId ?? -1,
        );
        if (!belongsToCapturedAccount) {
          // Keep foreign recordings out of "My recordings" while still cached locally.
          recording.mail = '';
        } else {
          recording.mail = currentEmail;
          recording.userId ??= currentUserId;
        }
      }
      recording.uploadKey ??= _newUploadKey('recording');
      final int id = await db.insert("recordings", recording.toJson());
      recording.id = id;
      if (capturedSession == null && token != null && token != '') {
        await enforceMaxRecordings();
      }
      logger.i('Recording ${recording.id} inserted.');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
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
    const _SecureStorageRecordingUploadSessions sessionProvider =
        _SecureStorageRecordingUploadSessions();
    final RecordingUploadSession? session = await sessionProvider.capture();
    if (session == null) return;
    validateRecordingUploadSession(session);
    final int userId = int.parse(session.userId);
    final String email = session.accountEmail?.trim() ?? '';
    if (email.isEmpty) return;

    // Adopt only genuine guest drafts in the active environment. Rows already
    // carrying an owner id may belong to another account even when legacy code
    // left their mail blank.
    await db.transaction<void>((Transaction txn) async {
      await _requireRecordingSessionCurrent(sessionProvider, session);
      await txn.rawUpdate(
        'UPDATE recordings SET mail = ?, userId = ? '
        'WHERE env = ? AND userId IS NULL '
        'AND (mail IS NULL OR TRIM(mail) = ?) '
        'AND COALESCE(sent, 0) = 0 AND BEId IS NULL '
        'AND COALESCE(sending, 0) = 0 '
        'AND COALESCE(parentUploadAttempted, 0) = 0 '
        'AND (uploadLease IS NULL OR TRIM(uploadLease) = ?)',
        <Object?>[
          email,
          userId,
          session.environment,
          '',
          '',
        ],
      );
      // If the account changed while SQLite was updating, throwing from the
      // transaction rolls the guest adoption back.
      await _requireRecordingSessionCurrent(sessionProvider, session);
    });
  }

  static Future<Map<String, Object?>> _requireCurrentEnvironmentRecordingParent(
    DatabaseExecutor executor, {
    required int? localRecordingId,
    required int? backendRecordingId,
    required String environment,
    required String childLabel,
  }) async {
    if (localRecordingId != null && localRecordingId <= 0) {
      throw RecordingUploadValidationException(
        '$childLabel has an invalid local recording id.',
      );
    }
    if (backendRecordingId != null && backendRecordingId <= 0) {
      throw RecordingUploadValidationException(
        '$childLabel has an invalid backend recording id.',
      );
    }
    if (localRecordingId == null && backendRecordingId == null) {
      throw RecordingUploadValidationException(
        '$childLabel must identify its recording parent.',
      );
    }

    final List<Map<String, Object?>> parents = await executor.query(
      'recordings',
      columns: const <String>['id', 'BEId', 'env'],
      where: localRecordingId == null
          ? 'BEId = ? AND env = ?'
          : 'id = ? AND env = ?',
      whereArgs: <Object?>[
        localRecordingId ?? backendRecordingId,
        environment,
      ],
      limit: 1,
    );
    if (parents.isEmpty) {
      throw RecordingUploadValidationException(
        '$childLabel has no local recording parent in the current '
        'environment.',
      );
    }

    final Map<String, Object?> parent = parents.first;
    final int? persistedBackendId = parent['BEId'] as int?;
    if (persistedBackendId == null || persistedBackendId <= 0) {
      throw RecordingUploadValidationException(
        '$childLabel cannot reference a recording without a valid backend id.',
      );
    }
    if (backendRecordingId != null &&
        backendRecordingId != persistedBackendId) {
      throw RecordingUploadValidationException(
        '$childLabel backend parent does not match its local recording.',
      );
    }
    return parent;
  }

  static Future<void> _freezePersistedBackendRecordingPart(
    DatabaseExecutor executor, {
    required int partId,
    required int backendPartId,
  }) async {
    if (partId <= 0 || backendPartId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot freeze a recording part without positive local and backend '
        'identities.',
      );
    }
    final int changed = await executor.rawUpdate(
      'UPDATE recordingParts SET uploadAttempted = 1 '
      'WHERE id = ? AND BEId = ? '
      'AND NOT EXISTS ('
      'SELECT 1 FROM recordings r '
      'WHERE r.id = recordingParts.recordingId '
      'AND r.uploadLease IS NOT NULL '
      'AND TRIM(r.uploadLease) <> ?'
      ')',
      <Object?>[partId, backendPartId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Recording part is missing or owned by an active workflow.',
      );
    }
  }

  static Future<int> insertRecordingPart(
    RecordingPart recordingPart, {
    String? capturedEnvironment,
  }) async {
    try {
      final db = await database;
      if (recordingPart.id != null) {
        List<Map<String, dynamic>> existing = await db.query("recordingParts",
            where: "id = ?", whereArgs: [recordingPart.id]);
        if (existing.isNotEmpty) {
          int id = existing.first["id"];
          final RecordingPart current = RecordingPart.fromJson(existing.first);
          recordingPart.id = id;
          recordingPart.uploadKey ??= current.uploadKey;
          if (current.BEId != null) {
            if (recordingPart.BEId != null &&
                recordingPart.BEId != current.BEId) {
              throw const RecordingUploadValidationException(
                'A recording part local id cannot change backend identity.',
              );
            }
            await _freezePersistedBackendRecordingPart(
              db,
              partId: id,
              backendPartId: current.BEId!,
            );
            recordingPart
              ..BEId = current.BEId
              ..recordingId = current.recordingId
              ..backendRecordingId = current.backendRecordingId
              ..uploadAttempted = true;
            return id;
          }
          await updateRecordingPart(recordingPart);
          logger.i(
              'Recording part with backendRecordingId ${recordingPart.backendRecordingId} updated (id: $id).');
          return id;
        }
      }
      if (recordingPart.BEId != null) {
        if (recordingPart.BEId! <= 0) {
          throw const RecordingUploadValidationException(
            'A backend recording part must have a positive backend id.',
          );
        }
        final Map<String, Object?> parent =
            await _requireCurrentEnvironmentRecordingParent(
          db,
          localRecordingId: recordingPart.recordingId,
          backendRecordingId: recordingPart.backendRecordingId,
          environment: capturedEnvironment ?? Config.hostEnvironment.name,
          childLabel: 'A backend recording part',
        );
        final int parentId = parent['id'] as int;
        final int parentBackendId = parent['BEId'] as int;
        recordingPart
          ..recordingId = parentId
          ..backendRecordingId = parentBackendId;
        List<Map<String, dynamic>> existingByBeId = await db.query(
          "recordingParts",
          where: "BEId = ? AND recordingId = ?",
          whereArgs: [recordingPart.BEId, parentId],
        );
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
          recordingPart.uploadKey ??= existing.uploadKey;
          if (!existing.uploadAttempted) {
            await updateRecordingPart(recordingPart);
          }
          await _freezePersistedBackendRecordingPart(
            db,
            partId: recordingPart.id!,
            backendPartId: recordingPart.BEId!,
          );
          recordingPart.uploadAttempted = true;
          logger.i(
              'Recording part with BEId ${recordingPart.BEId} updated (id: ${recordingPart.id}).');
          return recordingPart.id ?? -1;
        }
      }
      if (recordingPart.BEId != null) {
        recordingPart.uploadAttempted = true;
      }
      recordingPart.uploadKey ??= _newUploadKey('recording-part');
      final int id = await db.insert("recordingParts", recordingPart.toJson());
      recordingPart.id = id;
      logger.i('Recording part ${recordingPart.id} inserted.');
      return id;
    } catch (e, stackTrace) {
      logger.e('Failed to insert recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<RecordingOwnerSnapshot> _captureRecordingOwnerSnapshot() async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    final String? observedToken = await storage.read(key: 'token');
    final String? observedUserId = await storage.read(key: 'userId');
    final bool hasToken = observedToken?.trim().isNotEmpty ?? false;
    final bool hasUserId = observedUserId?.trim().isNotEmpty ?? false;

    late final RecordingOwnerSnapshot snapshot;
    try {
      if (!hasToken && !hasUserId) {
        snapshot = resolveRecordingOwnerSnapshot(
          accessToken: null,
          userId: null,
          accountEmail: null,
          logicalSessionId: null,
          environment: Config.hostEnvironment.name,
          backendHost: Config.host,
        );
      } else {
        if (hasToken != hasUserId) {
          throw StateError(
            'Authentication changed while recording ownership was captured.',
          );
        }
        const _SecureStorageRecordingUploadSessions sessionProvider =
            _SecureStorageRecordingUploadSessions();
        final RecordingUploadSession? session = await sessionProvider.capture();
        if (session == null) {
          throw StateError(
            'Authentication changed while recording ownership was captured.',
          );
        }
        validateRecordingUploadSession(session);
        snapshot = resolveRecordingOwnerSnapshot(
          accessToken: session.accessToken,
          userId: session.userId,
          accountEmail: session.accountEmail,
          logicalSessionId: session.logicalSessionId,
          environment: session.environment,
          backendHost: session.backendHost,
        );
      }
    } on StateError {
      throw const RecordingUploadSessionChangedException();
    }

    await _requireRecordingOwnerSnapshotCurrent(snapshot);
    return snapshot;
  }

  static Future<bool> _isRecordingOwnerSnapshotCurrent(
    RecordingOwnerSnapshot snapshot,
  ) async {
    String? token;
    String? userId;
    String? accountEmail;
    String? logicalSessionId;
    if (snapshot.isGuest) {
      const FlutterSecureStorage storage = FlutterSecureStorage();
      token = await storage.read(key: 'token');
      userId = await storage.read(key: 'userId');
    } else {
      const _SecureStorageRecordingUploadSessions sessionProvider =
          _SecureStorageRecordingUploadSessions();
      final RecordingUploadSession? session = await sessionProvider.capture();
      token = session?.accessToken;
      userId = session?.userId;
      accountEmail = session?.accountEmail;
      logicalSessionId = session?.logicalSessionId;
    }
    return recordingOwnerSnapshotIsCurrent(
      snapshot: snapshot,
      accessToken: token,
      userId: userId,
      accountEmail: accountEmail,
      logicalSessionId: logicalSessionId,
      environment: Config.hostEnvironment.name,
      backendHost: Config.host,
    );
  }

  static Future<void> _requireRecordingOwnerSnapshotCurrent(
    RecordingOwnerSnapshot snapshot,
  ) async {
    if (!await _isRecordingOwnerSnapshotCurrent(snapshot)) {
      throw const RecordingUploadSessionChangedException();
    }
  }

  /// Persists a newly captured recording and all of its dependent rows as one
  /// transaction. Upload scheduling must only happen after this method returns.
  static Future<int> insertRecordingDraft(
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
  ) async {
    if (parts.isEmpty) {
      throw const RecordingUploadValidationException(
        'A captured recording must contain at least one part.',
      );
    }
    if (recording.partCount != null &&
        recording.partCount! > 0 &&
        recording.partCount != parts.length) {
      throw RecordingUploadValidationException(
        'Expected ${recording.partCount} parts but received ${parts.length}.',
      );
    }

    final RecordingOwnerSnapshot ownerSnapshot =
        await _captureRecordingOwnerSnapshot();
    recording
      ..env = ownerSnapshot.environment
      ..mail = ownerSnapshot.isGuest ? '' : ownerSnapshot.accountEmail
      ..userId =
          ownerSnapshot.isGuest ? null : int.parse(ownerSnapshot.userId!);
    recording.uploadKey ??= _newUploadKey('recording');
    recording.partCount = parts.length;
    for (final RecordingPart part in parts) {
      part.uploadKey ??= _newUploadKey('recording-part');
    }
    for (final Dialect dialect in dialects) {
      dialect.uploadKey ??= _newUploadKey('dialect');
    }

    final Database db = await database;
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    late final int recordingId;
    try {
      recordingId = await db.transaction<int>((Transaction txn) async {
        final int id = await txn.insert('recordings', recording.toJson());
        if (id <= 0) {
          throw StateError('Failed to insert recording draft.');
        }
        recording.id = id;

        for (final RecordingPart part in parts) {
          part.recordingId = id;
          final int partId = await txn.insert('recordingParts', part.toJson());
          if (partId <= 0) {
            throw StateError('Failed to insert recording part.');
          }
          part.id = partId;
        }

        for (final Dialect dialect in dialects) {
          dialect.recordingId = id;
          final int dialectId = await txn.insert('Dialects', dialect.toJson());
          if (dialectId <= 0) {
            throw StateError('Failed to insert recording dialect.');
          }
          dialect.id = dialectId;
        }
        return id;
      });
    } catch (error, stackTrace) {
      try {
        final PersistedDraftIdentity? reconciled =
            await _reconcilePersistedRecordingDraft(
          db,
          recording,
          parts,
          dialects,
          ownerSnapshot,
        );
        if (reconciled == null) {
          _clearDraftLocalIds(recording, parts, dialects);
          logger.e(
            'Failed to persist recording draft transaction',
            error: error,
            stackTrace: stackTrace,
          );
          Sentry.captureException(error, stackTrace: stackTrace);
          Error.throwWithStackTrace(
            RecordingDraftPersistenceException(
              error,
              commitState: RecordingDraftCommitState.definitelyAbsent,
            ),
            stackTrace,
          );
        }
        recordingId = reconciled.recordingId;
        logger.w(
          'Recording draft commit acknowledgement was ambiguous; recovered '
          'the complete aggregate by durable upload keys.',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (reconciliationError, reconciliationStackTrace) {
        if (reconciliationError is RecordingDraftPersistenceException) {
          Error.throwWithStackTrace(
            reconciliationError,
            reconciliationStackTrace,
          );
        }
        _clearDraftLocalIds(recording, parts, dialects);
        logger.e(
          'Recording draft persistence could not be reconciled safely',
          error: reconciliationError,
          stackTrace: reconciliationStackTrace,
        );
        Sentry.captureException(
          reconciliationError,
          stackTrace: reconciliationStackTrace,
        );
        Error.throwWithStackTrace(
          RecordingDraftPersistenceException(
            reconciliationError,
            commitState: RecordingDraftCommitState.mayHaveCommitted,
          ),
          reconciliationStackTrace,
        );
      }
    }

    try {
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RecordingDraftPersistenceException(
          error,
          commitState: RecordingDraftCommitState.mayHaveCommitted,
        ),
        stackTrace,
      );
    }
    return recordingId;
  }

  static Future<PersistedDraftIdentity?> _reconcilePersistedRecordingDraft(
    DatabaseExecutor executor,
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
    RecordingOwnerSnapshot ownerSnapshot,
  ) async {
    final String recordingUploadKey = (recording.uploadKey ?? '').trim();
    final List<Map<String, Object?>> recordingRows = await executor.query(
      'recordings',
      columns: const <String>[
        'id',
        'uploadKey',
        'mail',
        'userId',
        'env',
      ],
      where: 'uploadKey = ?',
      whereArgs: <Object?>[recordingUploadKey],
    );
    if (recordingRows.isEmpty) return null;

    final Object? rawRecordingId = recordingRows.first['id'];
    final int? persistedRecordingId = rawRecordingId is int
        ? rawRecordingId
        : int.tryParse(rawRecordingId?.toString() ?? '');
    if (persistedRecordingId == null || persistedRecordingId <= 0) {
      throw StateError(
        'The reconciled recording draft has an invalid local id.',
      );
    }
    final List<Map<String, Object?>> partRows = await executor.query(
      'recordingParts',
      columns: const <String>['id', 'recordingId', 'uploadKey'],
      where: 'recordingId = ?',
      whereArgs: <Object?>[persistedRecordingId],
    );
    final List<Map<String, Object?>> dialectRows = await executor.query(
      'Dialects',
      columns: const <String>['id', 'recordingId', 'uploadKey'],
      where: 'recordingId = ?',
      whereArgs: <Object?>[persistedRecordingId],
    );
    final PersistedDraftIdentity? identity = reconcilePersistedDraftIdentity(
      ownerSnapshot: ownerSnapshot,
      recordingUploadKey: recordingUploadKey,
      expectedPartUploadKeys:
          parts.map((part) => (part.uploadKey ?? '').trim()),
      expectedDialectUploadKeys:
          dialects.map((dialect) => (dialect.uploadKey ?? '').trim()),
      recordingRows: recordingRows,
      partRows: partRows,
      dialectRows: dialectRows,
    );
    if (identity == null) return null;

    recording.id = identity.recordingId;
    for (final RecordingPart part in parts) {
      part
        ..id = identity.partIdsByUploadKey[(part.uploadKey ?? '').trim()]
        ..recordingId = identity.recordingId;
    }
    for (final Dialect dialect in dialects) {
      dialect
        ..id = identity.dialectIdsByUploadKey[(dialect.uploadKey ?? '').trim()]
        ..recordingId = identity.recordingId;
    }
    return identity;
  }

  static void _clearDraftLocalIds(
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
  ) {
    recording.id = null;
    for (final RecordingPart part in parts) {
      part
        ..id = null
        ..recordingId = null;
    }
    for (final Dialect dialect in dialects) {
      dialect
        ..id = null
        ..recordingId = null;
    }
  }

  /// Updates editable metadata for a saved-but-not-started upload and replaces
  /// its dialect rows atomically. A worker lease wins the race and makes this
  /// fail closed instead of mutating an aggregate already being sent.
  static Future<void> updateRecordingDraft(
    Recording recording,
    List<Dialect> dialects,
  ) async {
    final int? recordingId = recording.id;
    if (recordingId == null || recordingId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update a recording draft without a valid local id.',
      );
    }

    final String recordingUploadKey = (recording.uploadKey ?? '').trim();
    if (recordingUploadKey.isEmpty) {
      throw const RecordingUploadValidationException(
        'Cannot update a recording draft without a durable upload key.',
      );
    }
    final RecordingOwnerSnapshot ownerSnapshot =
        await _captureRecordingOwnerSnapshot();
    if (!recordingOwnerBindingMatchesSnapshot(
      snapshot: ownerSnapshot,
      persistedUserId: recording.userId,
      persistedEmail: recording.mail,
      persistedEnvironment: recording.env,
    )) {
      throw const RecordingUploadSessionChangedException();
    }
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

    final Database db = await database;
    await db.transaction<void>((Transaction txn) async {
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      final List<Map<String, Object?>> rows = await txn.query(
        'recordings',
        columns: const <String>[
          'sent',
          'sending',
          'BEId',
          'parentUploadAttempted',
          'uploadKey',
          'uploadLease',
          'mail',
          'userId',
          'env',
        ],
        where: 'id = ? AND uploadKey = ?',
        whereArgs: <Object?>[recordingId, recordingUploadKey],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const RecordingUploadValidationException(
          'The recording draft no longer exists.',
        );
      }
      final Map<String, Object?> row = rows.first;
      if (!recordingOwnerBindingMatchesSnapshot(
        snapshot: ownerSnapshot,
        persistedUserId: row['userId'],
        persistedEmail: row['mail'] as String?,
        persistedEnvironment: row['env'] as String? ?? '',
      )) {
        throw const RecordingUploadSessionChangedException();
      }
      final bool sent = row['sent'] == 1 || row['sent'] == true;
      final bool sending = row['sending'] == 1 || row['sending'] == true;
      final int? backendId = row['BEId'] as int?;
      final bool parentUploadAttempted = row['parentUploadAttempted'] == 1 ||
          row['parentUploadAttempted'] == true;
      final String? lease = row['uploadLease'] as String?;
      if (sent ||
          sending ||
          backendId != null ||
          parentUploadAttempted ||
          (lease != null && lease.isNotEmpty)) {
        throw StateError('Recording upload has already started.');
      }
      final String currentUploadKey =
          (row['uploadKey'] as String? ?? '').trim();
      if (currentUploadKey != recordingUploadKey) {
        throw const RecordingUploadValidationException(
          'The recording draft identity changed.',
        );
      }
      recording.uploadKey = currentUploadKey;

      late final String ownerPredicate;
      late final String aliasedOwnerPredicate;
      final List<Object?> ownerArgs = <Object?>[ownerSnapshot.environment];
      if (ownerSnapshot.isGuest) {
        ownerPredicate = 'env = ? AND userId IS NULL '
            "AND (mail IS NULL OR TRIM(mail) = '')";
        aliasedOwnerPredicate = 'r.env = ? AND r.userId IS NULL '
            "AND (r.mail IS NULL OR TRIM(r.mail) = '')";
      } else {
        ownerPredicate = 'env = ? AND userId = ? '
            'AND LOWER(TRIM(mail)) = LOWER(?)';
        aliasedOwnerPredicate = 'r.env = ? AND r.userId = ? '
            'AND LOWER(TRIM(r.mail)) = LOWER(?)';
        ownerArgs.addAll(<Object?>[
          int.parse(ownerSnapshot.userId!),
          ownerSnapshot.accountEmail,
        ]);
      }

      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

      final List<Map<String, Object?>> uploadedDialects = await txn.query(
        'Dialects',
        columns: const <String>['id'],
        where: 'recordingId = ? AND ('
            'BEID IS NOT NULL OR COALESCE(uploadAttempted, 0) = 1'
            ')',
        whereArgs: <Object?>[recordingId],
        limit: 1,
      );
      if (uploadedDialects.isNotEmpty) {
        throw StateError('Recording dialect upload has already started.');
      }
      final List<Map<String, Object?>> uploadedParts = await txn.query(
        'recordingParts',
        columns: const <String>['id'],
        where: 'recordingId = ? AND ('
            'BEId IS NOT NULL OR backendRecordingId IS NOT NULL '
            'OR COALESCE(sent, 0) = 1 OR COALESCE(sending, 0) = 1 '
            'OR COALESCE(uploadAttempted, 0) = 1'
            ')',
        whereArgs: <Object?>[recordingId],
        limit: 1,
      );
      if (uploadedParts.isNotEmpty) {
        throw StateError('Recording part upload has already started.');
      }

      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      final Map<String, Object?> reviewedMetadata =
          recordingMetadataUpdateFields(recording)..['captureReviewed'] = 1;
      final int changed = await txn.update(
        'recordings',
        reviewedMetadata,
        where: 'id = ? AND uploadKey = ? AND $ownerPredicate '
            'AND COALESCE(sending, 0) = 0 '
            'AND COALESCE(sent, 0) = 0 AND BEId IS NULL '
            'AND COALESCE(parentUploadAttempted, 0) = 0 '
            'AND uploadLease IS NULL',
        whereArgs: <Object?>[
          recordingId,
          recordingUploadKey,
          ...ownerArgs,
        ],
      );
      if (changed != 1) {
        throw StateError('Recording upload started while saving its draft.');
      }
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

      await txn.delete(
        'Dialects',
        where: 'recordingId = ? AND BEID IS NULL '
            'AND COALESCE(uploadAttempted, 0) = 0 AND EXISTS ('
            'SELECT 1 FROM recordings r '
            'WHERE r.id = Dialects.recordingId '
            'AND r.id = ? AND r.uploadKey = ? '
            'AND $aliasedOwnerPredicate '
            'AND COALESCE(r.sending, 0) = 0 '
            'AND COALESCE(r.sent, 0) = 0 AND r.BEId IS NULL '
            'AND COALESCE(r.parentUploadAttempted, 0) = 0 '
            'AND r.uploadLease IS NULL'
            ')',
        whereArgs: <Object?>[
          recordingId,
          recordingId,
          recordingUploadKey,
          ...ownerArgs,
        ],
      );
      for (final Dialect dialect in dialects) {
        await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
        dialect
          ..id = null
          ..recordingId = recordingId
          ..uploadKey = _newUploadKey('dialect');
        final int dialectId = await txn.insert('Dialects', dialect.toJson());
        if (dialectId <= 0) {
          throw StateError('Failed to replace recording dialect.');
        }
        dialect.id = dialectId;
      }
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    });
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    recording.captureReviewed = true;
  }

  static Future<void> onFetchFinished(
    RecordingUploadSession session,
  ) async {
    const _SecureStorageRecordingUploadSessions sessionProvider =
        _SecureStorageRecordingUploadSessions();
    await _requireRecordingSessionCurrent(sessionProvider, session);
    List<Recording> oldRecordings =
        await _getRecordingsForCapturedSession(session);
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
    // Delete sent recordings missing on backend
    for (Recording recording in sentRecordings) {
      await _requireRecordingSessionCurrent(sessionProvider, session);
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
      await _requireRecordingSessionCurrent(sessionProvider, session);
      recording.sent = true;
      recording.downloaded = false;
      logger.i(
          'Inserting recording with BEId: ${recording.BEId} and name ${recording.name}');
      await insertRecording(recording, capturedSession: session);
      if (recording.BEId != null && recording.id != null) {
        beIdToLocalId[recording.BEId!] = recording.id!;
      }
    }

    List<RecordingPart> oldRecordingParts = await getRecordingParts();
    final Set<(int, int)> existingPartIds = <(int, int)>{
      for (final RecordingPart part in oldRecordingParts)
        if (part.recordingId != null && part.BEId != null)
          (part.recordingId!, part.BEId!),
    };

    for (final RecordingPart recordingPart in fetchedRecordingParts!) {
      await _requireRecordingSessionCurrent(sessionProvider, session);
      final int? backendRecordingId = recordingPart.backendRecordingId;
      final int? localRecordingId =
          backendRecordingId == null ? null : beIdToLocalId[backendRecordingId];
      if (localRecordingId == null) {
        logger.w(
          'Skipping backend part ${recordingPart.BEId}: no current-environment '
          'recording exists for backend recording $backendRecordingId.',
        );
        continue;
      }

      final int? backendPartId = recordingPart.BEId;
      if (backendPartId != null &&
          !existingPartIds.add((localRecordingId, backendPartId))) {
        continue;
      }

      recordingPart
        ..sent = true
        ..recordingId = localRecordingId;
      await insertRecordingPart(recordingPart);
    }
    await _requireRecordingSessionCurrent(sessionProvider, session);
  }

  static Future<void> syncRecordings() async {
    if (fetching) return;
    logger.i("🔄 Syncing recordings...");
    try {
      await fetchRecordingsFromBE();
      final RecordingUploadSession? session = _fetchedRecordingSession;
      if (session == null) {
        throw const RecordingUploadSessionChangedException();
      }
      const _SecureStorageRecordingUploadSessions sessionProvider =
          _SecureStorageRecordingUploadSessions();
      await _requireRecordingSessionCurrent(sessionProvider, session);
      await onFetchFinished(session);
      await _requireRecordingSessionCurrent(sessionProvider, session);
      if (fetchedRecordings != null && fetchedRecordings!.isNotEmpty) {
        await _fetchFilteredPartsForRecordingsFromBE(
          fetchedRecordings!,
          capturedSession: session,
        );
        await _requireRecordingSessionCurrent(sessionProvider, session);
        await persistFetchedFilteredParts();
      }
      logger.i("✅ Recordings fetched and synced.");
    } catch (e, stackTrace) {
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  static Future<List<Recording>> getRecordings() async {
    final RecordingOwnerSnapshot ownerSnapshot =
        await _captureRecordingOwnerSnapshot();
    return _getVisibleRecordingsForOwnerSnapshot(ownerSnapshot);
  }

  static Future<List<Recording>> _getVisibleRecordingsForOwnerSnapshot(
    RecordingOwnerSnapshot ownerSnapshot, {
    int? recordingId,
  }) async {
    final Database db = await database;
    final String idPredicate = recordingId == null ? '' : 'id = ? AND ';
    final List<Object?> whereArgs = <Object?>[
      if (recordingId != null) recordingId,
    ];
    late final String where;
    if (ownerSnapshot.isGuest) {
      where = '${idPredicate}env = ? AND userId IS NULL '
          'AND (mail IS NULL OR TRIM(mail) = ?) '
          'AND COALESCE(sent, 0) = 0 AND BEId IS NULL';
      whereArgs.addAll(<Object?>[ownerSnapshot.environment, '']);
    } else {
      where = '${idPredicate}mail = ? AND env = ? '
          'AND (userId IS NULL OR userId = ?)';
      whereArgs.addAll(<Object?>[
        ownerSnapshot.accountEmail,
        ownerSnapshot.environment,
        int.parse(ownerSnapshot.userId!),
      ]);
    }
    final List<Map<String, Object?>> recs = await db.query(
      'recordings',
      where: where,
      whereArgs: whereArgs,
      limit: recordingId == null ? null : 1,
    );
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    return recs.map(Recording.fromJson).toList(growable: false);
  }

  static Future<List<Recording>> _getRecordingsForCapturedSession(
    RecordingUploadSession session,
  ) async {
    validateRecordingUploadSession(session);
    final int? userId = int.tryParse(session.userId.trim());
    final String? email = session.accountEmail?.trim();
    if (userId == null ||
        userId <= 0 ||
        email == null ||
        email.isEmpty ||
        session.environment.trim().isEmpty) {
      throw const RecordingUploadSessionChangedException();
    }

    final Database db = await database;
    final List<Map<String, dynamic>> recs = await db.query(
      'recordings',
      where: 'mail = ? AND env = ? AND (userId IS NULL OR userId = ?)',
      whereArgs: <Object?>[email, session.environment, userId],
    );
    return recs.map(Recording.fromJson).toList(growable: false);
  }

  /// Returns cache entries belonging to the exact activated owner/environment.
  ///
  /// Guests and unverified sessions receive an empty list. A logical-login
  /// change during the query fails closed instead of returning the previous
  /// account's recording names to Settings.
  static Future<List<Recording>> getDownloadedRecordingsForCurrentUser() async {
    const _SecureStorageRecordingUploadSessions sessions =
        _SecureStorageRecordingUploadSessions();
    return listDownloadedRecordingCacheForActivatedOwner<Recording>(
      sessions: sessions,
      loadOwnedEntries: (RecordingCacheOwner owner) async {
        final Database db = await database;
        final List<Map<String, dynamic>> recs = await db.query(
          'recordings',
          where: 'downloaded = 1 '
              'AND env = ? AND userId = ? '
              "AND LOWER(TRIM(COALESCE(mail, ''))) = ? "
              'AND ('
              "  (path IS NOT NULL AND path <> '') OR "
              '  EXISTS ('
              '    SELECT 1 FROM recordingParts p '
              '    WHERE p.recordingId = recordings.id '
              '      AND p.path IS NOT NULL '
              "      AND p.path <> ''"
              '  )'
              ')',
          whereArgs: <Object?>[
            owner.environment,
            owner.userId,
            owner.normalizedEmail,
          ],
          orderBy: 'datetime(createdAt) DESC',
        );
        return recs
            .map((Map<String, dynamic> row) => Recording.fromJson(row))
            .toList(growable: false);
      },
    );
  }

  static Future<List<RecordingPart>> getRecordingParts() async {
    final db = await database;
    final List<Map<String, dynamic>> parts = await db.query("recordingParts");
    return List.generate(parts.length, (i) => RecordingPart.fromJson(parts[i]));
  }

  static Future<void> deleteRecording(int id) async {
    _RecordingDeletionClaim? claim;
    try {
      final String environment = Config.hostEnvironment.name;
      final String backendHost = Config.host;
      const _SecureStorageRecordingUploadSessions sessionProvider =
          _SecureStorageRecordingUploadSessions();
      final RecordingUploadSession? session = await sessionProvider.capture();
      if (Config.hostEnvironment.name != environment ||
          Config.host != backendHost ||
          (session != null &&
              (session.environment != environment ||
                  session.backendHost != backendHost))) {
        throw const RecordingUploadSessionChangedException();
      }

      claim = await _claimRecordingDeletion(
        id,
        environment: environment,
        session: session,
        requireRemoteSession: true,
      );
      final Recording recording = claim.recording;

      // A backend id can be durable before all parts finish. Delete partial
      // parents too, otherwise local deletion would orphan remote data.
      if (recording.BEId != null) {
        if (session == null || session.backendHost.isEmpty) {
          throw FetchException(
            'Authentication is required to delete a remote recording.',
            401,
          );
        }
        validateRecordingSessionBinding(recording, session);
        if (!await sessionProvider.isCurrent(session)) {
          throw const RecordingUploadSessionChangedException();
        }
        final Response<dynamic> response = await _recordingsApi.deleteRecording(
          recording.BEId!,
          accessToken: session.accessToken,
          host: session.backendHost,
        );
        final int status = response.statusCode ?? 500;
        if ((status < 200 || status >= 300) && status != 404) {
          throw UploadException(
            'Failed to delete the recording from the backend.',
            status,
          );
        }
        logger.i('Recording BEId ${recording.BEId} deleted on backend.');
      }

      await _deleteClaimedRecordingLocally(claim);
      logger.i(
          'Recording id $id deleted locally (and on backend if applicable).');
    } catch (e, stackTrace) {
      if (claim != null) {
        await _releaseDeletionClaim(claim);
      }
      logger.e('Failed to delete recording id $id',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<void> sendRecordingBackground(int recordingId) async {
    await scheduleReviewedRecordingUpload(
      recordingId: recordingId,
      loadCaptureReviewed: (int id) async {
        final Database db = await database;
        final List<Map<String, Object?>> rows = await db.query(
          'recordings',
          columns: const <String>['captureReviewed'],
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        return rows.length == 1
            ? persistedCaptureReviewFlag(rows.single['captureReviewed'])
            : null;
      },
      schedule: (int id) {
        return Workmanager().registerOneOffTask(
          Platform.isIOS
              ? "com.delta.strnadi.sendRecording"
              : "sendRecording_$id",
          Platform.isIOS ? "com.delta.strnadi.sendRecording" : "sendRecording",
          inputData: <String, int>{"recordingId": id},
          existingWorkPolicy: Platform.isIOS
              ? ExistingWorkPolicy.append
              : ExistingWorkPolicy.keep,
        );
      },
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

  static Future<T> runWithRecordingWorkflowLease<T>({
    required int recordingId,
    required String leaseId,
    required Future<T> Function(RecordingWorkflowLeaseContext context)
        operation,
  }) {
    return const RecordingWorkflowLeaseService(
      store: _SqliteRecordingUploadStore(),
      sessions: _SecureStorageRecordingUploadSessions(),
    ).run<T>(
      recordingId: recordingId,
      leaseId: leaseId,
      operation: operation,
    );
  }

  static Future<void> updateDialectWithWorkflowLease(
    Dialect dialect,
    int recordingId,
    String leaseId,
  ) async {
    final Database db = await database;
    final int changed = await db.update(
      'Dialects',
      dialect.toJson(),
      where: 'id = ? AND recordingId = ? AND EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = ? AND r.uploadLease = ?'
          ')',
      whereArgs: <Object?>[
        dialect.id,
        recordingId,
        recordingId,
        leaseId,
      ],
    );
    if (changed != 1) {
      throw StateError('Recording workflow lease is no longer current.');
    }
  }

  static Future<void> markDialectAttemptedWithWorkflowLease(
    int dialectId,
    int recordingId,
    String leaseId,
  ) async {
    final Database db = await database;
    final int changed = await db.rawUpdate(
      'UPDATE Dialects SET uploadAttempted = 1 '
      'WHERE id = ? AND recordingId = ? AND BEID IS NULL '
      'AND EXISTS ('
      'SELECT 1 FROM recordings r '
      'WHERE r.id = ? AND r.uploadLease = ?'
      ')',
      <Object?>[
        dialectId,
        recordingId,
        recordingId,
        leaseId,
      ],
    );
    if (changed != 1) {
      throw StateError('Recording workflow lease is no longer current.');
    }
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
  ///
  /// This unscoped entry point is reserved for internal workflows which
  /// already own a concrete local draft/cache row. User-facing Settings must
  /// use [deleteDownloadedRecordingFromCurrentUserCache].
  static Future<void> deleteRecordingFromCache(int id) async {
    _RecordingDeletionClaim? claim;
    try {
      claim = await _claimRecordingDeletion(
        id,
        environment: null,
        session: null,
        requireRemoteSession: false,
      );
      await _deleteClaimedRecordingLocally(claim);
      logger.i('Recording id $id deleted from cache.');
    } catch (_) {
      if (claim != null) {
        await _releaseDeletionClaim(claim);
      }
      rethrow;
    }
  }

  /// Deletes a downloaded cache entry belonging to the exact activated owner.
  ///
  /// The claim and deletion transactions both re-check the pinned logical
  /// session. A guest, unverified user, environment switch, account switch, or
  /// logout cannot delete another account's cached recording.
  static Future<void> deleteDownloadedRecordingFromCurrentUserCache(
    int id,
  ) async {
    const _SecureStorageRecordingUploadSessions sessions =
        _SecureStorageRecordingUploadSessions();
    _RecordingDeletionClaim? claim;
    try {
      await deleteDownloadedRecordingCacheForActivatedOwner(
        recordingId: id,
        sessions: sessions,
        deleteOwnedEntry: (
          int recordingId,
          RecordingCacheOwner owner,
          RecordingCacheSessionGuard requireSessionCurrent,
        ) async {
          claim = await _claimRecordingDeletion(
            recordingId,
            environment: owner.environment,
            session: null,
            requireRemoteSession: false,
            cacheOwner: owner,
            requirePinnedSessionCurrent: requireSessionCurrent,
            requireDownloadedCache: true,
          );
          await requireSessionCurrent();
          await _deleteClaimedRecordingLocally(
            claim!,
            requirePinnedSessionCurrent: requireSessionCurrent,
          );
          logger.i('Downloaded recording id $recordingId deleted from cache.');
        },
      );
    } catch (_) {
      if (claim != null) {
        await _releaseDeletionClaim(claim!);
      }
      rethrow;
    }
  }

  static Future<_RecordingDeletionClaim> _claimRecordingDeletion(
    int recordingId, {
    required String? environment,
    required RecordingUploadSession? session,
    required bool requireRemoteSession,
    RecordingCacheOwner? cacheOwner,
    RecordingCacheSessionGuard? requirePinnedSessionCurrent,
    bool requireDownloadedCache = false,
  }) async {
    if (recordingId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot delete a recording without a valid local id.',
      );
    }

    final Database db = await database;
    return db.transaction<_RecordingDeletionClaim>((Transaction txn) async {
      if (requirePinnedSessionCurrent != null) {
        await requirePinnedSessionCurrent();
      }
      final String scopeWhere;
      final List<Object?> scopeArgs;
      if (cacheOwner != null) {
        scopeWhere = 'id = ? AND env = ? AND userId = ? '
            "AND LOWER(TRIM(COALESCE(mail, ''))) = ? "
            '${requireDownloadedCache ? 'AND downloaded = 1 ' : ''}'
            '${requireDownloadedCache ? "AND ((path IS NOT NULL AND path <> '') OR EXISTS (" : ''}'
            '${requireDownloadedCache ? 'SELECT 1 FROM recordingParts cachePart ' : ''}'
            '${requireDownloadedCache ? 'WHERE cachePart.recordingId = recordings.id ' : ''}'
            '${requireDownloadedCache ? "AND cachePart.path IS NOT NULL AND cachePart.path <> ''))" : ''}';
        scopeArgs = <Object?>[
          recordingId,
          cacheOwner.environment,
          cacheOwner.userId,
          cacheOwner.normalizedEmail,
        ];
      } else {
        scopeWhere = environment == null ? 'id = ?' : 'id = ? AND env = ?';
        scopeArgs = <Object?>[
          recordingId,
          if (environment != null) environment,
        ];
      }
      final List<Map<String, Object?>> rows = await txn.query(
        'recordings',
        where: scopeWhere,
        whereArgs: scopeArgs,
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const RecordingUploadValidationException(
          'The recording no longer exists.',
        );
      }

      final Recording persistedRecording = Recording.fromJson(rows.first);
      if (requireRemoteSession && persistedRecording.BEId != null) {
        if (session == null) {
          throw FetchException(
            'Authentication is required to delete a remote recording.',
            401,
          );
        }
        if (persistedRecording.userId == null &&
            (persistedRecording.mail == null ||
                persistedRecording.mail!.trim().isEmpty)) {
          throw const RecordingUploadSessionChangedException();
        }
        validateRecordingSessionBinding(persistedRecording, session);
      }

      final int now = DateTime.now().millisecondsSinceEpoch;
      final int staleBefore = now - _deletionLeaseTimeout.inMilliseconds;
      final String leaseId =
          'delete:$recordingId:${DateTime.now().microsecondsSinceEpoch}:'
          '${_uploadKeyRandom.nextInt(1 << 32)}';
      if (requirePinnedSessionCurrent != null) {
        await requirePinnedSessionCurrent();
      }
      final int changed = await txn.rawUpdate(
        'UPDATE recordings '
        'SET sending = 1, uploadLease = ?, uploadLeaseUpdatedAt = ? '
        'WHERE $scopeWhere '
        'AND ('
        '  (COALESCE(sending, 0) = 0 '
        '    AND (uploadLease IS NULL OR TRIM(uploadLease) = ?)) '
        '  OR (COALESCE(sending, 0) = 1 '
        '    AND uploadLease LIKE ? '
        '    AND (uploadLeaseUpdatedAt IS NULL '
        '      OR uploadLeaseUpdatedAt < ?))'
        ')',
        <Object?>[
          leaseId,
          now,
          ...scopeArgs,
          '',
          'delete:%',
          staleBefore,
        ],
      );
      if (changed != 1) {
        throw StateError(
          'Cannot delete a recording while its upload is active.',
        );
      }

      final Recording recording = persistedRecording
        ..sending = true
        ..uploadLease = leaseId;
      final Set<String> paths = <String>{};
      if (recording.path != null && recording.path!.isNotEmpty) {
        paths.add(recording.path!);
      }
      final List<Map<String, Object?>> partRows = await txn.query(
        'recordingParts',
        columns: const <String>['path'],
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );
      for (final Map<String, Object?> row in partRows) {
        final String? path = row['path'] as String?;
        if (path != null && path.isNotEmpty) {
          paths.add(path);
        }
      }
      if (requirePinnedSessionCurrent != null) {
        await requirePinnedSessionCurrent();
      }
      return _RecordingDeletionClaim(
        recording: recording,
        leaseId: leaseId,
        filePaths: paths.toList(growable: false),
      );
    });
  }

  static Future<void> _deleteClaimedRecordingLocally(
    _RecordingDeletionClaim claim, {
    RecordingCacheSessionGuard? requirePinnedSessionCurrent,
  }) async {
    final int recordingId = claim.recording.id!;
    final Database db = await database;
    await db.transaction<void>((Transaction txn) async {
      // A stale delete claim can be superseded. Prove this exact worker still
      // owns the parent before touching any child rows; the transaction then
      // prevents a competing claimant from taking over mid-delete.
      final int verified = await txn.rawUpdate(
        'UPDATE recordings SET uploadLeaseUpdatedAt = ? '
        'WHERE id = ? AND uploadLease = ? AND COALESCE(sending, 0) = 1',
        <Object?>[
          DateTime.now().millisecondsSinceEpoch,
          recordingId,
          claim.leaseId,
        ],
      );
      if (verified != 1) {
        throw StateError(
          'Recording deletion ownership changed before local cleanup.',
        );
      }
      if (requirePinnedSessionCurrent != null) {
        await requirePinnedSessionCurrent();
      }
      await txn.rawDelete(
        'DELETE FROM DetectedDialects WHERE filteredPartLocalId IN ('
        'SELECT id FROM FilteredRecordingParts WHERE recordingLocalId = ?'
        ')',
        <Object?>[recordingId],
      );
      await txn.delete(
        'FilteredRecordingParts',
        where: 'recordingLocalId = ?',
        whereArgs: <Object?>[recordingId],
      );
      await txn.delete(
        'Dialects',
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );
      await txn.delete(
        'images',
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );
      await txn.delete(
        'recordingParts',
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );
      if (requirePinnedSessionCurrent != null) {
        await requirePinnedSessionCurrent();
      }
      final int changed = await txn.delete(
        'recordings',
        where: 'id = ? AND uploadLease = ?',
        whereArgs: <Object?>[recordingId, claim.leaseId],
      );
      if (changed != 1) {
        throw StateError(
          'Recording deletion ownership changed before local commit.',
        );
      }
    });

    for (final String path in claim.filePaths) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // The durable rows are already gone. A missing/stale cache file does
        // not make the deletion unsafe to report as completed.
      }
    }
  }

  static Future<void> _releaseDeletionClaim(
    _RecordingDeletionClaim claim,
  ) async {
    try {
      final Database db = await database;
      await db.rawUpdate(
        'UPDATE recordings SET sending = 0, uploadLease = NULL, '
        'uploadLeaseUpdatedAt = NULL '
        'WHERE id = ? AND uploadLease = ?',
        <Object?>[claim.recording.id, claim.leaseId],
      );
    } catch (error, stackTrace) {
      logger.e(
        'Failed to release recording deletion claim',
        error: error,
        stackTrace: stackTrace,
      );
      Sentry.captureException(error, stackTrace: stackTrace);
    }
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
      final int? recordingId = recording.id;
      if (recordingId == null || recordingId <= 0) {
        throw const RecordingUploadValidationException(
          'Cannot update a recording without a valid local id.',
        );
      }
      await _updateRecordingFields(
        recordingId,
        recordingMetadataUpdateFields(recording),
      );
    } catch (e, stackTrace) {
      logger.e('Failed to update recording', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<void> updateRecordingCacheState(Recording recording) async {
    final int? recordingId = recording.id;
    if (recordingId == null || recordingId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update recording cache state without a valid local id.',
      );
    }
    await _updateRecordingFields(
      recordingId,
      <String, Object?>{
        'path': recording.path,
        'downloaded': recording.downloaded ? 1 : 0,
      },
    );
  }

  static Future<void> updateRecordingDuration(Recording recording) async {
    final int? recordingId = recording.id;
    if (recordingId == null || recordingId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update recording duration without a valid local id.',
      );
    }
    await _updateRecordingFields(
      recordingId,
      <String, Object?>{'totalSeconds': recording.totalSeconds},
    );
  }

  static Future<void> updateRecordingOwnerMail(
    int recordingId,
    String mail,
  ) async {
    if (recordingId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update recording ownership without a valid local id.',
      );
    }
    await _updateRecordingFields(
      recordingId,
      <String, Object?>{'mail': mail},
    );
  }

  static Future<void> _updateRecordingFields(
    int recordingId,
    Map<String, Object?> fields,
  ) async {
    final Database db = await database;
    final int changed = await db.update(
      'recordings',
      fields,
      where: 'id = ? AND (uploadLease IS NULL OR TRIM(uploadLease) = ?) '
          'AND (COALESCE(parentUploadAttempted, 0) = 0 OR BEId IS NOT NULL)',
      whereArgs: <Object?>[recordingId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Recording is missing or its upload lease became active.',
      );
    }
  }

  static Future<void> updateRecordingPart(RecordingPart recordingPart) async {
    try {
      final int? partId = recordingPart.id;
      if (partId == null || partId <= 0) {
        throw const RecordingUploadValidationException(
          'Cannot update a recording part without a valid local id.',
        );
      }
      await _updateRecordingPartFields(
        partId,
        recordingPartContentUpdateFields(recordingPart),
      );
    } catch (e, stackTrace) {
      logger.e('Failed to update recording part',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      rethrow;
    }
  }

  static Future<void> updateRecordingPartCacheState(
    RecordingPart recordingPart,
  ) async {
    final int? partId = recordingPart.id;
    if (partId == null || partId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update recording-part cache state without a valid local id.',
      );
    }
    final Database db = await database;
    final int changed = await db.update(
      'recordingParts',
      recordingPartCacheUpdateFields(recordingPart),
      where: 'id = ? AND BEId IS NOT NULL AND COALESCE(sent, 0) = 1 '
          'AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = recordingParts.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ')',
      whereArgs: <Object?>[partId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Recording part is missing, upload-owned, or has no durable remote '
        'cache identity.',
      );
    }
  }

  static Future<void> _updateRecordingPartRemoteCacheState(
    RecordingPart recordingPart,
  ) async {
    final int? partId = recordingPart.id;
    final int? backendPartId = recordingPart.BEId;
    final int? backendRecordingId = recordingPart.backendRecordingId;
    final String? path = recordingPart.path;
    if (partId == null ||
        partId <= 0 ||
        backendPartId == null ||
        backendPartId <= 0 ||
        backendRecordingId == null ||
        backendRecordingId <= 0 ||
        path == null ||
        path.isEmpty) {
      throw const RecordingUploadValidationException(
        'Cannot reconcile recording-part cache state without complete local '
        'and remote identities.',
      );
    }

    final Database db = await database;
    final int changed = await db.update(
      'recordingParts',
      <String, Object?>{
        ...recordingPartCacheUpdateFields(recordingPart),
        'sent': 1,
        'sending': 0,
        'uploadAttempted': 1,
      },
      where: 'id = ? AND BEId = ? AND backendRecordingId = ? '
          'AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = recordingParts.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ')',
      whereArgs: <Object?>[
        partId,
        backendPartId,
        backendRecordingId,
        '',
      ],
    );
    if (changed != 1) {
      throw StateError(
        'Recording-part remote cache identity changed concurrently.',
      );
    }
  }

  static Future<void> _updateRecordingPartFields(
    int partId,
    Map<String, Object?> fields,
  ) async {
    final Database db = await database;
    final int changed = await db.update(
      'recordingParts',
      fields,
      where: 'id = ? AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = recordingParts.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ') AND COALESCE(uploadAttempted, 0) = 0',
      whereArgs: <Object?>[partId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Recording part is missing, upload-owned, or already has an '
        'ambiguous remote attempt.',
      );
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
        fetchedFilteredRecordingParts!.isEmpty) {
      return;
    }

    final RecordingUploadSession? session = _fetchedRecordingSession;
    if (session == null) {
      throw const RecordingUploadSessionChangedException();
    }
    const _SecureStorageRecordingUploadSessions sessionProvider =
        _SecureStorageRecordingUploadSessions();
    await _requireRecordingSessionCurrent(sessionProvider, session);

    // Build recording BEId -> local id map
    final localRecs = await _getRecordingsForCapturedSession(session);
    final Map<int, int> recBeToLocal = {
      for (final r in localRecs)
        if (r.BEId != null && r.id != null) r.BEId!: r.id!
    };

    // Insert/update filtered parts first
    final Map<(int, int), int> frpBeToLocal = <(int, int), int>{};
    for (final frp in fetchedFilteredRecordingParts!) {
      await _requireRecordingSessionCurrent(sessionProvider, session);
      final int? recordingBackendId = frp.recordingBEID;
      final int? recordingLocalId =
          recordingBackendId == null ? null : recBeToLocal[recordingBackendId];
      if (recordingLocalId == null) {
        logger.w(
          'Skipping filtered part ${frp.BEId}: no current-environment '
          'recording exists for backend recording $recordingBackendId.',
        );
        continue;
      }

      frp.recordingLocalId = recordingLocalId;
      final id = await insertFilteredRecordingPart(frp);
      if (frp.BEId != null && id > 0) {
        frpBeToLocal[(recordingLocalId, frp.BEId!)] = id;
      }
    }

    // Resolve filtered-part parents after every row has a local id; backend
    // payload order is not guaranteed to put a parent before its child.
    for (final frp in fetchedFilteredRecordingParts!) {
      await _requireRecordingSessionCurrent(sessionProvider, session);
      final int? parentBackendId = frp.parentBEID;
      final int? recordingLocalId = frp.recordingLocalId;
      final int? localId = frp.BEId == null || recordingLocalId == null
          ? null
          : frpBeToLocal[(recordingLocalId, frp.BEId!)];
      if (parentBackendId == null || localId == null) continue;
      final int? parentLocalId =
          frpBeToLocal[(recordingLocalId!, parentBackendId)];
      if (parentLocalId == null || frp.parentLocalId == parentLocalId) continue;
      frp
        ..id = localId
        ..parentLocalId = parentLocalId;
      await updateFilteredRecordingPart(frp);
    }

    // Insert/update detected dialects, linked to local FRP ids
    if (fetchedDetectedDialects != null &&
        fetchedDetectedDialects!.isNotEmpty) {
      for (final dd in fetchedDetectedDialects!) {
        await _requireRecordingSessionCurrent(sessionProvider, session);
        final int? filteredPartBackendId = dd.filteredPartBEID;
        int? recordingLocalId =
            dd.recordingBEID == null ? null : recBeToLocal[dd.recordingBEID!];
        if (recordingLocalId == null && filteredPartBackendId != null) {
          final Set<int> candidateRecordings = frpBeToLocal.keys
              .where((key) => key.$2 == filteredPartBackendId)
              .map((key) => key.$1)
              .toSet();
          if (candidateRecordings.length == 1) {
            recordingLocalId = candidateRecordings.single;
          }
        }
        final int? filteredPartLocalId =
            filteredPartBackendId == null || recordingLocalId == null
                ? null
                : frpBeToLocal[(recordingLocalId, filteredPartBackendId)];
        if (filteredPartLocalId == null) {
          logger.w(
            'Skipping detected dialect ${dd.BEId}: no current-environment '
            'filtered part exists for backend part $filteredPartBackendId.',
          );
          continue;
        }
        dd.filteredPartLocalId = filteredPartLocalId;
        await insertDetectedDialect(dd);
      }
    }
    await _requireRecordingSessionCurrent(sessionProvider, session);
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

  static Future<int> downloadRecordingByLocalId(
    int localRecordingId, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    return _downloadRecordingByLocalId(
      localRecordingId,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Future<int> downloadRecordingByBackendId(
    int backendRecordingId, {
    DownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    return _downloadRecordingByBackendId(
      backendRecordingId,
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

    logger.i('Reserved a concatenated recording path.');

    final Recording? recording =
        await getRecordingFromDbByIdNoMail(recordingId);
    if (recording == null) {
      logger.w('Recording $recordingId not found when concatenating parts.');
      return;
    }
    recording
      ..path = outputPath
      ..downloaded = true;
    await updateRecordingCacheState(recording);

    logger.i('Concatenated recording parts for id: $recordingId.');
  }

  static Future<Database> initDb() async {
    return openDatabase('soundNew.db', version: 17,
        onCreate: (Database db, int version) async {
      await db.execute('''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY,
        userId INTEGER,
        BEId INTEGER,
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
        uploadKey TEXT UNIQUE,
        uploadLease TEXT,
        uploadLeaseUpdatedAt INTEGER,
        parentUploadAttempted INTEGER DEFAULT 0,
        uploadDeviceId TEXT,
        captureReviewed INTEGER NOT NULL DEFAULT 1,
        totalSeconds REAL,
        partCount INTEGER,
        env STRING DEFAULT 'prod'
      )
      ''');
      await db.execute('''
      CREATE TABLE recordingParts(
        id INTEGER PRIMARY KEY,
        BEId INTEGER,
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
        uploadAttempted INTEGER DEFAULT 0,
        uploadKey TEXT UNIQUE,
        uploadContentSha256 TEXT,
        uploadContentBytes INTEGER,
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
        read INTEGER DEFAULT 0,
        ownerUserId TEXT NOT NULL,
        env TEXT NOT NULL,
        providerMessageId TEXT
      )
      ''');
      await db.execute('''
      CREATE TABLE Dialects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        BEID INTEGER,
        recordingId INTEGER,
        recordingBEID INTEGER,
        uploadKey TEXT UNIQUE,
        uploadAttempted INTEGER DEFAULT 0,
        userGuessDialect TEXT,
        adminDialect TEXT,
        startDate TEXT,
        endDate TEXT
      )
      ''');
      await db.execute('''
    CREATE TABLE FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
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
      BEId INTEGER,
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
      await _createScopedBackendIdIndexes(db);
      await _createNotificationScopeIndex(db);
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
      BEId INTEGER,
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
      BEId INTEGER,
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
      if (oldVersion <= 12) {
        await _ensureColumn(db, 'recordings', 'uploadLease', 'TEXT');
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 13) {
        await _ensureColumn(db, 'recordings', 'userId', 'INTEGER');
        await _ensureColumn(db, 'recordings', 'uploadKey', 'TEXT');
        await _ensureColumn(
          db,
          'recordings',
          'uploadLeaseUpdatedAt',
          'INTEGER',
        );
        await _ensureColumn(db, 'recordingParts', 'uploadKey', 'TEXT');
        await _backfillUploadKeys(db);
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_recordings_upload_key ON recordings(uploadKey)',
        );
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_recording_parts_upload_key ON recordingParts(uploadKey)',
        );
        // No worker from the previous schema can own a timestamped lease.
        // Clear legacy flags once so new workers can acquire safely.
        await db.rawUpdate(
          'UPDATE recordings SET sending = 0, uploadLease = NULL, '
          'uploadLeaseUpdatedAt = NULL WHERE COALESCE(sending, 0) = 1',
        );
        await db.rawUpdate(
          'UPDATE recordingParts SET sending = 0 '
          'WHERE COALESCE(sending, 0) = 1',
        );
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 14) {
        await _ensureColumn(
          db,
          'recordings',
          'parentUploadAttempted',
          'INTEGER DEFAULT 0',
        );
        await _ensureColumn(db, 'recordings', 'uploadDeviceId', 'TEXT');
        await _ensureColumn(
          db,
          'recordingParts',
          'uploadAttempted',
          'INTEGER DEFAULT 0',
        );
        await _ensureColumn(db, 'Dialects', 'uploadKey', 'TEXT');
        await _ensureColumn(
          db,
          'Dialects',
          'uploadAttempted',
          'INTEGER DEFAULT 0',
        );
        await db.rawUpdate(
          'UPDATE recordings SET parentUploadAttempted = 1 '
          'WHERE BEId IS NOT NULL',
        );
        await db.rawUpdate(
          'UPDATE recordingParts SET uploadAttempted = 1 '
          'WHERE BEId IS NOT NULL',
        );
        await db.rawUpdate(
          'UPDATE Dialects SET uploadAttempted = 1 '
          'WHERE BEID IS NOT NULL',
        );
        await _backfillUploadKeys(db);
        await _rebuildUploadTablesForScopedBackendIds(db);
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS '
          'idx_dialects_upload_key ON Dialects(uploadKey)',
        );
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 15) {
        await _ensureColumn(
          db,
          'recordings',
          'captureReviewed',
          'INTEGER NOT NULL DEFAULT 1',
        );
        await db.rawUpdate(
          'UPDATE recordings SET captureReviewed = 1 '
          'WHERE captureReviewed IS NULL',
        );
        await db.setVersion(newVersion);
      }
      if (oldVersion <= 16) {
        // Legacy notification rows have no trustworthy owner. Keep both
        // columns nullable on upgraded databases so those rows remain
        // quarantined by every owner-scoped query instead of guessing.
        await _ensureColumn(db, 'Notifications', 'ownerUserId', 'TEXT');
        await _ensureColumn(db, 'Notifications', 'env', 'TEXT');
        await _ensureColumn(
          db,
          'Notifications',
          'providerMessageId',
          'TEXT',
        );
        await _ensureColumn(
          db,
          'recordingParts',
          'uploadContentSha256',
          'TEXT',
        );
        await _ensureColumn(
          db,
          'recordingParts',
          'uploadContentBytes',
          'INTEGER',
        );
        await _createNotificationScopeIndex(db);
        await db.setVersion(newVersion);
      }
    });
  }

  static Future<void> runPostMigrationBackfills() async {
    if (!_durationBackfillNeeded) return;
    try {
      await fetchAndUpdateDurationsFromBackend();
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
    return Config.hasBasicInternet;
  }

  static Future<void> insertNotification(RemoteMessage message) async {
    final NotificationCacheIsolation isolation = _notificationCacheIsolation();
    await isolation.persist(
      insert: (NotificationCacheScope scope) async {
        final Database db = await database;
        String? preferredLanguageCode;
        try {
          preferredLanguageCode = Config.StringFromLanguagePreference(
            await Config.getLanguagePreference(),
          );
        } catch (_) {
          // A preference read cannot suppress an otherwise valid push. The
          // pure normalizer keeps a deterministic language fallback order.
        }
        final Map<String, Object> values = notificationPersistenceValues(
          notificationTitle: message.notification?.title,
          notificationBody: message.notification?.body,
          messageType: message.messageType,
          data: message.data,
          sentTime: message.sentTime,
          ownerUserId: scope.ownerUserId,
          environment: scope.environment,
          providerMessageId: message.messageId,
          preferredLanguageCode: preferredLanguageCode,
        );
        final NotificationRetentionDeletePlan retention =
            notificationRetentionDeletePlan(
          ownerUserId: scope.ownerUserId,
          environment: scope.environment,
        );
        return db.transaction<int>((Transaction transaction) async {
          final int insertedId = await transaction.insert(
            'Notifications',
            values,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await transaction.delete(
            'Notifications',
            where: retention.where,
            whereArgs: retention.whereArgs,
          );
          return insertedId;
        });
      },
      removeInserted: (
        NotificationCacheScope scope,
        int insertedId,
      ) async {
        final Database db = await database;
        await db.delete(
          'Notifications',
          where: 'id = ? AND ownerUserId = ? AND env = ?',
          whereArgs: <Object?>[
            insertedId,
            scope.ownerUserId,
            scope.environment,
          ],
        );
      },
    );
    await refreshUnreadNotificationCount();
  }

  // New helper method to insert a custom local notification.
  static Future<void> sendLocalNotification(
      String title, String message) async {
    await showLocalNotification(title, message);
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
    final List<Map<String, Object?>> notifications =
        await _notificationCacheIsolation().readList<Map<String, Object?>>(
      read: (NotificationCacheScope scope) async {
        final Database db = await database;
        return db.query(
          'Notifications',
          where: 'ownerUserId = ? AND env = ?',
          whereArgs: <Object?>[scope.ownerUserId, scope.environment],
          orderBy: 'receivedAt DESC',
        );
      },
    );
    final List<NotificationItem> messages = <NotificationItem>[];
    for (final Map<String, Object?> notification in notifications) {
      messages.add(NotificationItem(
        title: notification['title'] as String? ?? '',
        message: notification['body'] as String? ?? '',
        time: notification['receivedAt'] as String? ?? '',
        unread: notification['read'] == 0,
      ));
    }
    return messages;
  }

  static Future<int> getUnreadNotificationCount() async {
    return _notificationCacheIsolation().readCount(
      read: (NotificationCacheScope scope) async {
        final Database db = await database;
        final List<Map<String, Object?>> result = await db.rawQuery(
          'SELECT COUNT(*) AS unreadCount FROM Notifications '
          'WHERE ownerUserId = ? AND env = ? AND read = 0',
          <Object?>[scope.ownerUserId, scope.environment],
        );
        return Sqflite.firstIntValue(result) ?? 0;
      },
    );
  }

  static Future<void> refreshUnreadNotificationCount() async {
    unreadNotificationCount.value = await getUnreadNotificationCount();
  }

  static Future<void> markAllNotificationsAsRead() async {
    await _notificationCacheIsolation().mutate(
      mutation: (NotificationCacheScope scope) async {
        final Database db = await database;
        await db.update(
          'Notifications',
          <String, Object?>{'read': 1},
          where: 'ownerUserId = ? AND env = ? AND read = 0',
          whereArgs: <Object?>[scope.ownerUserId, scope.environment],
        );
      },
    );
    await refreshUnreadNotificationCount();
  }

  static Future<void> deleteAllNotificationsForCurrentUser() async {
    await _notificationCacheIsolation().mutate(
      mutation: (NotificationCacheScope scope) async {
        final Database db = await database;
        await db.delete(
          'Notifications',
          where: 'ownerUserId = ? AND env = ?',
          whereArgs: <Object?>[scope.ownerUserId, scope.environment],
        );
      },
    );
    await refreshUnreadNotificationCount();
  }

  static Future<Recording?> getRecordingFromDbById(int recordingId) async {
    final RecordingOwnerSnapshot ownerSnapshot =
        await _captureRecordingOwnerSnapshot();
    final List<Recording> recordings =
        await _getVisibleRecordingsForOwnerSnapshot(
      ownerSnapshot,
      recordingId: recordingId,
    );
    return recordings.isEmpty ? null : recordings.single;
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

  static Future<List<Recording>> _getRecordingsForOwnerSnapshot(
    RecordingOwnerSnapshot snapshot, {
    int? recordingId,
  }) async {
    final Database db = await database;
    final String idPredicate = recordingId == null ? '' : 'id = ? AND ';
    final List<Object?> whereArgs = <Object?>[
      if (recordingId != null) recordingId,
    ];
    late final String where;
    if (snapshot.isGuest) {
      where = '${idPredicate}env = ? AND userId IS NULL '
          'AND (mail IS NULL OR TRIM(mail) = ?) '
          'AND captureReviewed = 1 '
          'AND COALESCE(sent, 0) = 0 AND BEId IS NULL';
      whereArgs.addAll(<Object?>[snapshot.environment, '']);
    } else {
      where = '${idPredicate}mail = ? AND env = ? '
          'AND captureReviewed = 1 '
          'AND (userId IS NULL OR userId = ?)';
      whereArgs.addAll(<Object?>[
        snapshot.accountEmail,
        snapshot.environment,
        int.parse(snapshot.userId!),
      ]);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'recordings',
      where: where,
      whereArgs: whereArgs,
    );
    return rows.map(Recording.fromJson).toList(growable: false);
  }

  static Future<List<IncompleteRecordingUpload>> findIncompleteUploads({
    int? recordingId,
    bool includeBackendCheck = true,
  }) async {
    final RecordingOwnerSnapshot ownerSnapshot =
        await _captureRecordingOwnerSnapshot();
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

    late final List<Recording> recordings;
    try {
      recordings = await _getRecordingsForOwnerSnapshot(
        ownerSnapshot,
        recordingId: recordingId,
      );
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    } on RecordingUploadSessionChangedException {
      rethrow;
    } catch (e, stackTrace) {
      logger.w('Could not load recordings for incomplete upload check: $e',
          error: e, stackTrace: stackTrace);
      return const <IncompleteRecordingUpload>[];
    }

    if (recordings.isEmpty) {
      return const <IncompleteRecordingUpload>[];
    }

    final BackendIncompleteUploadSnapshot backendSnapshot =
        includeBackendCheck && !ownerSnapshot.isGuest
            ? await _fetchIncompleteRecordingsFromBE(ownerSnapshot)
            : const BackendIncompleteUploadSnapshot.unavailable();
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

    final List<IncompleteRecordingUpload> result =
        <IncompleteRecordingUpload>[];

    for (final Recording recording in recordings) {
      if (recording.id == null || recording.sending) continue;

      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      final List<RecordingPart> parts = await getPartsByRecordingId(
        recording.id!,
      );
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

      if (backendSnapshot.authoritativelyConfirmsComplete(recording.BEId)) {
        continue;
      }
      final BackendIncompleteUploadEntry? backend =
          backendSnapshot.entryFor(recording.BEId);

      final int localExpected =
          recording.partCount != null && recording.partCount! > 0
              ? recording.partCount!
              : parts.length;
      final int expectedParts = backend?.expectedPartsCount ?? localExpected;
      final int localUploadedParts = parts
          .where(
            (RecordingPart part) => localPartCountsAsUploaded(
              sent: part.sent,
              backendPartId: part.BEId,
              backendRecordingId: part.backendRecordingId,
              expectedBackendRecordingId: recording.BEId,
            ),
          )
          .length;
      final int uploadedParts =
          backend?.uploadedPartsCount ?? localUploadedParts;
      final bool backendSaysIncomplete = backend != null &&
          (!backend.hasExactPartCounts || expectedParts > uploadedParts);
      final bool localRowsAreMissing = parts.length < expectedParts;
      final bool localSaysIncomplete = localRowsAreMissing ||
          ((recording.sent || recording.BEId != null) &&
              localUploadedParts != parts.length);
      final bool needsAttention = aggregateUploadNeedsAttention(
        backendExpectedPartsCount: backend?.expectedPartsCount,
        backendUploadedPartsCount: backend?.uploadedPartsCount,
        backendSaysIncomplete: backendSaysIncomplete,
        localSaysIncomplete: localSaysIncomplete,
      );

      if (!needsAttention) {
        continue;
      }
      final bool aggregateCanBeRetried = incompleteAggregateCanBeRetried(
        localPartsCount: parts.length,
        expectedPartsCount: expectedParts,
      );

      result.add(
        IncompleteRecordingUpload(
          recording: recording,
          expectedPartsCount: expectedParts,
          uploadedPartsCount: uploadedParts,
          localPartsCount: parts.length,
          hasExactBackendPartCounts: backend?.hasExactPartCounts ?? false,
          resendablePartsCount: aggregateCanBeRetried
              ? _countResendableMissingParts(
                  parts,
                  backend?.uploadedBackendPartIds,
                  reconcileAllBackendParts:
                      backend?.requiresFullPartReconciliation ?? false,
                )
              : 0,
          reconcileAllBackendParts:
              backend?.requiresFullPartReconciliation ?? false,
          uploadedBackendPartIds: backend?.uploadedBackendPartIds,
          ownerSnapshot: ownerSnapshot,
        ),
      );
    }

    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    return result;
  }

  static Future<void> resendMissingPartsForRecording(
    int recordingId, {
    Set<int>? uploadedBackendPartIds,
  }) async {
    // Compatibility entry point: never trust backend part ids retained by an
    // older caller. Re-run the pinned discovery and use the identity carried by
    // its result before touching SQLite.
    final List<IncompleteRecordingUpload> currentIssues =
        await findIncompleteUploads(recordingId: recordingId);
    if (currentIssues.isEmpty) {
      throw const RecordingUploadValidationException(
        'The recording has no incomplete upload in the current session.',
      );
    }
    await currentIssues.single.resendMissingParts();
  }

  static Future<void> _resendMissingPartsForRecording(
    IncompleteRecordingUpload issue,
  ) async {
    final RecordingOwnerSnapshot ownerSnapshot = issue._ownerSnapshot;
    final int? recordingId = issue.recording.id;
    final String recordingUploadKey = (issue.recording.uploadKey ?? '').trim();
    if (recordingId == null || recordingId <= 0 || recordingUploadKey.isEmpty) {
      throw const RecordingUploadValidationException(
        'The incomplete recording has no durable local identity.',
      );
    }

    // The prompt can remain open while the user logs out, changes account, or
    // switches environment. Check its captured identity before opening the DB
    // and again around every mutation.
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    final Database db = await database;
    bool hasResendablePart = false;
    await db.transaction<void>((Transaction txn) async {
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);

      final List<String> identityPredicates = <String>[
        'r.id = ?',
        'r.uploadKey = ?',
        'r.env = ?',
      ];
      final List<Object?> identityArgs = <Object?>[
        recordingId,
        recordingUploadKey,
        ownerSnapshot.environment,
      ];
      final int? capturedBackendId = issue.recording.BEId;
      if (capturedBackendId == null) {
        identityPredicates.add('r.BEId IS NULL');
      } else {
        identityPredicates.add('r.BEId = ?');
        identityArgs.add(capturedBackendId);
      }
      if (ownerSnapshot.isGuest) {
        identityPredicates.addAll(<String>[
          'r.userId IS NULL',
          "(r.mail IS NULL OR TRIM(r.mail) = '')",
          'COALESCE(r.sent, 0) = 0',
        ]);
      } else {
        identityPredicates.addAll(<String>[
          'r.mail = ?',
          '(r.userId IS NULL OR r.userId = ?)',
        ]);
        identityArgs.addAll(<Object?>[
          ownerSnapshot.accountEmail,
          int.parse(ownerSnapshot.userId!),
        ]);
      }

      final String identityWhere = identityPredicates.join(' AND ');
      final List<Map<String, Object?>> parents = await txn.rawQuery(
        'SELECT r.id FROM recordings r WHERE $identityWhere LIMIT 1',
        identityArgs,
      );
      if (parents.length != 1) {
        throw const RecordingUploadSessionChangedException();
      }
      final List<Map<String, Object?>> rows = await txn.query(
        'recordingParts',
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );

      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      for (final Map<String, Object?> row in rows) {
        final RecordingPart part = RecordingPart.fromJson(row);
        if (!_shouldResendMissingPart(
          part,
          issue.uploadedBackendPartIds,
          reconcileAllBackendParts: issue.reconcileAllBackendParts,
        )) {
          continue;
        }
        hasResendablePart = true;
        await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
        final int changed = await txn.update(
          'recordingParts',
          <String, Object?>{
            'sent': 0,
            'sending': 0,
            // Keep an ambiguous backend id. The aggregate upload service will
            // reconcile it with the captured session before replacing it.
          },
          where: 'id = ? AND recordingId = ? AND EXISTS ('
              'SELECT 1 FROM recordings r WHERE $identityWhere '
              'AND r.id = recordingParts.recordingId '
              'AND (r.uploadLease IS NULL OR TRIM(r.uploadLease) = ?)'
              ')',
          whereArgs: <Object?>[
            part.id,
            recordingId,
            ...identityArgs,
            '',
          ],
        );
        if (changed != 1) {
          throw StateError(
            'Recording part changed while preparing its retry.',
          );
        }
      }
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    });

    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    if (!hasResendablePart) return;
    final List<Recording> recordings = await _getRecordingsForOwnerSnapshot(
      ownerSnapshot,
      recordingId: recordingId,
    );
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    if (recordings.length != 1 ||
        (recordings.single.uploadKey ?? '').trim() != recordingUploadKey ||
        recordings.single.BEId != issue.recording.BEId) {
      throw const RecordingUploadValidationException(
        'The incomplete recording identity changed before retry.',
      );
    }
    await sendRecordingNew(recordings.single, const <RecordingPart>[]);
  }

  static int _countResendableMissingParts(
    List<RecordingPart> parts,
    Set<int>? uploadedBackendPartIds, {
    required bool reconcileAllBackendParts,
  }) {
    return parts
        .where((RecordingPart part) => _shouldResendMissingPart(
              part,
              uploadedBackendPartIds,
              reconcileAllBackendParts: reconcileAllBackendParts,
            ))
        .length;
  }

  static bool _shouldResendMissingPart(
    RecordingPart part,
    Set<int>? uploadedBackendPartIds, {
    required bool reconcileAllBackendParts,
  }) {
    return incompletePartCanBeRetried(
      sent: part.sent,
      sending: part.sending,
      backendPartId: part.BEId,
      localPath: part.path,
      uploadedBackendPartIds: uploadedBackendPartIds,
      reconcileAllBackendParts: reconcileAllBackendParts,
    );
  }

  static int? _readInt(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final String key in keys) {
      if (!map.containsKey(key)) continue;
      final dynamic value = map[key];
      if (value is int) return value;
      if (value is num) {
        if (value.isFinite && value == value.truncateToDouble()) {
          return value.toInt();
        }
        continue;
      }
      if (value is String) {
        final int? parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static Future<BackendIncompleteUploadSnapshot>
      _fetchIncompleteRecordingsFromBE(
    RecordingOwnerSnapshot ownerSnapshot,
  ) async {
    if (ownerSnapshot.isGuest) {
      return const BackendIncompleteUploadSnapshot.unavailable();
    }
    await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
    if (!await Config.hasBasicInternet) {
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      return const BackendIncompleteUploadSnapshot.unavailable();
    }

    try {
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      final response = await _recordingsApi.fetchIncompleteRecordings(
        accessToken: ownerSnapshot.accessToken,
        host: ownerSnapshot.backendHost,
      );
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      if (response.statusCode != 200 && response.statusCode != 204) {
        logger.i(
            'Incomplete recordings check skipped with status ${response.statusCode}.');
        return const BackendIncompleteUploadSnapshot.unavailable();
      }

      final dynamic decoded = response.statusCode == 204
          ? null
          : response.data is String
              ? jsonDecode(response.data as String)
              : response.data;
      final BackendIncompleteUploadSnapshot snapshot =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: response.statusCode,
        payload: decoded,
      );
      await _requireRecordingOwnerSnapshotCurrent(ownerSnapshot);
      return snapshot;
    } on RecordingUploadSessionChangedException {
      rethrow;
    } catch (e, stackTrace) {
      logger.w('Failed to fetch incomplete recordings: $e',
          error: e, stackTrace: stackTrace);
      return const BackendIncompleteUploadSnapshot.unavailable();
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

    // Group parts by local recordingId to make sure we send the parent
    // recording at most once. Rows without a valid local parent identity are
    // quarantined in place: they must never bypass aggregate validation by
    // uploading directly against a remembered backend parent id.
    final Map<int, List<Map<String, dynamic>>> byRecording =
        <int, List<Map<String, dynamic>>>{};
    for (final row in unsent) {
      final dynamic rawRecordingId = row['recordingId'];
      final int? recId;
      if (rawRecordingId is int) {
        recId = rawRecordingId;
      } else if (rawRecordingId is num &&
          rawRecordingId.isFinite &&
          rawRecordingId == rawRecordingId.truncateToDouble()) {
        recId = rawRecordingId.toInt();
      } else if (rawRecordingId is String) {
        recId = int.tryParse(rawRecordingId.trim());
      } else {
        recId = null;
      }
      if (recId == null || recId <= 0) {
        logger.w(
          'resendUnsentParts: quarantining orphan part ${row['id']} without '
          'a valid local recording parent.',
        );
        continue;
      }
      byRecording.putIfAbsent(recId, () => <Map<String, dynamic>>[]).add(row);
    }

    final List<Future<void>> tasks = <Future<void>>[];

    byRecording.forEach((int recId, List<Map<String, dynamic>> partRows) {
      tasks.add(() async {
        try {
          final Recording? recording = await getRecordingFromDbById(recId);

          if (recording == null) {
            logger.w(
              'resendUnsentParts: quarantining ${partRows.length} orphan '
              'part row(s) for missing local recording $recId.',
            );
            return;
          }

          // The upload service reloads and verifies the complete aggregate,
          // resumes an existing backend parent, and finalizes the parent only
          // after every persisted part is confirmed.
          await sendRecordingNew(recording, const <RecordingPart>[]);
        } catch (e, st) {
          logger.e('resendUnsentParts: failure in group for recordingId=$recId',
              error: e, stackTrace: st);
          Sentry.captureException(e, stackTrace: st);
          rethrow;
        }
      }());
    });

    await Future.wait(tasks, eagerError: false);
  }

  // Dialects
  static Future<void> _freezeAndRefreshBackendDialect(
    DatabaseExecutor executor,
    Dialect dialect,
  ) async {
    final int? dialectId = dialect.id;
    final int? backendDialectId = dialect.BEID;
    if (dialectId == null ||
        dialectId <= 0 ||
        backendDialectId == null ||
        backendDialectId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot freeze a backend dialect without complete identities.',
      );
    }
    final Map<String, dynamic> dialectJson = dialect.toJson();
    final int changed = await executor.update(
      'Dialects',
      <String, Object?>{
        // Admin assessment is response/cache state, not part of the POST body.
        'adminDialect': dialectJson['adminDialect'],
        'uploadAttempted': 1,
      },
      where: 'id = ? AND BEID = ? '
          'AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = Dialects.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ')',
      whereArgs: <Object?>[dialectId, backendDialectId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Dialect is missing or owned by an active workflow.',
      );
    }
    dialect.uploadAttempted = true;
  }

  static Future<int> insertDialect(Dialect dialect) async {
    final db = await database;

    logger.i(
      'Inserting dialect ${dialect.id} for recording ${dialect.recordingId}.',
    );
    if (dialect.BEID != null) {
      if (dialect.BEID! <= 0) {
        throw const RecordingUploadValidationException(
          'A backend dialect must have a positive backend id.',
        );
      }
      final Map<String, Object?> parent =
          await _requireCurrentEnvironmentRecordingParent(
        db,
        localRecordingId: dialect.recordingId,
        backendRecordingId: dialect.recordingBEID,
        environment: Config.hostEnvironment.name,
        childLabel: 'A backend dialect',
      );
      final int recordingId = parent['id'] as int;
      dialect
        ..recordingId = recordingId
        ..recordingBEID = parent['BEId'] as int;
      final List<Map<String, Object?>> existing = await db.query(
        'Dialects',
        columns: const <String>['id', 'uploadKey', 'uploadAttempted'],
        where: 'recordingId = ? AND BEID = ?',
        whereArgs: <Object?>[recordingId, dialect.BEID],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final bool uploadAttempted =
            (existing.first['uploadAttempted'] as int? ?? 0) == 1;
        dialect
          ..id = existing.first['id'] as int?
          ..uploadKey ??= existing.first['uploadKey'] as String?
          ..uploadAttempted = uploadAttempted;
        if (!uploadAttempted) {
          await updateDialect(dialect);
        }
        await _freezeAndRefreshBackendDialect(db, dialect);
        return dialect.id!;
      }
    }
    if (dialect.BEID != null) {
      dialect.uploadAttempted = true;
    }
    dialect.uploadKey ??= _newUploadKey('dialect');
    int id = await db.insert("Dialects", dialect.toJson());
    dialect.id = id;
    logger.i('Dialect ${dialect.id} inserted.');
    return id;
  }

  static Future<void> updateDialect(Dialect dialect) async {
    final int? dialectId = dialect.id;
    if (dialectId == null || dialectId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update a dialect without a valid local id.',
      );
    }
    final db = await database;
    final Map<String, dynamic> dialectJson = dialect.toJson();
    final int changed = await db.update(
      'Dialects',
      <String, Object?>{
        'userGuessDialect': dialectJson['userGuessDialect'],
        'adminDialect': dialectJson['adminDialect'],
        'startDate': dialectJson['startDate'],
        'endDate': dialectJson['endDate'],
      },
      where: 'id = ? AND COALESCE(uploadAttempted, 0) = 0 '
          'AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = Dialects.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ')',
      whereArgs: <Object?>[dialectId, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Dialect is missing or already has an ambiguous remote attempt.',
      );
    }
    logger.i('Dialect ${dialect.id} updated.');
  }

  static Future<void> deleteDialect(int id) async {
    if (id <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot delete a dialect without a valid local id.',
      );
    }
    final db = await database;
    final int changed = await db.delete(
      'Dialects',
      where: 'id = ? AND BEID IS NULL '
          'AND COALESCE(uploadAttempted, 0) = 0 '
          'AND NOT EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = Dialects.recordingId '
          'AND r.uploadLease IS NOT NULL '
          'AND TRIM(r.uploadLease) <> ?'
          ')',
      whereArgs: <Object?>[id, ''],
    );
    if (changed != 1) {
      throw StateError(
        'Dialect is missing, upload-owned, or already has a remote attempt.',
      );
    }
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
    final List<Map<String, dynamic>> results = await db.rawQuery(
      'SELECT d.* FROM Dialects d '
      'JOIN recordings r ON r.id = d.recordingId '
      'WHERE d.recordingBEID = ? AND r.env = ?',
      <Object?>[recordingBEID, Config.hostEnvironment.name],
    );
    return List.generate(results.length, (i) => Dialect.fromJson(results[i]));
  }

  static Future<void> _validateFilteredRecordingPartParent(
    DatabaseExecutor executor,
    FilteredRecordingPart frp,
  ) async {
    final Map<String, Object?> recording =
        await _requireCurrentEnvironmentRecordingParent(
      executor,
      localRecordingId: frp.recordingLocalId,
      backendRecordingId: frp.recordingBEID,
      environment: Config.hostEnvironment.name,
      childLabel: 'A backend filtered recording part',
    );
    final int recordingLocalId = recording['id'] as int;
    final int recordingBackendId = recording['BEId'] as int;
    frp
      ..recordingLocalId = recordingLocalId
      ..recordingBEID = recordingBackendId;

    final int? parentLocalId = frp.parentLocalId;
    final int? parentBackendId = frp.parentBEID;
    if (parentLocalId == null && parentBackendId == null) return;
    if (parentLocalId != null && parentLocalId <= 0) {
      throw const RecordingUploadValidationException(
        'A filtered recording part has an invalid local filtered parent id.',
      );
    }
    if (parentBackendId != null && parentBackendId <= 0) {
      throw const RecordingUploadValidationException(
        'A filtered recording part has an invalid backend filtered parent id.',
      );
    }
    // Backend payload order is not stable. Keep the scoped backend parent id
    // on first insert and resolve/validate its local id in the second pass.
    if (parentLocalId == null) return;

    final List<Map<String, Object?>> parents = await executor.query(
      'FilteredRecordingParts',
      columns: const <String>['id', 'BEId'],
      where: 'recordingLocalId = ? AND id = ?',
      whereArgs: <Object?>[
        recordingLocalId,
        parentLocalId,
      ],
      limit: 1,
    );
    if (parents.isEmpty) {
      throw const RecordingUploadValidationException(
        'A filtered recording part has no parent under the same recording.',
      );
    }
    final int? persistedParentBackendId = parents.first['BEId'] as int?;
    if (persistedParentBackendId == null ||
        persistedParentBackendId <= 0 ||
        (parentBackendId != null &&
            parentBackendId != persistedParentBackendId)) {
      throw const RecordingUploadValidationException(
        'A filtered recording part parent identity is inconsistent.',
      );
    }
    frp
      ..parentLocalId = parents.first['id'] as int
      ..parentBEID = persistedParentBackendId;
  }

  static Future<void> _validateDetectedDialectParent(
    DatabaseExecutor executor,
    DetectedDialect dialect,
  ) async {
    final int? localParentId = dialect.filteredPartLocalId;
    final int? backendParentId = dialect.filteredPartBEID;
    if (localParentId != null && localParentId <= 0) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect has an invalid local filtered part id.',
      );
    }
    if (backendParentId != null && backendParentId <= 0) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect has an invalid backend filtered part id.',
      );
    }
    if (localParentId == null && backendParentId == null) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect must identify its filtered part.',
      );
    }
    if (localParentId == null && dialect.recordingBEID == null) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect must identify the recording that scopes '
        'its backend filtered-part id.',
      );
    }

    final List<Map<String, Object?>> parents = await executor.rawQuery(
      'SELECT fp.id AS filteredPartLocalId, '
      'fp.BEId AS filteredPartBEID, '
      'r.id AS recordingLocalId, '
      'r.BEId AS recordingBEID '
      'FROM FilteredRecordingParts fp '
      'INNER JOIN recordings r ON r.id = fp.recordingLocalId '
      'WHERE ${localParentId == null ? 'fp.BEId = ?' : 'fp.id = ?'} '
      'AND r.env = ? '
      '${dialect.recordingBEID == null ? '' : 'AND r.BEId = ? '}'
      'LIMIT 1',
      <Object?>[
        localParentId ?? backendParentId,
        Config.hostEnvironment.name,
        if (dialect.recordingBEID != null) dialect.recordingBEID,
      ],
    );
    if (parents.isEmpty) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect has no filtered-part parent in the '
        'current environment.',
      );
    }
    final Map<String, Object?> parent = parents.first;
    final int? persistedParentBackendId = parent['filteredPartBEID'] as int?;
    if (persistedParentBackendId == null ||
        persistedParentBackendId <= 0 ||
        (backendParentId != null &&
            backendParentId != persistedParentBackendId)) {
      throw const RecordingUploadValidationException(
        'A backend detected dialect parent identity is inconsistent.',
      );
    }
    dialect
      ..filteredPartLocalId = parent['filteredPartLocalId'] as int
      ..filteredPartBEID = persistedParentBackendId
      ..recordingBEID = parent['recordingBEID'] as int;
  }

  // === Filtered Recording Parts CRUD ===
  static Future<int> insertFilteredRecordingPart(
      FilteredRecordingPart frp) async {
    final db = await database;
    if (frp.BEId != null) {
      if (frp.BEId! <= 0) {
        throw const RecordingUploadValidationException(
          'A backend filtered part must have a positive backend id.',
        );
      }
      await _validateFilteredRecordingPartParent(db, frp);
      final int recordingLocalId = frp.recordingLocalId!;
      final existing = await db.query(
        'FilteredRecordingParts',
        where: 'recordingLocalId = ? AND BEId = ?',
        whereArgs: [recordingLocalId, frp.BEId],
        limit: 1,
      );
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
    final int? filteredPartId = frp.id;
    if (filteredPartId == null || filteredPartId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update a filtered recording part without a valid local id.',
      );
    }
    final db = await database;
    if (frp.BEId != null) {
      if (frp.BEId! <= 0) {
        throw const RecordingUploadValidationException(
          'A backend filtered part must have a positive backend id.',
        );
      }
      await _validateFilteredRecordingPartParent(db, frp);
    }
    final int changed = await db.update(
      'FilteredRecordingParts',
      frp.toDbJson(),
      where: 'id = ?',
      whereArgs: <Object?>[filteredPartId],
    );
    if (changed != 1) {
      throw StateError('Filtered recording part no longer exists.');
    }
  }

// === Detected Dialects CRUD ===
  static Future<int> insertDetectedDialect(DetectedDialect dd) async {
    final db = await database;
    if (dd.BEId != null) {
      if (dd.BEId! <= 0) {
        throw const RecordingUploadValidationException(
          'A backend detected dialect must have a positive backend id.',
        );
      }
      await _validateDetectedDialectParent(db, dd);
      final int filteredPartLocalId = dd.filteredPartLocalId!;
      final existing = await db.query(
        'DetectedDialects',
        where: 'filteredPartLocalId = ? AND BEId = ?',
        whereArgs: [filteredPartLocalId, dd.BEId],
        limit: 1,
      );
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
    final int? dialectId = dd.id;
    if (dialectId == null || dialectId <= 0) {
      throw const RecordingUploadValidationException(
        'Cannot update a detected dialect without a valid local id.',
      );
    }
    final db = await database;
    if (dd.BEId != null) {
      if (dd.BEId! <= 0) {
        throw const RecordingUploadValidationException(
          'A backend detected dialect must have a positive backend id.',
        );
      }
      await _validateDetectedDialectParent(db, dd);
    }
    final int changed = await db.update(
      'DetectedDialects',
      dd.toDbJson(),
      where: 'id = ?',
      whereArgs: <Object?>[dialectId],
    );
    if (changed != 1) {
      throw StateError('Detected dialect no longer exists.');
    }
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

  static bool _isDeletionLease(String? leaseId) {
    return leaseId?.trim().toLowerCase().startsWith('delete:') ?? false;
  }

  static Future<void> checkSendingRecordings() async {
    final db = await database;
    final List<Map<String, dynamic>> result =
        await db.query("recordings", where: "sending = 1");
    final List<Recording> recordings =
        result.map((row) => Recording.fromJson(row)).toList();
    final int staleBefore = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;

    for (final Recording recording in recordings) {
      if (_isDeletionLease(recording.uploadLease)) {
        logger.i(
          'Recording ${recording.id} is owned by a deletion workflow; '
          'upload reconciliation will not clear its lease.',
        );
        continue;
      }

      final String portName = '/upload/rec/${recording.id}';
      final SendPort? port = IsolateNameServer.lookupPortByName(portName);
      bool workerResponded = false;
      if (port != null) {
        final receive = ReceivePort();
        port.send({'replyTo': receive.sendPort, 'cmd': 'ping'});
        try {
          final response =
              await receive.first.timeout(const Duration(seconds: 2));
          if (response is Map && response['status'] == 'uploading') {
            workerResponded = true;
            logger.i('Recording ${recording.id} still uploading.');
          }
        } catch (error, stackTrace) {
          logger.w(
            'Recording ${recording.id} did not answer its upload health ping.',
            error: error,
            stackTrace: stackTrace,
          );
        } finally {
          receive.close();
        }
      }
      if (workerResponded) continue;

      final bool hasNoLease =
          recording.uploadLease == null || recording.uploadLease!.isEmpty;
      final bool leaseExpired = recording.uploadLeaseUpdatedAt == null ||
          recording.uploadLeaseUpdatedAt! < staleBefore;
      if (!hasNoLease && !leaseExpired) {
        logger.i(
          'Recording ${recording.id} has a fresh durable upload lease; '
          'leaving it untouched while its worker starts or recovers.',
        );
        continue;
      }

      final bool cleared = await _clearObservedUploadLease(db, recording);
      if (!cleared) {
        logger.i(
          'Recording ${recording.id} changed while reconciling; '
          'the newer lease was preserved.',
        );
        continue;
      }
      _inflightRecordingIds.remove(recording.id);
      logger.i(
        'Recording ${recording.id} stale upload lease was cleared.',
      );
    }
  }

  static Future<bool> _clearObservedUploadLease(
    Database db,
    Recording recording,
  ) {
    final int? recordingId = recording.id;
    if (recordingId == null) return Future<bool>.value(false);

    return db.transaction<bool>((Transaction txn) async {
      final String? lease = recording.uploadLease;
      final int? updatedAt = recording.uploadLeaseUpdatedAt;
      if (_isDeletionLease(lease)) {
        return false;
      }
      final String leasePredicate;
      final List<Object?> args = <Object?>[recordingId];
      if (lease == null || lease.isEmpty) {
        leasePredicate = "COALESCE(uploadLease, '') = ''";
      } else if (updatedAt == null) {
        leasePredicate = 'uploadLease = ? AND uploadLeaseUpdatedAt IS NULL';
        args.add(lease);
      } else {
        leasePredicate = 'uploadLease = ? AND uploadLeaseUpdatedAt = ?';
        args
          ..add(lease)
          ..add(updatedAt);
      }

      final int changed = await txn.rawUpdate(
        'UPDATE recordings '
        'SET sending = 0, uploadLease = NULL, uploadLeaseUpdatedAt = NULL '
        'WHERE id = ? AND COALESCE(sending, 0) = 1 AND $leasePredicate '
        'AND LOWER(TRIM(COALESCE(uploadLease, ?))) NOT LIKE ?',
        <Object?>[...args, '', 'delete:%'],
      );
      if (changed != 1) return false;

      await txn.rawUpdate(
        'UPDATE recordingParts SET sending = 0 WHERE recordingId = ?',
        <Object?>[recordingId],
      );
      return true;
    });
  }
}
