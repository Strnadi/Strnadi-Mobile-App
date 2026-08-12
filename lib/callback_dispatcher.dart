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
/*
 * callback_dispatcher.dart (refactored)
 *
 * Responsibilities split into small functions for clarity:
 *  - _getRecordingOrFail
 *  - _ensureRecordingFileAvailable
 *  - _markRecordingSending
 *  - _uploadRecording
 *  - _sendDialectsForRecording
 *  - _postDialect
 *  - _notify
 *  - _handleSendRecordingTask
 */

import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:dio/dio.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/background_recording_upload_task.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/database/upload_protocol.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:workmanager/workmanager.dart';

import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/database/background_upload_initialization.dart';
import 'package:strnadi/firebase/local_notifications.dart';
import '../dialects/ModelHandler.dart';

final logger = Logger();
const FilteredRecordingsController _filteredRecordingsController =
    FilteredRecordingsController();

// ---------- Lightweight health-check port server ----------
String _healthPortName(int recordingId) => '/upload/rec/$recordingId';

final Map<int, ReceivePort> _healthPorts = <int, ReceivePort>{};

Future<void> _loadBackgroundLocalization() async {
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.reload();
  } catch (error, stackTrace) {
    // Workmanager may reuse an isolate whose preferences cache predates a
    // language change. A reload failure is non-fatal; Localization.load still
    // gets a chance to use the cached selection or its platform fallback.
    logger.w(
      'Failed to refresh background language preference: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    await Localization.load(null);
  } catch (error, stackTrace) {
    logger.w(
      'Failed to load the selected language for the background worker: $error',
      error: error,
      stackTrace: stackTrace,
    );
    try {
      await Localization.load('assets/lang/en.json');
    } catch (fallbackError, fallbackStackTrace) {
      // Uploading is authoritative; a missing notification translation must
      // never prevent the worker from sending or retrying the recording.
      logger.w(
        'Failed to load fallback background translations: $fallbackError',
        error: fallbackError,
        stackTrace: fallbackStackTrace,
      );
    }
  }
}

/// Start a simple reply server bound to IsolateNameServer under a well-known name.
/// While active, UI can `lookupPortByName` and send either a `SendPort` directly
/// or a Map with `{'replyTo': SendPort, 'cmd': 'ping'}` to receive a status reply.
bool _startHealthServer(int recordingId) {
  if (_healthPorts.containsKey(recordingId)) {
    return false;
  }
  final ReceivePort candidate = ReceivePort();

  final name = _healthPortName(recordingId);
  final bool ok =
      IsolateNameServer.registerPortWithName(candidate.sendPort, name);
  if (!ok) {
    candidate.close();
    logger.i('Upload health server already exists on $name.');
    return false;
  }
  _healthPorts[recordingId] = candidate;

  candidate.listen((message) {
    try {
      // Accept either a SendPort directly...
      if (message is SendPort) {
        message.send({
          'status': 'uploading',
          'recordingId': recordingId,
        });
        return;
      }
      // ...or a Map with a replyTo port
      if (message is Map) {
        final replyTo = message['replyTo'];
        if (replyTo is SendPort) {
          replyTo.send({
            'status': 'uploading',
            'recordingId': recordingId,
            'cmd': message['cmd'],
          });
          return;
        }
      }
    } catch (_) {
      // Best-effort: ignore malformed messages
    }
  });

  logger.i('Health-check server started on ${_healthPortName(recordingId)}');
  return true;
}

/// Stop and unregister the health server.
void _stopHealthServer(int recordingId) {
  try {
    IsolateNameServer.removePortNameMapping(_healthPortName(recordingId));
  } catch (_) {}
  try {
    _healthPorts.remove(recordingId)?.close();
  } catch (_) {}
  logger.i('Health-check server stopped on ${_healthPortName(recordingId)}');
}
// ----------------------------------------------------------

Future<void> registerPlugins() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await initializeBackgroundUploadRuntime(
    initializeEssentialConfiguration: () async {
      await Config.loadConfig();
    },
    initializeNotifications: () async {
      await initLocalNotifications();
    },
    initializeLocalization: () async {
      await _loadBackgroundLocalization();
    },
    onAncillaryFailure: (String step, Object error, StackTrace stackTrace) {
      logger.w(
        'Background $step initialization failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    logger.i('Got background task: $task');
    await registerPlugins();
    logger.i('Background Flutter binding initialized');

    if (task == 'sendRecording' || task == 'com.delta.strnadi.sendRecording') {
      final ok = await _handleSendRecordingTask(inputData);
      return Future.value(ok);
    }

    // Unknown task: still return success to avoid retries.
    logger.w('Unknown task name: $task');
    return Future.value(true);
  });
}

