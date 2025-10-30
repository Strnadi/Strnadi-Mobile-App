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
 *  - _parseRecordingId
 *  - _getRecordingOrFail
 *  - _ensureRecordingFileAvailable
 *  - _markRecordingSending
 *  - _uploadRecording
 *  - _sendDialectsForRecording
 *  - _postDialect
 *  - _notify
 *  - _handleSendRecordingTask
 */

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import '../dialects/ModelHandler.dart';

final logger = Logger();

Future<void> registerPlugins() async {
  await Config.loadConfig();
  await Config.loadFirebaseConfig();
  WidgetsFlutterBinding.ensureInitialized();
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

/// Extract and normalize `recordingId` from [inputData]. Returns `null` if missing/invalid.
int? _parseRecordingId(Map<String, dynamic>? inputData) {
  try {
    final raw = inputData?['recordingId'];
    if (raw == null) return null;
    if (raw is int) return raw;
    final parsed = int.tryParse(raw.toString());
    return parsed;
  } catch (e, st) {
    logger.e('Failed to parse recordingId from inputData: $e', error: e, stackTrace: st);
    return null;
  }
}

/// Fetch recording from local DB by id. Throws on failure.
Future<Recording?> _getRecordingOrFail(int recordingId) async {
  try {
    logger.i('Getting recording from DB with id $recordingId');
    return await DatabaseNew.getRecordingFromDbById(recordingId);
  } catch (e, st) {
    logger.e('BG Failed to get recording from DB: $e', error: e, stackTrace: st);
    Sentry.captureException(e, stackTrace: st);
    rethrow;
  }
}

/// Ensure a single audio file is available: if not downloaded/has empty path, try concatenation.
/// Returns an updated recording (refetched) when possible.
Future<Recording?> _ensureRecordingFileAvailable(Recording? recording) async {
  if (recording == null) return null;

  final needsConcat =
      (recording.path == null || recording.path!.isEmpty || !recording.downloaded);

  if (!needsConcat) return recording;

  try {
    logger.i('Recording path is empty or not downloaded. Concatenating parts for recording id ${recording.id}.');
    await DatabaseNew.concatRecordingParts(recording.id!);
    final updated = await DatabaseNew.getRecordingFromDbById(recording.id!);
    if (updated != null && (updated.path != null && updated.path!.isNotEmpty && updated.downloaded)) {
      logger.i('Recording updated after concatenation: path = ${updated.path}, downloaded = ${updated.downloaded}');
    } else {
      logger.w('Recording still not downloaded after attempting concatenation.');
    }
    return updated;
  } catch (e, st) {
    logger.e('Failed concatenating parts: $e', error: e, stackTrace: st);
    Sentry.captureException(e, stackTrace: st);
    return recording; // best effort
  }
}

/// Flip the `sending` flag to true to prevent duplicate workers. Returns false if already sending.
Future<bool> _markRecordingSending(Recording recording) async {
  if (recording.sending) {
    logger.w('Recording ${recording.id} is already marked as sending.');
    return false;
  }
  recording.sending = true;
  await DatabaseNew.updateRecording(recording);
  logger.i('Recording ${recording.id} marked as sending.');
  return true;
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

  List<Dialect> dialects = const [];
  try {
    logger.i('Getting dialects from DB with recording id $recordingId');
    dialects = await DatabaseNew.getDialectsByRecordingId(recordingId);
  } catch (e, st) {
    logger.e('Failed to get dialects for recording $recordingId: $e', error: e, stackTrace: st);
    Sentry.captureException(e, stackTrace: st);
  }

  logger.i('Got dialects for recording $recordingId: ${dialects.length}');
  if (dialects.isEmpty) {
    logger.i('No dialects found for recording $recordingId');
    return;
  }

  final jwt = await const FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    logger.e('JWT token not found in secure storage.');
    return;
  }

  for (final dialect in dialects) {
    final body = dialect.toBEJson()
      ..['recordingId'] = beRecordingId; // overwrite with BE id

    logger.t('Dialect body: $body');

    try {
      final resp = await _postDialect(body: body, jwt: jwt);
      if (resp.statusCode == 200) {
        logger.i('Dialect ${dialect.dialect} sent successfully');
      } else {
        logger.e('Dialect sending failed with status ${resp.statusCode}. Response: ${resp.body}');
      }
    } catch (e, st) {
      logger.e('Error sending dialect ${dialect.dialect}: $e', error: e, stackTrace: st);
    }
  }
}

Future<http.Response> _postDialect({
  required Map<String, dynamic> body,
  required String jwt,
}) async {
  final url = Uri.https(Config.host, '/recordings/filtered');
  return http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
    body: jsonEncode(body),
  );
}

Future<void> _notify(String title, String message) async {
  await DatabaseNew.sendLocalNotification(title, message);
}

/// Main entry for the background worker that sends a recording.
Future<bool> _handleSendRecordingTask(Map<String, dynamic>? inputData) async {
  final recordingId = _parseRecordingId(inputData);
  if (recordingId == null) {
    logger.e('Missing or invalid recordingId in inputData: $inputData');
    await _notify('Nahrávání nahrávky selhalo', 'Odesílání nahrávky selhalo: chybí recordingId.');
    return true; // do not retry, input was invalid
  }

  Recording? recording;
  try {
    recording = await _getRecordingOrFail(recordingId);
  } catch (_) {
    await _notify('Nahrávání nahrávky selhalo', 'Odesílání nahrávky $recordingId selhalo při čtení z DB.');
    return true; // already logged & captured
  }

  if (recording == null) {
    logger.e('Recording $recordingId not found in DB');
    await _notify('Recording Not Found', 'Recording $recordingId was not found in the database.');
    return true;
  }

  // Ensure local file exists (concatenate parts if needed)
  recording = await _ensureRecordingFileAvailable(recording);

  // Guard: _ensureRecordingFileAvailable may return null or leave file unavailable
  if (recording == null ||
      recording.path == null ||
      recording.path!.isEmpty ||
      !recording.downloaded) {
    logger.e('Recording $recordingId not ready after ensure: null/file missing.');
    await _notify(
      'Nahrávání nahrávky selhalo',
      'Odesílání nahrávky $recordingId selhalo: soubor nahrávky není k dispozici.',
    );
    return true;
  }

  // Prevent duplicate uploads
  final allowed = await _markRecordingSending(recording);
  if (!allowed) {
    return false; // indicate worker can be retried if needed
  }

  try {
    await _uploadRecording(recording);

    // After successful upload, send dialects
    await _sendDialectsForRecording(
      recordingId: recordingId,
      beRecordingId: recording.BEId,
    );

    await _notify('Nahrávka se odeslala', 'Nahrávka $recordingId se úspěšně odeslala.');
    return true;
  } catch (e, st) {
    // Reset sending flag on failure
    try {
      recording.sending = false;
      await DatabaseNew.updateRecording(recording);
    } catch (_) {}

    logger.e('Failed to upload recording $recordingId in background: $e', error: e, stackTrace: st);
    Sentry.captureException(e, stackTrace: st);
    await _notify('Nahrávání nahrávky selhalo', 'Odesílání nahrávky $recordingId selhalo s chybou: $e');
    return true; // handled; avoid infinite retries unless WorkManager policy says otherwise
  }
}