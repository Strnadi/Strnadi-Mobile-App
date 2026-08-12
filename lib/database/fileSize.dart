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
import 'dart:io';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/database/recording_duration_refresh.dart';
import 'package:strnadi/recording/waw.dart';

import '../config/config.dart';
import 'Models/recording.dart';
import 'databaseNew.dart';

final logger = Logger();

/// Calculates the duration of a WAV file in seconds.
///
/// Reads the WAV file header to extract:
/// - Sample rate (Hz)
/// - Bit depth (bits per sample)
/// - Number of channels
/// - Audio data size
///
/// Formula: duration = audioDataSize / (sampleRate * bytesPerSample * numChannels)
Future<double?> calculateWavDuration(
  String filePath, {
  SegmentFileOperations fileOperations = const IoSegmentFileOperations(),
}) async {
  try {
    final WavPcmDataRegion region = await readWavPcmDataRegion(
      fileOperations,
      filePath,
    );
    if (region.dataLength == 0) {
      logger.w('WAV file contains no audio data.');
      return null;
    }

    final int bytesPerFrame = region.channels * region.bitsPerSample ~/ 8;
    final double duration =
        region.dataLength / (region.sampleRate * bytesPerFrame);

    logger.i(
      'WAV duration calculated: sampleRate=${region.sampleRate}, '
      'channels=${region.channels}, bitsPerSample=${region.bitsPerSample}, '
      'duration=${duration.toStringAsFixed(2)}s.',
    );

    return duration;
  } catch (e, stackTrace) {
    logger.e(
      'Error calculating WAV duration.',
      error: e,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Updates a recording's duration and saves it to the database
Future<void> updateRecordingDuration(
    Recording recording, DatabaseNew db) async {
  if (recording.path == null) {
    logger.w('Recording ${recording.id} has no path, skipping duration calc');
    return;
  }

  final duration = await calculateWavDuration(recording.path!);
  if (duration != null && duration > 0) {
    recording.totalSeconds = duration;
    await DatabaseNew.updateRecordingDuration(recording);
    logger.i('Recording ${recording.id} duration updated: $duration seconds');
  } else {
    logger.w('Failed to calculate duration for recording ${recording.id}');
  }
}

/// Batch update all local recordings with null duration
Future<void> updateAllRecordingsDurations(DatabaseNew db) async {
  try {
    final recordings = await DatabaseNew.getRecordings();
    int updated = 0;

    for (final rec in recordings) {
      // Only update unsent recordings or those missing duration
      if (rec.totalSeconds == null || rec.totalSeconds! < 0) {
        if (rec.path != null && await File(rec.path!).exists()) {
          await updateRecordingDuration(rec, db);
          updated++;
        }
      }
    }

    logger.i('Updated $updated recording durations');
  } catch (e, stackTrace) {
    logger.e('Error updating all recording durations',
        error: e, stackTrace: stackTrace);
  }
}

/// Fetches recording durations from the backend for sent recordings
/// Updates the local database with the fetched durations
Future<void> fetchAndUpdateDurationsFromBackend() async {
  try {
    logger.i('Fetching recording durations from backend...');

    final ActivatedAuthSessionSnapshot? session =
        await activatedAuthSessions.capture();
    if (session == null || !session.verified) {
      logger.w(
        'No activated verified session is available for duration refresh.',
      );
      return;
    }

    final String environment = Config.hostEnvironment.name;
    final String backendHost = Config.host;
    final Map<int, Recording> recordingsByLocalId = <int, Recording>{};
    const RecordingsController controller = RecordingsController();

    Future<bool> sessionIsCurrent() async {
      final ActivatedAuthSessionSnapshot? current =
          await activatedAuthSessions.capture();
      return current != null &&
          current.verified &&
          current.accessToken == session.accessToken &&
          current.userId == session.userId &&
          current.subject == session.subject &&
          current.sessionId == session.sessionId &&
          Config.hostEnvironment.name == environment &&
          Config.host == backendHost;
    }

    final RecordingDurationRefreshResult result =
        await refreshRecordingDurations(
      isSessionCurrent: sessionIsCurrent,
      loadTargets: () async {
        final List<Recording> recordings = await DatabaseNew.getRecordings();
        final List<RecordingDurationTarget> targets =
            <RecordingDurationTarget>[];
        for (final Recording recording in recordings) {
          final int? localId = recording.id;
          final int? backendId = recording.BEId;
          if (!recording.sent ||
              localId == null ||
              localId <= 0 ||
              backendId == null ||
              backendId <= 0) {
            continue;
          }
          recordingsByLocalId[localId] = recording;
          targets.add(
            RecordingDurationTarget(
              localId: localId,
              backendId: backendId,
              currentDuration: recording.totalSeconds,
            ),
          );
        }
        return targets;
      },
      fetchDuration: (int backendId) async {
        final response = await controller.fetchRecordingById(
          backendId,
          includeParts: false,
          accessToken: session.accessToken,
          host: backendHost,
        );
        return RecordingDurationFetchResponse(
          statusCode: response.statusCode ?? 0,
          data: response.data,
        );
      },
      saveDuration: (
        RecordingDurationTarget target,
        double duration,
      ) async {
        final Recording? recording = recordingsByLocalId[target.localId];
        if (recording == null) {
          throw StateError('Duration target disappeared before persistence.');
        }
        recording.totalSeconds = duration;
        await DatabaseNew.updateRecordingDuration(recording);
      },
    );

    logger.i(
      'Duration fetch complete. Attempted: ${result.attempted}, '
      'updated: ${result.updated}, failed: ${result.failed}, '
      'session changed: ${result.sessionChanged}.',
    );
  } catch (e, stackTrace) {
    logger.e('Error fetching durations from backend',
        error: e, stackTrace: stackTrace);
  }
}
