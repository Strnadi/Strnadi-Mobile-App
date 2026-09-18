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

extension _RecordingFiles on RecordingController {
  Future<void> _deleteTemporarySegmentFiles() async {
    final String? finalRecordingPath = recordedFilePath;
    final Set<String> pathsToDelete = <String>{
      ...segmentPaths.where((path) => path.isNotEmpty),
      if (filepath.isNotEmpty) filepath,
      if (finalRecordingPath != null && finalRecordingPath.isNotEmpty)
        finalRecordingPath,
    };

    for (final String path in pathsToDelete) {
      try {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e, stackTrace) {
        logger.e(
          'Error deleting a discarded recording segment.',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _resetDiscardedRecordingState() {
    void reset() {
      _recordDuration = Duration.zero;
      _segmentElapsedBaseline = Duration.zero;
      segmentPaths.clear();
      recordingPartsList.clear();
      recordingPartsTimeList.clear();
      _liveRoute.clear();
      _lastRouteUpdateTime = null;
      currentPosition = null;
      recordedPart = null;
      recordedFilePath = null;
      filepath = '';
      overallStartTime = null;
      segmentStartTime = null;
      recording = false;
      _recordState = RecordState.stop;
      _segmentFinalizationPending = false;
      _logicalPauseOwnsRecorderState = false;
      _draftPersistenceMayHaveCommitted = false;
      _rawPcmCapture = null;
      _recordingInterruptedAt = null;
    }

    if (mounted) {
      _update(reset);
    } else {
      reset();
    }
  }

  Future<void> _discardRecordingResources() async {
    await _shutdownRecordingRuntime();
    await _deleteTemporarySegmentFiles();
    _resetDiscardedRecordingState();
  }

  Future<void> _cleanupFailedRecordingStart({
    required bool recorderStarted,
  }) async {
    _elapsedTimer.pause();
    if (recorderStarted) {
      try {
        await _audioRecorder.stop();
        await _finishActiveRawPcmCapture();
      } catch (e, stackTrace) {
        try {
          await _abortActiveRawPcmCapture();
        } catch (_) {
          // Preserve the recorder/startup failure.
        }
        logger.e(
          'Error stopping recorder after a failed start: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    await _shutdownRecordingRuntime(stopRecorder: false);
    await _deleteTemporarySegmentFiles();
    _resetDiscardedRecordingState();
  }

  Future<String> _getPath({
    Iterable<String> excludedPaths = const <String>[],
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final String path = await selectUnusedRecordingPath(
      nextCandidate: () {
        final int timestamp = DateTime.now().microsecondsSinceEpoch;
        final int sequence = _recordingPathSequence++;
        return '${dir.path}${Platform.pathSeparator}'
            'audio_${timestamp}_$sequence.wav';
      },
      exists: (candidate) => File(candidate).exists(),
      excludedPaths: excludedPaths.toSet(),
    );
    logger.i('Reserved a final recording path.');
    return path;
  }

  Future<ReservedRawPcmFile> _reserveRawPcmPath({
    Iterable<String> excludedPaths = const <String>[],
  }) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
      nextCandidate: () {
        final int timestamp = DateTime.now().microsecondsSinceEpoch;
        final int sequence = _recordingPathSequence++;
        return '${dir.path}${Platform.pathSeparator}'
            'audio_${timestamp}_$sequence.raw';
      },
      excludedPaths: excludedPaths.toSet(),
    );
    logger.i('Reserved a raw PCM path.');
    return reserved;
  }
}
