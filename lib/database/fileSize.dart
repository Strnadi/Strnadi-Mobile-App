import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../config/config.dart';
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
Future<double?> calculateWavDuration(String filePath) async {
  try {
    final file = File(filePath);
    if (!await file.exists()) {
      logger.w('WAV file does not exist: $filePath');
      return null;
    }

    final bytes = await file.readAsBytes();

    // Minimum WAV header is 44 bytes
    if (bytes.length < 44) {
      logger.w('File is too small to be a valid WAV file: $filePath');
      return null;
    }

    // Verify RIFF header (bytes 0-3 should be "RIFF")
    if (bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46) {
      logger.w('Invalid RIFF header. Not a WAV file: $filePath');
      return null;
    }

    // Verify WAVE header (bytes 8-11 should be "WAVE")
    if (bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      logger.w('Invalid WAVE header. Not a WAV file: $filePath');
      return null;
    }

    // Extract audio format info from fmt subchunk (typically starts at byte 12)
    int fmtChunkOffset = 12;
    int audioDataSize = 0;
    int sampleRate = 0;
    int bytesPerSample = 0;
    int numChannels = 0;

    // Find fmt chunk
    while (fmtChunkOffset < bytes.length - 8) {
      // Check if this is the fmt chunk
      if (bytes[fmtChunkOffset] == 0x66 &&
          bytes[fmtChunkOffset + 1] == 0x6D &&
          bytes[fmtChunkOffset + 2] == 0x74 &&
          bytes[fmtChunkOffset + 3] == 0x20) {
        // Found "fmt " chunk
        // Chunk size is at fmtChunkOffset + 4
        final fmtChunkSize = _bytesToInt32LE(bytes, fmtChunkOffset + 4);

        // AudioFormat (1 = PCM)
        final audioFormat = _bytesToInt16LE(bytes, fmtChunkOffset + 8);
        if (audioFormat != 1) {
          logger.w('Unsupported audio format: $audioFormat');
          return null;
        }

        // NumChannels
        numChannels = _bytesToInt16LE(bytes, fmtChunkOffset + 12);

        // SampleRate
        sampleRate = _bytesToInt32LE(bytes, fmtChunkOffset + 16);

        // ByteRate (not needed but available at fmtChunkOffset + 20)

        // BlockAlign (not needed but available at fmtChunkOffset + 24)

        // BitsPerSample
        final bitsPerSample = _bytesToInt16LE(bytes, fmtChunkOffset + 26);
        bytesPerSample = bitsPerSample ~/ 8;

        break;
      }

      fmtChunkOffset += 8;
    }

    if (sampleRate == 0 || bytesPerSample == 0 || numChannels == 0) {
      logger.w('Failed to extract WAV format information from: $filePath');
      return null;
    }

    // Find data chunk
    int dataChunkOffset = 12;
    while (dataChunkOffset < bytes.length - 8) {
      if (bytes[dataChunkOffset] == 0x64 &&
          bytes[dataChunkOffset + 1] == 0x61 &&
          bytes[dataChunkOffset + 2] == 0x74 &&
          bytes[dataChunkOffset + 3] == 0x61) {
        // Found "data" chunk
        audioDataSize = _bytesToInt32LE(bytes, dataChunkOffset + 4);
        break;
      }

      dataChunkOffset += 8;
    }

    if (audioDataSize == 0) {
      logger.w('No audio data found in WAV file: $filePath');
      return null;
    }

    // Calculate duration in seconds
    final bytesPerFrame = bytesPerSample * numChannels;
    final duration = audioDataSize / (sampleRate * bytesPerFrame);

    logger.i(
        'WAV Duration calculated - File: $filePath, Sample Rate: $sampleRate Hz, Channels: $numChannels, Bits/Sample: ${bytesPerSample * 8}, Duration: ${duration.toStringAsFixed(2)}s');

    return duration;
  } catch (e, stackTrace) {
    logger.e('Error calculating WAV duration for $filePath',
        error: e, stackTrace: stackTrace);
    return null;
  }
}

/// Helper function to convert 2 bytes (little-endian) to int16
int _bytesToInt16LE(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

/// Helper function to convert 4 bytes (little-endian) to int32
int _bytesToInt32LE(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
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
    await DatabaseNew.updateRecording(recording);
    logger.i('Recording ${recording.id} duration updated: $duration seconds');
  } else {
    logger.w('Failed to calculate duration for recording ${recording.id}');
  }
}

/// Batch update all local recordings with null duration
Future<void> updateAllRecordingsDurations(DatabaseNew db) async {
  try {
    final recordings = DatabaseNew.recordings;
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
Future<void> fetchAndUpdateDurationsFromBackend(DatabaseNew db) async {
  try {
    logger.i('Fetching recording durations from backend...');

    String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      logger.w('No JWT token available. Cannot fetch durations from backend.');
      return;
    }

    // Get all local recordings that are marked as sent
    final recordings = DatabaseNew.recordings
        .where((rec) => rec.sent && rec.BEId != null)
        .toList();

    if (recordings.isEmpty) {
      logger.i('No sent recordings found to fetch durations for.');
      return;
    }

    logger.i(
        'Found ${recordings.length} sent recordings to update durations for.');

    int updated = 0;
    int failed = 0;

    for (final rec in recordings) {
      try {
        // Skip if duration is already set and valid
        if (rec.totalSeconds != null && rec.totalSeconds! > 0) {
          logger.i(
              'Recording ${rec.id} (BEId: ${rec.BEId}) already has duration: ${rec.totalSeconds}s');
          continue;
        }

        // Fetch recording details from backend
        final Uri url = Uri(
          scheme: 'https',
          host: Config.host,
          path: '/recordings/${rec.BEId}',
          query: 'parts=false',
        );

        final http.Response response = await http.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);

          // Extract totalSeconds from backend response
          final dynamic totalSecondsValue = data['totalSeconds'];
          double? duration;

          if (totalSecondsValue is double) {
            duration = totalSecondsValue;
          } else if (totalSecondsValue is int) {
            duration = totalSecondsValue.toDouble();
          } else if (totalSecondsValue is String) {
            duration = double.tryParse(totalSecondsValue);
          }

          if (duration != null && duration > 0) {
            rec.totalSeconds = duration;
            await DatabaseNew.updateRecording(rec);
            logger.i(
                'Recording ${rec.id} (BEId: ${rec.BEId}) duration updated from backend: ${duration}s');
            updated++;
          } else {
            logger.w(
                'Invalid duration value from backend for recording ${rec.id}: $totalSecondsValue');
            failed++;
          }
        } else if (response.statusCode == 404) {
          logger.w(
              'Recording ${rec.id} (BEId: ${rec.BEId}) not found on backend');
          failed++;
        } else {
          logger.w(
              'Failed to fetch recording ${rec.id} (BEId: ${rec.BEId}). Status: ${response.statusCode}');
          failed++;
        }
      } catch (e, stackTrace) {
        logger.e('Error fetching duration for recording ${rec.id}',
            error: e, stackTrace: stackTrace);
        failed++;
      }
    }

    logger.i('✅ Duration fetch complete. Updated: $updated, Failed: $failed');
  } catch (e, stackTrace) {
    logger.e('Error fetching durations from backend',
        error: e, stackTrace: stackTrace);
  }
}