/// Fetch recording from local DB by id. Throws on failure.
Future<Recording?> _getRecordingOrFail(int recordingId) async {
  try {
    logger.i('Getting recording from DB with id $recordingId');
    return await DatabaseNew.getRecordingFromDbById(recordingId);
  } catch (e, st) {
    logger.e('BG Failed to get recording from DB: $e',
        error: e, stackTrace: st);
    Sentry.captureException(e, stackTrace: st);
    rethrow;
  }
}

/// Uploads the recording binary and its parts to the backend.
Future<void> _uploadRecording(Recording recording) async {
  logger.i('Getting parts from DB with recording id ${recording.id}');
  final parts = await DatabaseNew.getPartsByRecordingId(recording.id!);
  logger.i('Starting to send recording ${recording.id} in background');
  await DatabaseNew.sendRecordingNew(recording, parts);
  logger.i('Recording ${recording.id} uploaded successfully in background');
}

/// Fetch dialects for [recordingId] and send them to BE using the BE recording id [beRecordingId].
Future<void> _sendDialectsForRecording({
  required int recordingId,
  required int? beRecordingId,
}) async {
  logger.i('Sending dialects for recording $recordingId in background');

  if (beRecordingId == null || beRecordingId <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot send dialects without a backend recording id.',
    );
  }

  final String leaseId =
      'dialect:$recordingId:${DateTime.now().microsecondsSinceEpoch}:'
      '${Isolate.current.hashCode}';
  await DatabaseNew.runWithRecordingWorkflowLease<void>(
    recordingId: recordingId,
    leaseId: leaseId,
    operation: (RecordingWorkflowLeaseContext context) async {
      final Recording localRecording = context.recording;
      final RecordingUploadSession session = context.session;
      if (session.backendHost.isEmpty) {
        throw FetchException(
          'Authentication is required to send dialects.',
          401,
        );
      }
      if (!localRecording.sent ||
          localRecording.BEId == null ||
          localRecording.BEId != beRecordingId) {
        throw const RecordingUploadValidationException(
          'Cannot send dialects before the recording upload is durable.',
        );
      }
      final String recordingUploadKey = (localRecording.uploadKey ?? '').trim();
      if (recordingUploadKey.isEmpty) {
        throw const RecordingUploadValidationException(
          'Cannot send dialects without a durable recording upload key.',
        );
      }

      // Load the request rows only after the aggregate lease is held. A draft
      // edit that wins before acquisition is reflected here; an edit that
      // loses after acquisition is rejected by the repository CAS.
      logger.i('Getting dialects from DB with recording id $recordingId');
      final List<Dialect> dialects =
          await DatabaseNew.getDialectsByRecordingId(recordingId);
      logger.i('Got dialects for recording $recordingId: ${dialects.length}');
      if (dialects.isEmpty) {
        logger.i('No dialects found for recording $recordingId');
        return;
      }

      for (final dialect in dialects) {
        final int? existingBackendId = dialect.BEID;
        if (existingBackendId != null) {
          validatePersistedDialectBackendAssociation(
            backendDialectId: existingBackendId,
            backendRecordingId: dialect.recordingBEID,
            expectedBackendRecordingId: beRecordingId,
          );
          continue;
        }
        await context.renew();

        final String dialectUploadKey = (dialect.uploadKey ?? '').trim();
        if (dialectUploadKey.isEmpty) {
          throw const RecordingUploadValidationException(
            'Cannot send a dialect without a durable upload key.',
          );
        }
        final int? dialectId = dialect.id;
        if (dialectId == null || dialectId <= 0) {
          throw const RecordingUploadValidationException(
            'Cannot send a dialect without a valid local id.',
          );
        }
        final body = dialect.toBEJson()
          ..['recordingId'] = beRecordingId; // overwrite with BE id
        validateDialectUploadRequest(body);

        logger.t(
          'Sending dialect ${dialect.id} for recording $recordingId.',
        );

        final Response<dynamic> resp =
            await runDialectUploadAttempt<Response<dynamic>>(
          uploadAttempted: dialect.uploadAttempted,
          persistAttemptMarker: () {
            return DatabaseNew.markDialectAttemptedWithWorkflowLease(
              dialectId,
              recordingId,
              leaseId,
            );
          },
          markAttemptedInMemory: () {
            dialect.uploadAttempted = true;
          },
          renew: context.renew,
          post: (Future<void> Function() beforePost) {
            return _postDialect(
              body: body,
              accessToken: session.accessToken,
              backendHost: session.backendHost,
              idempotencyKey: dialectUploadIdempotencyKey(
                recordingUploadKey: recordingUploadKey,
                dialectUploadKey: dialectUploadKey,
              ),
              beforePost: beforePost,
            );
          },
        );
        final int status = resp.statusCode ?? 500;
        if (status < 200 || status >= 300) {
          throw UploadException(
            'Dialect sending failed.',
            status,
          );
        }

        final int backendDialectId = readPositiveUploadResponseId(
          resp.data,
          entity: 'dialect',
          mapKeys: const <String>['id', 'filteredPartId', 'data'],
        );
        dialect
          ..BEID = backendDialectId
          ..recordingBEID = beRecordingId;
        await DatabaseNew.updateDialectWithWorkflowLease(
          dialect,
          recordingId,
          leaseId,
        );
        logger.i('Dialect ${dialect.dialect} sent successfully');
      }
    },
  );
}

