import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/dialects/dialect_time_resolver.dart';
import 'package:strnadi/localization/localization.dart';
import 'recording_audio_player.dart';
import 'recording_detail_repository.dart';
import 'recording_dialect_entry.dart';
import 'recording_dialect_resolver.dart';

enum RecordingDetailActionResult {
  success,
  restricted,
  unavailable,
  canceled,
  stale,
}

/// Owns recording-detail loading, playback and download lifecycles.
class RecordingDetailController extends ChangeNotifier {
  RecordingDetailController({
    required Recording recording,
    required RecordingAudioPlayer audio,
    RecordingDetailRepository repository =
        const DatabaseRecordingDetailRepository(),
  }) : _recording = recording,
       _audio = audio,
       _repository = repository {
    dialectsLoading = recording.BEId != null;
    _subscriptions = [
      _audio.positionStream.listen((value) {
        currentPosition = value;
        _notify();
      }),
      _audio.durationStream.listen((value) {
        totalDuration = value ?? Duration.zero;
        _notify();
      }),
      _audio.playingStream.listen((value) {
        isPlaying = value;
        _notify();
      }),
    ];
  }

  final RecordingAudioPlayer _audio;
  final RecordingDetailRepository _repository;
  final Logger _logger = Logger();
  late final List<StreamSubscription<dynamic>> _subscriptions;
  Recording _recording;
  Recording get recording => _recording;
  List<RecordingPart> parts = const [];
  List<RecordingDialectEntry> dialectEntries = const [];
  String placeTitle = t('recListItem.placeTitle');
  bool loaded = false;
  bool playAccessResolved = false;
  bool canAccessPlayback = false;
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool isDownloading = false;
  double downloadProgress = 0;
  bool dialectsLoading = false;
  String? dialectsError;
  RecordingDetailScope? _scope;
  CancelToken? _downloadCancelToken;
  int _generation = 0;
  bool _disposed = false;
  bool _scopeInvalidated = false;

  String get title {
    final name = recording.name?.trim();
    return name != null && name.isNotEmpty ? name : placeTitle;
  }

  Duration get playbackDuration {
    if (totalDuration > Duration.zero) return totalDuration;
    final seconds = recording.totalSeconds?.round() ?? 0;
    return Duration(seconds: seconds > 0 ? seconds : 0);
  }

  Duration get playbackPosition {
    if (currentPosition < Duration.zero) return Duration.zero;
    final total = playbackDuration;
    return total > Duration.zero && currentPosition > total
        ? total
        : currentPosition;
  }

  double get playbackProgress => playbackDuration.inMilliseconds <= 0
      ? 0
      : (playbackPosition.inMilliseconds / playbackDuration.inMilliseconds)
            .clamp(0, 1);

  Future<void> initialize() async {
    final generation = ++_generation;
    try {
      final captured = await _repository.captureScope();
      if (!_active(generation)) return;
      _scope = captured;
      playAccessResolved = true;
      canAccessPlayback = captured.canPlay(recording);
      _notify();
      try {
        await _loadRecording(generation);
      } catch (error, stack) {
        _report('Could not load cached recording detail', error, stack);
      }
      if (!await _current(generation)) return;
      loaded = true;
      _notify();
      await _loadDialects(generation);
    } catch (error, stack) {
      if (!_active(generation)) return;
      loaded = true;
      playAccessResolved = true;
      dialectsLoading = false;
      dialectsError = 'Could not load recording details';
      _report('Could not initialize recording detail', error, stack);
      _notify();
    }
  }

  Future<void> refresh() async {
    if (isDownloading || _scopeInvalidated || _disposed) return;
    final generation = ++_generation;
    try {
      if (!await _current(generation)) return;
      await _loadRecording(generation);
      if (!await _current(generation)) return;
      await _loadDialects(generation);
    } catch (error, stack) {
      _report('Could not refresh recording detail', error, stack);
    }
  }

  Future<void> _loadRecording(int generation) async {
    final resolved = await _repository.resolveRecording(recording);
    if (!await _current(generation)) return;
    if (resolved != null) _recording = resolved;
    canAccessPlayback = _scope!.canPlay(recording);
    final localId = recording.id;
    final loadedParts = localId == null
        ? <RecordingPart>[]
        : await _repository.loadParts(localId);
    if (!await _current(generation)) return;
    loadedParts.sort((a, b) => a.startTime.compareTo(b.startTime));
    parts = List.unmodifiable(loadedParts);
    _notify();
    if (canAccessPlayback) await _loadAudio(generation);
    if (!await _current(generation) || parts.isEmpty) return;
    unawaited(_resolvePlaceTitle(parts.first, generation));
  }

  Future<void> _resolvePlaceTitle(RecordingPart first, int generation) async {
    try {
      final label = await _repository.reverseGeocode(
        first.gpsLatitudeStart,
        first.gpsLongitudeStart,
        _scope!.host,
      );
      if (!await _current(generation)) return;
      if (label != null) {
        placeTitle = label;
        _notify();
      }
    } catch (error, stack) {
      _report('Could not resolve recording location', error, stack);
    }
  }

  Future<void> _loadAudio(int generation) async {
    final path = recording.path;
    if (path == null || path.isEmpty || isFileLoaded) return;
    try {
      await _audio.setFilePath(path);
      if (!await _current(generation)) return;
      isFileLoaded = true;
      currentPosition = Duration.zero;
      totalDuration = _audio.duration ?? Duration.zero;
      _notify();
    } catch (error, stack) {
      _report('Could not load recording audio', error, stack);
    }
  }

