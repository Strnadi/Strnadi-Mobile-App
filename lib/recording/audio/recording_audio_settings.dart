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
import 'package:flutter/services.dart';
import 'package:strnadi/logging/app_logger.dart';

/// Native settings fall back to mono, 48 kHz, 16-bit PCM.
const defaultRecordingSampleRate = 48000;
const recordingPcmBitDepth = 16;
const MethodChannel recordingSettingsChannel = MethodChannel(
  'com.delta.strnadi/audio',
);

int calcBitRate(int sampleRate, int bitDepth) {
  return sampleRate * bitDepth;
}

/// The mono PCM format shared by initial and resumed segments.
class RecordingAudioSettings {
  const RecordingAudioSettings({this.sampleRate = defaultRecordingSampleRate});

  final int sampleRate;
  int get bitRate => calcBitRate(sampleRate, recordingPcmBitDepth);

  static Future<RecordingAudioSettings> load({
    MethodChannel channel = recordingSettingsChannel,
  }) async {
    final logger = AppLogger(scope: 'recording.audioSettings');
    int resolvedSampleRate = defaultRecordingSampleRate;
    try {
      final Map<dynamic, dynamic>? settings = await channel.invokeMethod(
        'getBestAudioSettings',
      );
      final Object? configuredSampleRate = settings?['sampleRate'];
      final int? parsedSampleRate = configuredSampleRate is num
          ? configuredSampleRate.toInt()
          : int.tryParse(configuredSampleRate?.toString() ?? '');
      if (parsedSampleRate != null && parsedSampleRate > 0) {
        resolvedSampleRate = parsedSampleRate;
      }
    } catch (error, stackTrace) {
      logger.e(
        'Failed to get audio settings, using defaults: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
    final result = RecordingAudioSettings(sampleRate: resolvedSampleRate);
    logger.i(
      'Audio settings: sampleRate=${result.sampleRate}, bitRate=${result.bitRate}',
    );
    return result;
  }
}
