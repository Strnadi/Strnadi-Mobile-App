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
import 'package:strnadi/recording/location/recording_location_subscription.dart';
import 'package:strnadi/PostRecordingForm/RecordingForm.dart';
import 'package:strnadi/PostRecordingForm/recording_draft_handoff.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/localRecordings/incomplete_upload_prompt.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/location/location_resolution.dart';
import 'package:strnadi/recording/audio/raw_pcm_capture.dart';
import 'package:strnadi/recording/platform/recording_foreground_service.dart';
import 'package:strnadi/recording/audio/recording_path.dart';
import 'package:strnadi/recording/location/recording_permission.dart';
import 'package:strnadi/recording/session/recording_resource_cleanup.dart';
import 'package:strnadi/recording/session/recording_state_reducer.dart';
import 'package:strnadi/recording/audio/wav/wav.dart'; // Contains createWavHeader & concatWavFiles
import 'package:strnadi/recording/platform/recording_live_activity.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/recording_screen.dart';
import '../audio/recording_audio_settings.dart';
import '../location/recording_location_permission.dart';
import '../platform/recording_task_handler.dart';
import '../widgets/recording_dialogs.dart';
import 'elapsed_timer.dart';

part 'recording_capture.dart';
part 'recording_runtime.dart';
part 'recording_segments.dart';
part 'recording_files.dart';
part 'recording_location.dart';
part 'recording_completion.dart';
part 'recording_activity.dart';

final logger = AppLogger(scope: 'recording.streamRec');

/// Owns one recorder route's session, asynchronous operations and recovery state.
/// Parts group tightly coupled transitions; audio and platform boundaries are
/// independent libraries. The screen owns and disposes this controller.
class RecordingController extends ChangeNotifier {
  RecordingController({required this.contextProvider, this.foregroundService});

  final BuildContext Function() contextProvider;
  final RecordingForegroundService? foregroundService;
  bool _disposed = false;
  BuildContext get context => contextProvider();
  bool get mounted => !_disposed && context.mounted;

  Duration get duration => _recordDuration;
  RecordState get recordState => _recordState;
  bool get hasMicPermission => _hasMicPermission;
  bool get isGuestUser => _isGuestUser;
  bool get isProcessing => _isProcessingRecording;
  bool get isFinishing => _isFinishingRecording;
  bool get isDiscarding => _isDiscardingRecording;

  Future<void> toggleRecording() => _toggleRecording();
  Future<void> finishRecording() => _stop();
  Future<void> discardRecording() => _discardRecording();
  Future<bool> confirmExit() => changeConfirmation();

  void _showMessage(String message) {
    if (mounted) showRecordingMessage(context, message);
  }

  void _showGuestRules() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) =>
          GuestUserRules(recorderExitPolicy: changeConfirmation),
    );
  }

  void _update(VoidCallback change) {
    change();
    if (mounted) notifyListeners();
  }

  Duration _recordDuration = Duration.zero;
  String filepath = "";
  late final ElapsedTimer _elapsedTimer;
  late final AudioRecorder _audioRecorder;
  late final Future<void> _audioSettingsReady;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  StreamSubscription<Amplitude>? _amplitudeSub;
  int sampleRate = defaultRecordingSampleRate;
  int bitRate = calcBitRate(defaultRecordingSampleRate, recordingPcmBitDepth);
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

  final _liveActivity = RecordingLiveActivity();
  Future<void> _liveActivityOperations = Future<void>.value();
  String? _liveActivitySessionID;

  DateTime? _recordingInterruptedAt;

  // Fail closed until secure storage confirms an authenticated user. This
  // prevents the notification bell from refreshing account data for guests.
  bool _isGuestUser = true;

  void initialize() {
    _foregroundService =
        foregroundService ?? const FlutterRecordingForegroundService();
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
      _update(() {
        _hasMicPermission = allowed;
      });
    });
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    _elapsedTimer = ElapsedTimer(
      onTick: (elapsed) {
        if (!mounted) return;
        _update(() {
          _recordDuration = elapsed;
        });
      },
    );
    _liveActivity.setActionHandler(_handleLiveActivityAction);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      bool shown = prefs.getBool('popupShown') ?? false;
      bool isGuest = await FlutterSecureStorage().read(key: 'userId') == null;
      if (!mounted) return;
      if (!shown && isGuest) {
        _showGuestRules();
        await prefs.setBool('popupShown', true);
      }
    });
  }

  Future<void> _initAudioSettings() async {
    final settings = await RecordingAudioSettings.load();
    sampleRate = settings.sampleRate;
    bitRate = settings.bitRate;
  }

  Future<void> _loadGuestStatus() async {
    final storage = const FlutterSecureStorage();
    final userId = await storage.read(key: 'userId');
    if (!mounted) return;
    _update(() {
      _isGuestUser = userId == null || userId.isEmpty;
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
    _disposed = true;
    _liveActivity.setActionHandler(null);
    if (!_foregroundServiceEntryStarted) {
      _completeForegroundServiceEntry();
    }
    _elapsedTimer.dispose();
    unawaited(_disposeRecordingResources());
    super.dispose();
  }
}
