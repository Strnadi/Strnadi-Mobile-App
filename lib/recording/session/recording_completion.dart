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

extension _RecordingCompletion on RecordingController {
  Future<void> _stop() async {
    if (_isFinishingRecording || _isProcessingRecording || !mounted) return;
    if (_draftPersistenceMayHaveCommitted) {
      _showMessage(t('streamRec.errors.saveStatusUnknown'));
      return;
    }
    bool shouldShutdownRuntime = false;
    _update(() {
      _isFinishingRecording = true;
    });

    try {
      if (filepath.isEmpty) {
        _showMessage(t('streamRec.errors.noRecordingFound'));
        return;
      }
      try {
        await _finalizeInterruptedSegment();
      } catch (error, stackTrace) {
        _reportSegmentFinalizationFailure(error, stackTrace);
        return;
      }
      if (_recordState == RecordState.record) {
        try {
          await _stopActiveSegmentForFinalization(action: 'stopping recording');
          await _finalizePendingSegment();
        } catch (e, stackTrace) {
          _reportSegmentFinalizationFailure(e, stackTrace);
          return;
        }
        if (!mounted) return;
        _update(() {
          _recordDuration = Duration.zero;
        });
      } else if (_recordState == RecordState.pause) {
        if (_segmentFinalizationPending) {
          try {
            await _finalizePendingSegment();
          } catch (e, stackTrace) {
            _reportSegmentFinalizationFailure(e, stackTrace);
            return;
          }
        }
        if (!mounted) return;
        _update(() {
          recording = false;
        });
      }
      final List<String> paths = List<String>.from(segmentPaths);
      String? outputPath = recordedFilePath;
      if (outputPath == null || !await File(outputPath).exists()) {
        outputPath = await _getPath(excludedPaths: paths);
        try {
          await concatWavFiles(paths, outputPath);
          recordedFilePath = outputPath;
          logger.i('Final recording saved.');
        } catch (e, stackTrace) {
          logger.e(
            "Error concatenating files: $e",
            error: e,
            stackTrace: stackTrace,
          );
          return;
        }
      }
      if (overallStartTime == null) return;
      if (!mounted) return;

      late final RecordingDraftHandoff persistedDraft;
      try {
        persistedDraft = await RecordingDraftHandoffCoordinator.database()
            .persistCapture(
              filepath: recordedFilePath!,
              startTime: overallStartTime!,
              recordingParts: recordingPartsList,
              recordingPartDurations: recordingPartsTimeList,
              environment: Config.dataEnvironment,
            );
      } catch (error, stackTrace) {
        if (error is RecordingDraftPersistenceException &&
            error.mayHaveCommitted) {
          _draftPersistenceMayHaveCommitted = true;
          shouldShutdownRuntime = true;
        }
        logger.e(
          'Failed to persist the completed recording before opening its form',
          error: error,
          stackTrace: stackTrace,
        );

        if (mounted) {
          _showMessage(
            t('postRecordingForm.recordingForm.dialogs.error.saveFailed'),
          );
        }
        return;
      }

      if (!mounted) {
        // The complete aggregate is already durable and can be recovered from
        // local recordings even if this route disappeared while SQLite wrote.
        shouldShutdownRuntime = true;
        return;
      }
      shouldShutdownRuntime = true;
      _openRecordingForm(persistedDraft);
    } finally {
      if (shouldShutdownRuntime || !mounted) {
        await _shutdownRecordingRuntime();
      }
      if (mounted) {
        _update(() {
          _isFinishingRecording = false;
        });
      }
    }
  }

  Future<bool> changeConfirmation() async {
    if (_isDiscardingRecording ||
        _isFinishingRecording ||
        _isProcessingRecording) {
      return false;
    }

    await _foregroundServiceEntryCompleter.future;
    if (!mounted) return false;

    if (_draftPersistenceMayHaveCommitted) {
      logger.w(
        'Leaving the recorder while retaining files from an ambiguously '
        'acknowledged draft commit.',
      );
      await _shutdownRecordingRuntime();
      return true;
    }

    final bool hasRecordingToDiscard =
        _recordState == RecordState.record ||
        _recordState == RecordState.pause ||
        recording ||
        segmentPaths.isNotEmpty ||
        filepath.isNotEmpty;
    if (!hasRecordingToDiscard) {
      return true;
    }

    if (mounted) {
      _update(() {
        _isDiscardingRecording = true;
      });
    } else {
      return false;
    }

    try {
      final bool discard = await _confirmDiscard();

      if (discard) {
        try {
          await _discardRecordingResources();
        } catch (error, stackTrace) {
          logger.e(
            'Discard was cancelled because recording runtime cleanup failed.',
            error: error,
            stackTrace: stackTrace,
          );

          if (mounted) {
            _showMessage(t('streamRec.errors.foregroundServiceCleanup'));
          }
          return false;
        }
      }
      return discard;
    } finally {
      if (mounted) {
        _update(() {
          _isDiscardingRecording = false;
        });
      } else {
        _isDiscardingRecording = false;
      }
    }
  }

  Future<void> _discardRecording() async {
    if (_isFinishingRecording ||
        _isDiscardingRecording ||
        _isProcessingRecording) {
      return;
    }

    final bool discard = await changeConfirmation();
    if (!discard || !mounted) return;

    _replaceRecorder();
  }

  void _openRecordingForm(RecordingDraftHandoff persistedDraft) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RecordingForm(
          filepath: recordedFilePath!,
          startTime: overallStartTime!,
          currentPosition: currentPosition,
          recordingParts: recordingPartsList,
          recordingPartsTimeList: recordingPartsTimeList,
          route: _liveRoute,
          persistedDraft: persistedDraft,
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: Text(t('streamRec.dialogs.confirmExit.title')),
              content: Text(t('streamRec.dialogs.confirmExit.message')),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(t('streamRec.dialogs.confirmExit.cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(t('streamRec.dialogs.confirmExit.confirm')),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _replaceRecorder() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            LiveRec(foregroundService: _foregroundService),
        settings: const RouteSettings(name: '/Recorder'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}
