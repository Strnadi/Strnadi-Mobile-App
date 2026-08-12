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
 * streamRec.dart
 */

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/widgets/GuestUserWarning.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/localization/localization.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/PostRecordingForm/recording_draft_handoff.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/localRecordings/incomplete_upload_prompt.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/location/location_resolution.dart';
import 'package:strnadi/recording/raw_pcm_capture.dart';
import 'package:strnadi/recording/recording_foreground_service.dart';
import 'package:strnadi/recording/recording_path.dart';
import 'package:strnadi/recording/recording_permission.dart';
import 'package:strnadi/recording/recording_resource_cleanup.dart';
import 'package:strnadi/recording/recording_state_reducer.dart';
import 'package:strnadi/recording/waw.dart'; // Contains createWavHeader & concatWavFiles
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../navigation/guide_shortcut_button.dart';
import '../navigation/notification_bell_button.dart';
import '../navigation/scaffold_with_bottom_bar.dart';

final logger = Logger();

class RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    logger.i("Foreground task started at $timestamp");
    if (taskStarter == TaskStarter.system) {
      try {
        // Recording is owned by the app isolate and cannot survive a process
        // restart. A system-started task can only be an orphan from an older
        // sticky-service configuration.
        await reconcileStaleRecordingForegroundService(
          service: const FlutterRecordingForegroundService(),
        );
      } catch (error, stackTrace) {
        logger.e(
          'Failed to stop a system-started recording service.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    logger.i("Foreground task destroyed at $timestamp (isTimeout: $isTimeout)");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    logger.i("Foreground task event at $timestamp");
  }
}

void startRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

class ElapsedTimer {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final ValueChanged<Duration> onTick;

  ElapsedTimer({required this.onTick});

  void start() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void pause() {
    _stopwatch.stop();
    _ticker?.cancel();
  }

  void resume() {
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      onTick(_stopwatch.elapsed);
    });
  }

  void reset() {
    _stopwatch.reset();
    _ticker?.cancel();
    onTick(_stopwatch.elapsed);
  }

  Duration get elapsed => _stopwatch.elapsed;

  void dispose() {
    _stopwatch.stop();
    _ticker?.cancel();
  }
}

class LiveRec extends StatefulWidget {
  const LiveRec({
    super.key,
    this.foregroundService,
  });

  final RecordingForegroundService? foregroundService;

  @override
  State<LiveRec> createState() => _LiveRecState();
}

int calcBitRate(int sampleRate, int bitDepth) {
  return sampleRate * bitDepth;
}

void _showMessage(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('streamRec.dialogs.info.title')),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('streamRec.dialogs.info.ok')),
        ),
      ],
    ),
  );
}

Future<bool> getLocationPermission(BuildContext context) async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (!isUsableRecordingLocationPermission(permission) &&
      permission != LocationPermission.deniedForever) {
    permission = await Geolocator.requestPermission();
  }
  if (!context.mounted) return false;
  logger.i("Location permission: $permission");
  if (isUsableRecordingLocationPermission(permission)) {
    return true;
  }

  // A denied-forever status cannot change through another request. Show one
  // actionable message and return instead of repeatedly stacking dialogs.
  _showMessage(context, t('streamRec.errors.locationPermission'));
  return false;
}

class _LiveRecState extends State<LiveRec> {
  static const int _defaultSampleRate = 48000;
  static const int _pcmBitDepth = 16;

  Duration _recordDuration = Duration.zero;
  String filepath = "";
  late final ElapsedTimer _elapsedTimer;
  late final AudioRecorder _audioRecorder;
  late final Future<void> _audioSettingsReady;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  int sampleRate = _defaultSampleRate;
  int bitRate = calcBitRate(_defaultSampleRate, _pcmBitDepth);
  final recordingPartsTimeList = <int>[];
  List<RecordingPartUnready> recordingPartsList = [];
  RecordingPartUnready? recordedPart;
  DateTime? overallStartTime;
  DateTime? segmentStartTime;
  String? recordedFilePath;
  LatLng? currentPosition;
  final List<LatLng> _liveRoute = [];
  DateTime? _lastRouteUpdateTime;
  final List<String> segmentPaths = [];
  StreamSubscription? _locationSub;
  late LocationService _locService;
  bool recording = false;
  bool _hasMicPermission = false;

