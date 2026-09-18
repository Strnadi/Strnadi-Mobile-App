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

extension _RecordingActivity on RecordingController {
  void _queueLiveActivityOperation(Future<void> Function() operation) {
    _liveActivityOperations = _liveActivityOperations.then((_) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        logger.w(
          'Recording Live Activity operation failed.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  void _startLiveActivity() {
    if (!_liveActivity.isSupportedPlatform) return;

    final sessionID = DateTime.now().microsecondsSinceEpoch.toString();
    _liveActivitySessionID = sessionID;

    final elapsed = _elapsedTimer.elapsed;
    final runningSince = DateTime.now();

    _queueLiveActivityOperation(() async {
      await _liveActivity.start(sessionID: sessionID);

      // Align the activity with the recorder's timer.
      await _liveActivity.update(
        sessionID: sessionID,
        elapsed: elapsed,
        runningSince: runningSince,
      );
    });
  }

  void _updateLiveActivity({required bool isRunning}) {
    final sessionID = _liveActivitySessionID;
    if (sessionID == null) return;

    final elapsed = _elapsedTimer.elapsed;
    final runningSince = isRunning ? DateTime.now() : null;

    _queueLiveActivityOperation(() async {
      await _liveActivity.update(
        sessionID: sessionID,
        elapsed: elapsed,
        runningSince: runningSince,
      );
    });
  }

  void _endLiveActivity() {
    final sessionID = _liveActivitySessionID;
    if (sessionID == null) return;

    _liveActivitySessionID = null;

    _queueLiveActivityOperation(() async {
      await _liveActivity.end(sessionID: sessionID);
    });
  }

  Future<void> _handleLiveActivityAction(
    String sessionID,
    RecordingActivityAction action,
  ) async {
    if (!mounted || sessionID != _liveActivitySessionID) {
      throw PlatformException(code: 'RECORDING_NOT_AVAILABLE');
    }

    if (_isProcessingRecording ||
        _isFinishingRecording ||
        _isDiscardingRecording ||
        _draftPersistenceMayHaveCommitted) {
      throw PlatformException(code: 'RECORDING_BUSY');
    }

    if (action == RecordingActivityAction.stop) {
      // Finish owns its own operation guard and durable draft handoff. Do not
      // set the capture guard first: that would make _stop return immediately.
      await _stop();
      if (_liveActivitySessionID == sessionID) {
        throw PlatformException(code: 'RECORDING_FINISH_FAILED');
      }
      await _liveActivityOperations;
      return;
    }

    final shouldResume = action == RecordingActivityAction.resume;
    final desiredState = shouldResume ? RecordState.record : RecordState.pause;

    // Repeating the same command must not toggle the recording.
    if (_recordState == desiredState) return;

    if (_recordState == RecordState.stop) {
      throw PlatformException(code: 'RECORDING_NOT_AVAILABLE');
    }

    _update(() {
      _isProcessingRecording = true;
    });

    try {
      if (shouldResume) {
        // Use the same permission source as the recorder, without displaying
        // a permission prompt from a background Live Activity action.
        final hasMicrophonePermission = await _audioRecorder.hasPermission(
          request: false,
        );
        final locationPermission = await Geolocator.checkPermission();

        if (!hasMicrophonePermission) {
          throw PlatformException(code: 'RESUME_MICROPHONE_PERMISSION');
        }
        if (!isUsableRecordingLocationPermission(locationPermission)) {
          throw PlatformException(
            code: 'RESUME_LOCATION_PERMISSION',
            message: 'Open Strnadi to restore recording permissions.',
          );
        }
      }

      // The screen could have been disposed while checking permissions.
      if (!mounted || sessionID != _liveActivitySessionID) {
        throw PlatformException(code: 'RECORDING_NOT_AVAILABLE');
      }

      if (shouldResume) {
        await _resume(fromLiveActivity: true);
      } else {
        await _pause();
      }

      if (!mounted ||
          sessionID != _liveActivitySessionID ||
          _recordState != desiredState) {
        throw PlatformException(code: 'RECORDING_ACTION_FAILED');
      }

      // Wait for the activity's queued state update before replying.
      await _liveActivityOperations;
    } catch (error, stackTrace) {
      logger.w(
        'Live Activity recording action failed.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (mounted) {
        _update(() {
          _isProcessingRecording = false;
        });
      }
    }
  }
}
