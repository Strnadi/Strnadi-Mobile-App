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
part of 'recording_controller.dart';

extension _RecordingSegments on RecordingController {
  Future<void> _finishActiveRawPcmCapture() async {
    final RawPcmCapture? capture = _rawPcmCapture;
    if (capture == null) return;

    await capture.finish();
    if (identical(_rawPcmCapture, capture)) {
      _rawPcmCapture = null;
    }
  }

  Future<void> _abortActiveRawPcmCapture() async {
    final RawPcmCapture? capture = _rawPcmCapture;
    if (capture == null) return;

    // Keep the aborted capture attached. Its finish() method will continue to
    // reject finalization, preventing a partial raw file from being wrapped.
    await capture.abort();
  }

  void _setRecorderPausedForFinalization() {
    void update() {
      recording = false;
      _recordState = RecordState.pause;
      _logicalPauseOwnsRecorderState = true;
    }

    if (mounted) {
      _update(update);
    } else {
      update();
    }
  }

  Future<void> _stopActiveSegmentForFinalization({
    required String action,
  }) async {
    if (_segmentFinalizationPending) {
      return;
    }

    final RecordingPartUnready? part = recordedPart;
    if (part == null) {
      throw StateError('Missing recording part metadata while $action');
    }
    if (filepath.isEmpty) {
      throw StateError('Missing raw recording path while $action');
    }

    final DateTime segmentStoppedAt = _recordingInterruptedAt ?? DateTime.now();
    part.endTime = segmentStoppedAt;
    logger.i('Segment end time: ${part.endTime}');
    _elapsedTimer.pause();
    _segmentFinalizationPending = true;
    _setRecorderPausedForFinalization();
    _updateLiveActivity(isRunning: false);

    try {
      await _audioRecorder.stop();
      await _finishActiveRawPcmCapture();
    } catch (error, stackTrace) {
      try {
        await _abortActiveRawPcmCapture();
      } catch (_) {
        // Preserve the recorder/capture failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    try {
      await WakelockPlus.disable();
    } catch (e, stackTrace) {
      logger.e(
        'Error disabling wakelock while $action: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    await _showPausedForegroundNotification(action: action);

    await _finishPartLocation(part, action: action);
  }

  Future<void> _finalizePendingSegment() async {
    if (!_segmentFinalizationPending) {
      return;
    }

    final RecordingPartUnready? part = recordedPart;
    if (part == null) {
      throw StateError('Missing recording part metadata while finalizing');
    }
    final String rawPath = filepath;
    if (rawPath.isEmpty) {
      throw StateError('Missing raw recording path while finalizing');
    }
    await _finishActiveRawPcmCapture();

    final String finalizedPath = await _getPath(
      excludedPaths: <String>{...segmentPaths, rawPath},
    );

    await writeFinalizedWavSegment(
      rawInputPath: rawPath,
      outputPath: finalizedPath,
      sampleRate: sampleRate,
      bitRate: bitRate,
    );

    final int segmentDuration = _currentSegmentElapsed.inSeconds;
    final int rawPathIndex = segmentPaths.lastIndexOf(rawPath);
    if (rawPathIndex >= 0) {
      segmentPaths[rawPathIndex] = finalizedPath;
    } else {
      segmentPaths.add(finalizedPath);
    }
    recordingPartsTimeList.add(segmentDuration);
    part.path = finalizedPath;
    recordingPartsList.add(part);
    recordedPart = null;
    _segmentFinalizationPending = false;

    try {
      await const IoSegmentFileOperations().deleteIfExists(rawPath);
    } catch (e, stackTrace) {
      logger.e(
        'Finalized segment was committed, but raw input cleanup failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _reportSegmentFinalizationFailure(Object error, StackTrace stackTrace) {
    logger.e(
      'Error finalizing recorded segment: $error',
      error: error,
      stackTrace: stackTrace,
    );

    if (mounted) {
      _showMessage(t('streamRec.errors.segmentFinalizeError'));
    }
  }

  Future<void> _finalizeInterruptedSegment() async {
    if (_recordingInterruptedAt == null) return;

    await _stopActiveSegmentForFinalization(
      action: 'finalizing interrupted recording',
    );
    await _finalizePendingSegment();

    _recordingInterruptedAt = null;
  }
}
