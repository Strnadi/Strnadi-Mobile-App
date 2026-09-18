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

extension _RecordingCapture on RecordingController {
  Future<void> _toggleRecording() async {
    if (_isProcessingRecording ||
        _isFinishingRecording ||
        _isDiscardingRecording) {
      return;
    }

    _update(() {
      _isProcessingRecording = true;
    });
    try {
      await _foregroundServiceEntryCompleter.future;
      if (!mounted) return;
      // Revoked GPS/microphone permission must never prevent stopping an
      // existing segment. Permissions are needed only to start or resume.
      if (_recordState == RecordState.record) {
        await _pause();
        return;
      }
      if (!_hasMicPermission) {
        // Request microphone permission
        var status = await Permission.microphone.request();
        if (status.isGranted) {
          if (!mounted) return;
          _update(() {
            _hasMicPermission = true;
          });
        } else {
          if (!mounted) return;
          _showMessage(t('streamRec.errors.micPermission'));
          return;
        }
      }
      // Check and request location permission before recording
      LocationPermission locationPerm = await Geolocator.checkPermission();
      if (!isUsableRecordingLocationPermission(locationPerm)) {
        locationPerm = await Geolocator.requestPermission();
      }
      if (!isUsableRecordingLocationPermission(locationPerm)) {
        if (!mounted) return;
        _showMessage(t('streamRec.errors.locationPermission'));
        return;
      }
      if (_recordState == RecordState.pause) {
        await _resume();
      } else {
        await _start();
      }
    } catch (e, stackTrace) {
      if (e is RecordingForegroundServiceStopException ||
          e is RecordingForegroundServiceOperationException) {
        logger.e(
          'Recording notification lifecycle operation failed.',
          error: e,
          stackTrace: stackTrace,
        );

        if (mounted) {
          _showMessage(t('streamRec.errors.foregroundServiceCleanup'));
        }
      } else if (_segmentFinalizationPending) {
        _reportSegmentFinalizationFailure(e, stackTrace);
      } else {
        logger.e(
          "Error toggling recording: $e",
          error: e,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) {
        _update(() {
          _isProcessingRecording = false;
        });
      }
    }
  }

  Duration get _currentSegmentElapsed {
    final Duration elapsed = _elapsedTimer.elapsed - _segmentElapsedBaseline;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _start() async {
    // Request location permission for recording
    if (!await getLocationPermission(context)) return;
    if (!mounted) return;

    await _audioSettingsReady;
    if (!mounted) return;

    // Start caching location only while this screen has an active listener.
    _locService = LocationService();

    final LatLng? startLocation = await _resolveSegmentStartLocation(
      action: 'starting recording',
      allowLastKnownFallback: false,
    );
    if (!mounted) return;
    if (startLocation == null) {
      _showMessage(t('streamRec.errors.locationFetchError'));
      return;
    }
    _update(() => _rememberSegmentStartLocation(startLocation));

    await _locationSub?.cancel();
    if (!mounted) return;
    bool locationFailureShown = false;
    _locationSub = subscribeToRecordingLocation(
      positions: _locService.positionStream,
      onPosition: (position) {
        if (!mounted) return;
        locationFailureShown = false;
        final now = DateTime.now();
        if (_lastRouteUpdateTime == null ||
            now.difference(_lastRouteUpdateTime!) >= Duration(seconds: 5)) {
          _update(() {
            currentPosition = LatLng(position.latitude, position.longitude);
            _liveRoute.add(LatLng(position.latitude, position.longitude));
            _lastRouteUpdateTime = now;
          });
        }
      },
      onFailure: (error, stackTrace) {
        if (!mounted || locationFailureShown) return;
        locationFailureShown = true;
        logger.w(
          'Recording location updates are unavailable.',
          error: error,
          stackTrace: stackTrace,
        );
        _showMessage(t('streamRec.errors.locationFetchError'));
      },
    );

    bool recorderStarted = false;
    try {
      await _ensureRecordingForegroundService();

      logger.i('Started recording');
      // Stream PCM bytes to a file owned by Dart. Native file recording can
      // add a WAV/CAF container on iOS even when pcm16bits is requested.
      final ReservedRawPcmFile reservedFile = await _reserveRawPcmPath(
        excludedPaths: segmentPaths,
      );
      filepath = reservedFile.path;
      await WakelockPlus.enable();

      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: sampleRate,
        bitRate: bitRate,
      );
      _logicalPauseOwnsRecorderState = false;
      _rawPcmCapture = await RawPcmCapture.start(
        reservedFile: reservedFile,
        startStream: () async {
          final Stream<List<int>> stream = await _audioRecorder.startStream(
            config,
          );
          recorderStarted = true;
          return stream;
        },
      );
      segmentPaths.add(filepath);

      if (!mounted) {
        await _cleanupFailedRecordingStart(recorderStarted: recorderStarted);
        return;
      }

      final DateTime startTime = DateTime.now();
      overallStartTime = startTime;
      logger.i('Overall start time: $overallStartTime');
      // Create a new segment metadata object
      recordedPart = RecordingPartUnready(
        path: null,
        gpsLongitudeStart: startLocation.longitude,
        gpsLatitudeStart: startLocation.latitude,
        startTime: startTime,
      );
      logger.i('Recorded part start time: ${recordedPart!.startTime}');
      _elapsedTimer.reset();
      _segmentElapsedBaseline = Duration.zero;
      _elapsedTimer.start();
      _update(() {
        recording = true;
        _recordState = RecordState.record;
      });
      _startLiveActivity();
    } catch (e, stackTrace) {
      await _cleanupFailedRecordingStart(recorderStarted: recorderStarted);
      logger.e(
        'Starting audio recording failed.',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _pause() async {
    await _stopActiveSegmentForFinalization(action: 'pausing recording');
    await _finalizePendingSegment();
  }

  Future<void> _resume({bool fromLiveActivity = false}) async {
    await _finalizeInterruptedSegment();
    if (_segmentFinalizationPending) {
      await _finalizePendingSegment();
    }
    await _audioSettingsReady;
    if (!mounted) return;

    final LatLng? startLocation = await _resolveSegmentStartLocation(
      action: 'resuming recording',
    );
    if (!mounted) return;
    if (startLocation == null) {
      if (fromLiveActivity) {
        throw PlatformException(code: 'RESUME_LOCATION_UNAVAILABLE');
      }
      _showMessage(t('streamRec.errors.locationFetchError'));
      return;
    }

    final ReservedRawPcmFile reservedFile = await _reserveRawPcmPath(
      excludedPaths: segmentPaths,
    );
    final String path = reservedFile.path;
    if (!mounted) {
      await reservedFile.writer.close();
      await File(path).delete();
      return;
    }

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: 1,
      sampleRate: sampleRate,
      bitRate: bitRate,
    );

    bool recorderStarted = false;
    bool captureStartAttempted = false;
    try {
      await _ensureRecordingForegroundService();
      await WakelockPlus.enable();
      captureStartAttempted = true;
      _rawPcmCapture = await RawPcmCapture.start(
        reservedFile: reservedFile,
        startStream: () async {
          final Stream<List<int>> stream = await _audioRecorder.startStream(
            config,
          );
          recorderStarted = true;
          return stream;
        },
      );
    } catch (e) {
      if (!captureStartAttempted) {
        try {
          await reservedFile.writer.close();
        } catch (_) {
          // Keep the original resume failure.
        }
      }
      if (recorderStarted) {
        try {
          await _audioRecorder.stop();
          await _finishActiveRawPcmCapture();
        } catch (_) {
          try {
            await _abortActiveRawPcmCapture();
          } catch (_) {
            // Keep the original start failure.
          }
        }
      }
      try {
        await WakelockPlus.disable();
      } catch (_) {
        // Keep the original recorder failure.
      }
      try {
        await _showPausedForegroundNotification(
          action: 'recovering from a failed resume',
        );
      } catch (_) {
        // Keep the original recorder failure.
      }
      try {
        final File failedFile = File(path);
        if (await failedFile.exists()) {
          await failedFile.delete();
        }
      } catch (_) {
        // Keep the original recorder failure.
      }
      rethrow;
    }

    if (!mounted) {
      try {
        await _audioRecorder.stop();
        await _finishActiveRawPcmCapture();
      } catch (_) {
        try {
          await _abortActiveRawPcmCapture();
        } catch (_) {
          // The widget is gone; continue releasing remaining resources.
        }
        // The widget is gone; continue releasing the remaining resources.
      }
      try {
        await WakelockPlus.disable();
      } catch (_) {
        // The widget is gone; continue releasing the remaining resources.
      }
      await _shutdownRecordingRuntime(stopRecorder: false);
      try {
        final File abandonedFile = File(path);
        if (await abandonedFile.exists()) {
          await abandonedFile.delete();
        }
      } catch (e, stackTrace) {
        logger.e(
          'Error deleting abandoned resumed segment $path: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
      return;
    }

    filepath = path;
    segmentPaths.add(path);
    recordedPart = RecordingPartUnready(
      path: null,
      gpsLongitudeStart: startLocation.longitude,
      gpsLatitudeStart: startLocation.latitude,
      startTime: DateTime.now(),
    );
    logger.i('New segment start time: ${recordedPart!.startTime}');
    _segmentElapsedBaseline = _elapsedTimer.elapsed;
    _elapsedTimer.resume();
    _update(() {
      _rememberSegmentStartLocation(startLocation);
      recording = true;
      _recordState = RecordState.record;
      _logicalPauseOwnsRecorderState = false;
    });
    _updateLiveActivity(isRunning: true);
  }

  void _updateRecordState(RecordState recordState) {
    if (!mounted) return;

    final nativePause =
        recordState == RecordState.pause && !_logicalPauseOwnsRecorderState;

    if (nativePause) {
      _recordingInterruptedAt ??= DateTime.now();
      _elapsedTimer.pause();
    }

    _update(() {
      _recordState = reduceRecorderState(
        currentState: _recordState,
        physicalState: recordState,
        logicalPauseOwnsState:
            _logicalPauseOwnsRecorderState || _recordingInterruptedAt != null,
      );

      if (nativePause) {
        recording = false;
        _recordDuration = _elapsedTimer.elapsed;
      }
    });

    if (nativePause) {
      _updateLiveActivity(isRunning: false);
    }
  }
}