  bool _isProcessingRecording = false;
  bool _isFinishingRecording = false;
  bool _isDiscardingRecording = false;
  bool _segmentFinalizationPending = false;
  bool _logicalPauseOwnsRecorderState = false;
  bool _draftPersistenceMayHaveCommitted = false;
  Duration _segmentElapsedBaseline = Duration.zero;
  Future<void>? _runtimeShutdownFuture;
  int _recordingPathSequence = 0;
  RawPcmCapture? _rawPcmCapture;
  late final RecordingForegroundService _foregroundService;
  late final Completer<void> _foregroundServiceEntryCompleter;
  bool _foregroundServiceEntryStarted = false;

  // Fail closed until secure storage confirms an authenticated user. This
  // prevents the notification bell from refreshing account data for guests.
  bool _isGuestUser = true;

  @override
  void initState() {
    super.initState();
    _foregroundService =
        widget.foregroundService ?? const FlutterRecordingForegroundService();
    _foregroundServiceEntryCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _foregroundServiceEntryStarted = true;
      if (!mounted) {
        _completeForegroundServiceEntry();
        return;
      }
      unawaited(_reconcileForegroundServiceOnRecorderEntry());
    });
    _loadGuestStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      IncompleteUploadPrompt.checkAndPrompt(context);
    });
    _audioSettingsReady = _initAudioSettings();
    _audioRecorder = AudioRecorder();
    _audioRecorder.hasPermission().then((allowed) {
      if (!mounted) return;
      setState(() {
        _hasMicPermission = allowed;
      });
    });
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    _elapsedTimer = ElapsedTimer(onTick: (elapsed) {
      if (!mounted) return;
      setState(() {
        _recordDuration = elapsed;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool shown = prefs.getBool('popupShown') ?? false;
      bool isGuest = await FlutterSecureStorage().read(key: 'userId') == null;
      if (!mounted) return;
      if (!shown && isGuest) {
        showDialog(
          context: context,
          builder: (context) => GuestUserRules(
            recorderExitPolicy: changeConfirmation,
          ),
        );
        await prefs.setBool('popupShown', true);
      }
    });
  }

  static const MethodChannel _platform =
      MethodChannel('com.delta.strnadi/audio');

  Future<void> _initAudioSettings() async {
    int resolvedSampleRate = _defaultSampleRate;
    try {
      final Map<dynamic, dynamic>? settings =
          await _platform.invokeMethod('getBestAudioSettings');
      final Object? configuredSampleRate = settings?['sampleRate'];
      final int? parsedSampleRate = configuredSampleRate is num
          ? configuredSampleRate.toInt()
          : int.tryParse(configuredSampleRate?.toString() ?? '');
      if (parsedSampleRate != null && parsedSampleRate > 0) {
        resolvedSampleRate = parsedSampleRate;
      }
    } catch (e, stackTrace) {
      logger.e('Failed to get audio settings, using defaults: $e',
          error: e, stackTrace: stackTrace);
    }

    sampleRate = resolvedSampleRate;
    bitRate = calcBitRate(resolvedSampleRate, _pcmBitDepth);
    logger.i('Audio settings: sampleRate=$sampleRate, bitRate=$bitRate');
  }

  Future<void> _toggleRecording() async {
    if (_isProcessingRecording ||
        _isFinishingRecording ||
        _isDiscardingRecording) {
      return;
    }

    setState(() {
      _isProcessingRecording = true;
    });
    try {
      await _foregroundServiceEntryCompleter.future;
      if (!mounted) return;
      if (!_hasMicPermission) {
        // Request microphone permission
        var status = await Permission.microphone.request();
        if (status.isGranted) {
          if (!mounted) return;
          setState(() {
            _hasMicPermission = true;
          });
        } else {
          if (!mounted) return;
          _showMessage(context, t('streamRec.errors.micPermission'));
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
        _showMessage(context, t('streamRec.errors.locationPermission'));
        return;
      }
      if (_recordState == RecordState.record) {
        await _pause();
      } else if (_recordState == RecordState.pause) {
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
        Sentry.captureException(e, stackTrace: stackTrace);
        if (mounted) {
          _showMessage(
            context,
            t('streamRec.errors.foregroundServiceCleanup'),
          );
        }
      } else if (_segmentFinalizationPending) {
        _reportSegmentFinalizationFailure(e, stackTrace);
      } else {
        logger.e("Error toggling recording: $e",
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingRecording = false;
        });
      }
    }
  }

  Duration get _currentSegmentElapsed {
    final Duration elapsed = _elapsedTimer.elapsed - _segmentElapsedBaseline;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

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
      Sentry.captureException(error, stackTrace: stackTrace);
      if (mounted) {
        _showMessage(
          context,
          t('streamRec.errors.foregroundServiceCleanup'),
        );
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
      Sentry.captureException(error, stackTrace: stackTrace);

      // A stale "recording in progress" notification is worse than having no
      // paused notification. Remove the service if its content cannot be made
      // truthful; resume will start it again.
      await stopRecordingForegroundService(service: _foregroundService);
    }
  }

  Future<void> _shutdownRecordingRuntime({
    bool stopRecorder = true,
  }) {
    final Future<void>? inFlight = _runtimeShutdownFuture;
    if (inFlight != null) {
      return inFlight;
    }

    late final Future<void> shutdown;
    shutdown = _performRecordingRuntimeShutdown(
      stopRecorder: stopRecorder,
    );
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
        Sentry.captureException(e, stackTrace: stackTrace);
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
      Sentry.captureException(e, stackTrace: stackTrace);
      Error.throwWithStackTrace(e, stackTrace);
    }
  }

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
        Sentry.captureException(e, stackTrace: stackTrace);
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
    }

    if (mounted) {
      setState(reset);
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

  Future<void> _finishPartLocation(
    RecordingPartUnready part, {
    required String action,
  }) async {
    try {
      final loc = await _locService.getCurrentLocation();
      part.gpsLatitudeEnd = loc.latitude;
      part.gpsLongitudeEnd = loc.longitude;
    } catch (e, stackTrace) {
      logger.e(
        'Error fetching location on $action: $e',
        error: e,
        stackTrace: stackTrace,
      );
      part.gpsLatitudeEnd ??= part.gpsLatitudeStart;
      part.gpsLongitudeEnd ??= part.gpsLongitudeStart;
    }
  }

  void _setRecorderPausedForFinalization() {
    void update() {
      recording = false;
      _recordState = RecordState.pause;
      _logicalPauseOwnsRecorderState = true;
    }

    if (mounted) {
      setState(update);
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

    final DateTime segmentStoppedAt = DateTime.now();
    part.endTime = segmentStoppedAt;
    logger.i('Segment end time: ${part.endTime}');
    _elapsedTimer.pause();
    _segmentFinalizationPending = true;
    _setRecorderPausedForFinalization();

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
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  void _reportSegmentFinalizationFailure(
    Object error,
    StackTrace stackTrace,
  ) {
    logger.e(
      'Error finalizing recorded segment: $error',
      error: error,
      stackTrace: stackTrace,
    );
    Sentry.captureException(error, stackTrace: stackTrace);
    if (mounted) {
      _showMessage(context, t('streamRec.errors.segmentFinalizeError'));
    }
  }

  Future<LatLng?> _resolveSegmentStartLocation({
    required String action,
    bool allowLastKnownFallback = true,
  }) async {
    try {
      final LatLng current = await _locService.getCurrentLocation(
        allowLastKnownFallback: allowLastKnownFallback,
      );
      if (isValidLocation(current)) {
        return current;
      }
      logger.w('Ignoring invalid location while $action.');
    } catch (e, stackTrace) {
      logger.e(
        'Error fetching location while $action: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return null;
  }

  void _rememberSegmentStartLocation(LatLng location) {
    currentPosition = location;
    final bool isNewPoint = _liveRoute.isEmpty ||
        _liveRoute.last.latitude != location.latitude ||
        _liveRoute.last.longitude != location.longitude;
    if (isNewPoint) {
      _liveRoute.add(location);
    }
    _lastRouteUpdateTime = DateTime.now();
  }

  Future<void> _stop() async {
    if (_isFinishingRecording || _isProcessingRecording || !mounted) return;
    if (_draftPersistenceMayHaveCommitted) {
      _showMessage(
        context,
        t('streamRec.errors.saveStatusUnknown'),
      );
      return;
    }
    bool shouldShutdownRuntime = false;
    setState(() {
      _isFinishingRecording = true;
    });

    try {
      if (filepath.isEmpty) {
        _showMessage(context, t('streamRec.errors.noRecordingFound'));
        return;
      }
      if (_recordState == RecordState.record) {
        try {
          await _stopActiveSegmentForFinalization(
            action: 'stopping recording',
          );
          await _finalizePendingSegment();
        } catch (e, stackTrace) {
          _reportSegmentFinalizationFailure(e, stackTrace);
          return;
        }
        if (!mounted) return;
        setState(() {
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
        setState(() {
          recording = false;
        });
      }
      final List<String> paths = List<String>.from(segmentPaths);
      String? outputPath = recordedFilePath;
      if (outputPath == null || !await File(outputPath).exists()) {
        outputPath = await _getPath(
          excludedPaths: paths,
        );
        try {
          await concatWavFiles(paths, outputPath);
          recordedFilePath = outputPath;
          logger.i('Final recording saved.');
        } catch (e, stackTrace) {
          logger.e("Error concatenating files: $e",
              error: e, stackTrace: stackTrace);
          Sentry.captureException(e, stackTrace: stackTrace);
          return;
        }
      }
      if (overallStartTime == null) return;
      if (!mounted) return;

      late final RecordingDraftHandoff persistedDraft;
      try {
        persistedDraft =
            await RecordingDraftHandoffCoordinator.database().persistCapture(
          filepath: recordedFilePath!,
          startTime: overallStartTime!,
          recordingParts: recordingPartsList,
          recordingPartDurations: recordingPartsTimeList,
          environment: Config.hostEnvironment.name,
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
        Sentry.captureException(error, stackTrace: stackTrace);
        if (mounted) {
          _showMessage(
            context,
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
    } finally {
      if (shouldShutdownRuntime || !mounted) {
        await _shutdownRecordingRuntime();
      }
      if (mounted) {
        setState(() {
          _isFinishingRecording = false;
        });
      }
    }
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

  Future<void> _loadGuestStatus() async {
    final storage = const FlutterSecureStorage();
    final userId = await storage.read(key: 'userId');
    if (!mounted) return;
    setState(() {
      _isGuestUser = userId == null || userId.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalTime = _recordDuration;

    // Define custom colors to match your design.
    final Color primaryRed = const Color(0xFFFF3B3B);
    final Color secondaryRed = const Color(0xFFFFEDED);

    // Determine button colors, border, and shadow based on recording state.
    IconData iconData = Icons.mic;
    Color fillColor = primaryRed;
    Color iconColor = Colors.white;
    Border? border;
    List<BoxShadow> boxShadows = [];

    if (_recordState == RecordState.stop) {
      // Stop state: filled red circle with white mic icon.
      iconData = Icons.mic;
      fillColor = primaryRed;
      iconColor = Colors.white;
      border = null;
      boxShadows = [];
    } else if (_recordState == RecordState.record) {
      // Recording (pause button visible): white circle, thicker red border, red icon + glow.
      iconData = Icons.pause;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withValues(alpha: 0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    } else if (_recordState == RecordState.pause) {
      // Paused (play button visible): white circle, thicker red border, red icon + glow.
      iconData = Icons.play_arrow;
      fillColor = secondaryRed;
      iconColor = primaryRed;
      border = Border.all(color: primaryRed, width: 5);
      boxShadows = [
        BoxShadow(
          color: primaryRed.withValues(alpha: 0.4),
          blurRadius: 15,
          spreadRadius: 3,
        ),
      ];
    }

    // Create the scaffold widget.
    final scaffoldWidget = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: GuideShortcutButton(
          recorderExitPolicy: changeConfirmation,
        ),
        actions: [
          NotificationBellButton(
            isGuestUser: _isGuestUser,
            recorderExitPolicy: changeConfirmation,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(top: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image banner at top
            LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final imageHeight = screenHeight * 0.25;
                return SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.0),
                      child: Image.asset(
                        'assets/images/bird_example.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // Recording button with vertical padding.
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Opacity(
                opacity: _hasMicPermission ? 1.0 : 0.5,
                child: AbsorbPointer(
                  absorbing: _isProcessingRecording,
                  child: Semantics(
                    label: _recordState == RecordState.stop
                        ? t('streamRec.buttons.startRecording')
                        : _recordState == RecordState.record
                            ? t('streamRec.buttons.pauseRecording')
                            : t('streamRec.buttons.resumeRecording'),
                    button: true,
                    child: GestureDetector(
                      onTap: _toggleRecording,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: fillColor,
                          border: border,
                          boxShadow: boxShadows,
                        ),
                        child: _recordState == RecordState.pause
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.play_arrow,
                                    size: 40,
                                    color: iconColor,
                                  ),
                                  Icon(
                                    Icons.mic,
                                    size: 20,
                                    color: iconColor,
                                  ),
                                ],
                              )
                            : Icon(
                                iconData,
                                color: iconColor,
                                size: 40,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Timer display
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: _recordState == RecordState.record
                      ? primaryRed
                      : Colors.grey,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: Text(
                _formatTime(totalTime),
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Status text
            if (_recordState == RecordState.stop) ...[
              Text(
                t('streamRec.status.stopped'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ] else if (_recordState == RecordState.record) ...[
              Text(
                t('streamRec.status.recording'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ] else if (_recordState == RecordState.pause) ...[
              Text(
                t('streamRec.status.paused'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: 'Bricolage Grotesque',
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Finish button
            if (_recordState == RecordState.record ||
                _recordState == RecordState.pause)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isFinishingRecording ||
                            _isDiscardingRecording ||
                            _isProcessingRecording
                        ? null
                        : _stop,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: secondaryRed,
                      foregroundColor: primaryRed,
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Bricolage Grotesque',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.stop, color: primaryRed),
                        const SizedBox(width: 8),
                        Text(
                          t('streamRec.buttons.finishRecording'),
                          style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Discard button
            if (_recordState == RecordState.record ||
                _recordState == RecordState.pause)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isFinishingRecording ||
                            _isDiscardingRecording ||
                            _isProcessingRecording
                        ? null
                        : _discardRecording,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Bricolage Grotesque',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          t('streamRec.buttons.discardRecording'),
                          style: TextStyle(fontFamily: 'Bricolage Grotesque'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: ReusableBottomAppBar(
        currentPage: BottomBarItem.recorder,
        changeConfirmation: changeConfirmation,
        isGuestUser: _isGuestUser,
      ),
    );
    // Return the PopScope widget with an onPopInvokedWithResult callback that completes without returning any widget.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await _discardRecording();
      },
      child: scaffoldWidget,
    );
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

    final bool hasRecordingToDiscard = _recordState == RecordState.record ||
        _recordState == RecordState.pause ||
        recording ||
        segmentPaths.isNotEmpty ||
        filepath.isNotEmpty;
    if (!hasRecordingToDiscard) {
      return true;
    }

    if (mounted) {
      setState(() {
        _isDiscardingRecording = true;
      });
    } else {
      return false;
    }

    try {
      final bool discard = await showDialog<bool>(
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

      if (discard) {
        try {
          await _discardRecordingResources();
        } catch (error, stackTrace) {
          logger.e(
            'Discard was cancelled because recording runtime cleanup failed.',
            error: error,
            stackTrace: stackTrace,
          );
          Sentry.captureException(error, stackTrace: stackTrace);
          if (mounted) {
            _showMessage(
              context,
              t('streamRec.errors.foregroundServiceCleanup'),
            );
          }
          return false;
        }
      }
      return discard;
    } finally {
      if (mounted) {
        setState(() {
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

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LiveRec(
          foregroundService: _foregroundService,
        ),
        settings: const RouteSettings(name: '/Recorder'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
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
      _showMessage(context, t('streamRec.errors.locationFetchError'));
      return;
    }
    setState(() => _rememberSegmentStartLocation(startLocation));

    _locationSub = _locService.positionStream.listen((position) {
      if (!mounted) return;
      final now = DateTime.now();
      if (_lastRouteUpdateTime == null ||
          now.difference(_lastRouteUpdateTime!) >= Duration(seconds: 5)) {
        setState(() {
          currentPosition = LatLng(position.latitude, position.longitude);
          _liveRoute.add(LatLng(position.latitude, position.longitude));
          _lastRouteUpdateTime = now;
        });
      }
    });

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
          final Stream<List<int>> stream =
              await _audioRecorder.startStream(config);
          recorderStarted = true;
          return stream;
        },
      );
      segmentPaths.add(filepath);

      if (!mounted) {
        await _cleanupFailedRecordingStart(
          recorderStarted: recorderStarted,
        );
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
      setState(() {
        recording = true;
        _recordState = RecordState.record;
      });
    } catch (e, stackTrace) {
      await _cleanupFailedRecordingStart(
        recorderStarted: recorderStarted,
      );
      logger.e("An error has occurred: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  String _formatTime(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final hundredths =
        ((duration.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$minutes:$seconds,$hundredths';
  }

  Future<void> _pause() async {
    await _stopActiveSegmentForFinalization(action: 'pausing recording');
    await _finalizePendingSegment();
  }

  Future<void> _resume() async {
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
      _showMessage(context, t('streamRec.errors.locationFetchError'));
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
          final Stream<List<int>> stream =
              await _audioRecorder.startStream(config);
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
    setState(() {
      _rememberSegmentStartLocation(startLocation);
      recording = true;
      _recordState = RecordState.record;
      _logicalPauseOwnsRecorderState = false;
    });
  }

  void _updateRecordState(RecordState recordState) {
    if (!mounted) return;
    setState(() {
      _recordState = reduceRecorderState(
        currentState: _recordState,
        physicalState: recordState,
        logicalPauseOwnsState: _logicalPauseOwnsRecorderState,
      );
    });
  }

  Future<void> _disposeRecordingResources() async {
    try {
      await _recordSub?.cancel();
    } catch (e, stackTrace) {
      logger.e(
        'Error cancelling recorder state subscription during dispose: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
    try {
      await _amplitudeSub?.cancel();
    } catch (e, stackTrace) {
      logger.e(
        'Error cancelling amplitude subscription during dispose: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    await _foregroundServiceEntryCompleter.future;
    await shutdownRuntimeThenDisposeRecorder(
      shutdownRuntime: () async {
        try {
          await _shutdownRecordingRuntime();
        } catch (e, stackTrace) {
          logger.e(
            'Error shutting down recording runtime during dispose: $e',
            error: e,
            stackTrace: stackTrace,
          );
        }
      },
      disposeRecorder: () async {
        try {
          await _audioRecorder.dispose();
        } catch (e, stackTrace) {
          logger.e(
            'Error disposing recorder after runtime shutdown: $e',
            error: e,
            stackTrace: stackTrace,
          );
        }
      },
    );
  }

  @override
  void dispose() {
    if (!_foregroundServiceEntryStarted) {
      _completeForegroundServiceEntry();
    }
    _elapsedTimer.dispose();
    unawaited(_disposeRecordingResources());
    super.dispose();
  }
}