  Future<void> _loadDialects(int generation) async {
    final backendId = recording.BEId;
    if (backendId == null) {
      dialectEntries = const [];
      dialectsError = null;
      dialectsLoading = false;
      _notify();
      return;
    }
    dialectsLoading = true;
    dialectsError = null;
    _notify();
    try {
      final payload = await _repository.loadDialectParts(
        backendId,
        _scope!.host,
      );
      if (!await _current(generation)) return;
      final entries = RecordingDialectResolver(
        recordingCreatedAt: recording.createdAt,
        totalSeconds: recording.totalSeconds,
        parts: parts.map(
          (part) =>
              DialectTimeSegment(start: part.startTime, end: part.endTime),
        ),
      ).resolve(payload);
      final codes = entries
          .map((entry) => entry.canonicalCode)
          .toSet()
          .toList();
      final colors = codes.isEmpty
          ? <Color>[]
          : await _repository.loadDialectColors(codes);
      if (!await _current(generation)) return;
      final colorsByCode = {
        for (var i = 0; i < codes.length; i++)
          codes[i]: i < colors.length ? colors[i] : Colors.grey.shade400,
      };
      dialectEntries = [
        for (final entry in entries)
          entry.withColor(colorsByCode[entry.canonicalCode]!),
      ];
    } catch (error, stack) {
      if (!await _current(generation)) return;
      dialectEntries = const [];
      dialectsError = 'Could not load dialects';
      _report('Could not load recording dialects', error, stack);
    }
    if (!_active(generation)) return;
    dialectsLoading = false;
    _notify();
  }

  Future<RecordingDetailActionResult> togglePlay() async {
    final generation = _generation;
    if (!await _current(generation)) return RecordingDetailActionResult.stale;
    if (!canAccessPlayback) return RecordingDetailActionResult.restricted;
    await _loadAudio(generation);
    if (!await _current(generation)) return RecordingDetailActionResult.stale;
    if (!isFileLoaded) return RecordingDetailActionResult.unavailable;
    try {
      if (_audio.playing) {
        await _audio.pause();
      } else {
        if (playbackDuration > Duration.zero &&
            currentPosition >=
                playbackDuration - const Duration(milliseconds: 300)) {
          await _audio.seek(Duration.zero);
        }
        // just_audio's play future completes when playback ends or is paused.
        unawaited(
          _audio.play().catchError((Object error, StackTrace stack) {
            _report('Could not play recording audio', error, stack);
          }),
        );
      }
      return RecordingDetailActionResult.success;
    } catch (error, stack) {
      _report('Could not toggle recording playback', error, stack);
      return RecordingDetailActionResult.unavailable;
    }
  }

  Future<void> seekRelative(int seconds) async {
    if (!await _current(_generation) || !canAccessPlayback) return;
    var next = currentPosition + Duration(seconds: seconds);
    if (next < Duration.zero) next = Duration.zero;
    if (playbackDuration > Duration.zero && next > playbackDuration)
      next = playbackDuration;
    await _audio.seek(next);
  }

  Future<RecordingDetailActionResult> download() async {
    final generation = _generation;
    if (!await _current(generation)) return RecordingDetailActionResult.stale;
    if (!canAccessPlayback) return RecordingDetailActionResult.restricted;
    if (isDownloading) return RecordingDetailActionResult.stale;
    final backendId = recording.BEId;
    if (backendId == null) return RecordingDetailActionResult.unavailable;
    isDownloading = true;
    loaded = false;
    downloadProgress = 0;
    final token = CancelToken();
    _downloadCancelToken = token;
    _notify();
    try {
      final updated = await _repository.downloadByBackendId(
        backendId,
        cancelToken: token,
        onProgress: (progress) {
          if (!_active(generation)) return;
          downloadProgress = progress.clamp(0, 1);
          _notify();
        },
      );
      if (!await _current(generation)) return RecordingDetailActionResult.stale;
      if (updated != null) {
        _recording = updated;
        isFileLoaded = false;
        await _loadRecording(generation);
      }
      if (!await _current(generation)) return RecordingDetailActionResult.stale;
      return RecordingDetailActionResult.success;
    } catch (error, stack) {
      if (!_active(generation)) return RecordingDetailActionResult.stale;
      if (error is DioException && error.type == DioExceptionType.cancel) {
        return RecordingDetailActionResult.canceled;
      }
      _report('Could not download recording', error, stack);
      return RecordingDetailActionResult.unavailable;
    } finally {
      if (_active(generation)) {
        isDownloading = false;
        loaded = true;
        _downloadCancelToken = null;
        _notify();
      }
    }
  }

  void cancelDownload() =>
      _downloadCancelToken?.cancel('User canceled recording download.');

  bool _active(int generation) => !_disposed && generation == _generation;

  Future<bool> _current(int generation) async {
    if (!_active(generation) || _scope == null || _scopeInvalidated)
      return false;
    final current = await _repository.captureScope();
    if (!_active(generation)) return false;
    if (current == _scope) return true;
    _scopeInvalidated = true;
    _generation++;
    canAccessPlayback = false;
    isFileLoaded = false;
    isPlaying = false;
    loaded = true;
    isDownloading = false;
    dialectsLoading = false;
    parts = const [];
    dialectEntries = const [];
    _downloadCancelToken?.cancel('Recording session changed.');
    unawaited(_audio.pause());
    _notify();
    return false;
  }

  void _report(String message, Object error, StackTrace stack) {
    _logger.w('$message (${error.runtimeType}).');
    unawaited(Sentry.captureException(error, stackTrace: stack));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _downloadCancelToken?.cancel('Recording download canceled on dispose.');
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_audio.dispose());
    super.dispose();
  }
}
