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

extension _RecordingRuntime on RecordingController {
  void _completeForegroundServiceEntry() {
    if (!_foregroundServiceEntryCompleter.isCompleted) {
      _foregroundServiceEntryCompleter.complete();
    }
  }

  Future<void> _reconcileForegroundServiceOnRecorderEntry() async {
    try {
      await reconcileStaleRecordingForegroundService(
        service: _foregroundService,
      );
    } catch (error, stackTrace) {
      logger.e(
        'Failed to reconcile the recording foreground service on entry.',
        error: error,
        stackTrace: stackTrace,
      );

      if (mounted) {
        _showMessage(t('streamRec.errors.foregroundServiceCleanup'));
      }
    } finally {
      _completeForegroundServiceEntry();
    }
  }

  Future<void> _ensureRecordingForegroundService() async {
    if (await _foregroundService.isRunning()) {
      await _foregroundService.update(
        notificationTitle: 'Strnadi',
        notificationText: t('streamRec.notifications.recordingInProgress'),
      );
      return;
    }

    await _foregroundService.start(
      notificationTitle: 'Strnadi',
      notificationText: t('streamRec.notifications.recordingInProgress'),
      callback: startRecordingCallback,
    );
  }

  Future<void> _showPausedForegroundNotification({
    required String action,
  }) async {
    try {
      if (!await _foregroundService.isRunning()) {
        return;
      }
      await _foregroundService.update(
        notificationTitle: 'Strnadi',
        notificationText: t('streamRec.notifications.recordingPaused'),
      );
    } catch (error, stackTrace) {
      logger.e(
        'Error updating paused recording notification while $action.',
        error: error,
        stackTrace: stackTrace,
      );

      // A stale "recording in progress" notification is worse than having no
      // paused notification. Remove the service if its content cannot be made
      // truthful; resume will start it again.
      await stopRecordingForegroundService(service: _foregroundService);
    }
  }

  Future<void> _shutdownRecordingRuntime({bool stopRecorder = true}) {
    final Future<void>? inFlight = _runtimeShutdownFuture;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> shutdown;
    shutdown = _performRecordingRuntimeShutdown(stopRecorder: stopRecorder);
    _runtimeShutdownFuture = shutdown;
    return shutdown.whenComplete(() {
      if (identical(_runtimeShutdownFuture, shutdown)) {
        _runtimeShutdownFuture = null;
      }
    });
  }

  Future<void> _performRecordingRuntimeShutdown({
    required bool stopRecorder,
  }) async {
    _elapsedTimer.pause();
    _endLiveActivity();

    bool shouldStopRecorder = _recordState == RecordState.record || recording;
    if (stopRecorder && !shouldStopRecorder) {
      try {
        shouldStopRecorder = await _audioRecorder.isRecording();
      } catch (e, stackTrace) {
        logger.e(
          'Error checking recorder state during lifecycle cleanup: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    if (stopRecorder && shouldStopRecorder) {
      try {
        await _audioRecorder.stop();
        await _finishActiveRawPcmCapture();
      } catch (e, stackTrace) {
        try {
          await _abortActiveRawPcmCapture();
        } catch (_) {
          // Preserve the recorder/shutdown failure.
        }
        logger.e(
          'Error stopping recorder during lifecycle cleanup: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    try {
      await _locationSub?.cancel();
    } catch (e, stackTrace) {
      logger.e(
        'Error cancelling location subscription: $e',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      _locationSub = null;
    }

    try {
      await WakelockPlus.disable();
    } catch (e, stackTrace) {
      logger.e(
        'Error disabling wakelock: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      await stopRecordingForegroundService(service: _foregroundService);
    } catch (e, stackTrace) {
      logger.e(
        'Error stopping foreground recording service: $e',
        error: e,
        stackTrace: stackTrace,
      );

      Error.throwWithStackTrace(e, stackTrace);
    }
  }
}