Future<Response<dynamic>> _postDialect({
  required Map<String, dynamic> body,
  required String accessToken,
  required String backendHost,
  required String idempotencyKey,
  required Future<void> Function() beforePost,
}) async {
  return _filteredRecordingsController.createFilteredPart(
    body,
    accessToken: accessToken,
    host: backendHost,
    idempotencyKey: idempotencyKey,
    beforePost: beforePost,
  );
}

Future<void> _notify(String title, String message) async {
  try {
    await DatabaseNew.sendLocalNotification(title, message);
  } catch (error, stackTrace) {
    // A user-visible notification is ancillary. It must not turn a completed
    // upload into a retry, or replace the upload error used to decide whether
    // Workmanager should retry.
    logger.w(
      'Failed to show recording upload notification: $error',
      error: error,
      stackTrace: stackTrace,
    );
    Sentry.captureException(error, stackTrace: stackTrace);
  }
}

Future<void> _sendBackgroundUploadNotice(
  BackgroundRecordingUploadNotice notice,
  int? recordingId,
) {
  switch (notice) {
    case BackgroundRecordingUploadNotice.missingId:
      return _notify(
        t('notifications.recordingUpload.failure.title'),
        t('notifications.recordingUpload.failure.missingId'),
      );
    case BackgroundRecordingUploadNotice.databaseReadFailure:
      return _notify(
        t('notifications.recordingUpload.failure.title'),
        t('notifications.recordingUpload.failure.databaseRead')
            .replaceFirst('{recordingId}', recordingId.toString()),
      );
    case BackgroundRecordingUploadNotice.notFound:
      return _notify(
        t('notifications.recordingUpload.notFound.title'),
        t('notifications.recordingUpload.notFound.message')
            .replaceFirst('{recordingId}', recordingId.toString()),
      );
    case BackgroundRecordingUploadNotice.uploadSucceeded:
      return _notify(
        t('notifications.recordingUpload.success.title'),
        t('notifications.recordingUpload.success.message')
            .replaceFirst('{recordingId}', recordingId.toString()),
      );
    case BackgroundRecordingUploadNotice.uploadFailed:
      return _notify(
        t('notifications.recordingUpload.failure.title'),
        t('notifications.recordingUpload.failure.upload')
            .replaceFirst('{recordingId}', recordingId.toString()),
      );
  }
}

/// Main entry for the background worker that sends a recording.
Future<bool> _handleSendRecordingTask(Map<String, dynamic>? inputData) async {
  return handleBackgroundRecordingUploadTask<Recording>(
    rawRecordingId: inputData?['recordingId'],
    loadRecording: _getRecordingOrFail,
    reconcileInterruptedUploads: DatabaseNew.checkSendingRecordings,
    recordingIsSending: (Recording recording) => recording.sending,
    backendRecordingId: (Recording recording) => recording.BEId,
    uploadRecording: _uploadRecording,
    sendDialects: (int recordingId, int? backendRecordingId) =>
        _sendDialectsForRecording(
      recordingId: recordingId,
      beRecordingId: backendRecordingId,
    ),
    sendNotice: _sendBackgroundUploadNotice,
    startHealth: (int recordingId) async => _startHealthServer(recordingId),
    stopHealth: (int recordingId) async => _stopHealthServer(recordingId),
    isRetryable: isRetryableRecordingUploadFailure,
    onTaskFailure: (Object error, StackTrace stackTrace) {
      logger.e(
        'Background recording upload failed.',
        error: error,
        stackTrace: stackTrace,
      );
      Sentry.captureException(error, stackTrace: stackTrace);
    },
    onAncillaryFailure: (
      String operation,
      Object error,
      StackTrace stackTrace,
    ) {
      logger.w(
        'Background upload $operation failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      Sentry.captureException(error, stackTrace: stackTrace);
    },
  );
}
