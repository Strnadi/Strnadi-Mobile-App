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
 * recListItem.dart
 */

import 'dart:convert';

import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/localization/localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:strnadi/api/http_adapter.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/dialects/dialect_time_resolver.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/utils/location_label.dart';
import '../navigation/scaffold_with_bottom_bar.dart';
import 'editRecording.dart';
import '../config/config.dart'; // Contains MAPY_CZ_API_KEY
import 'package:strnadi/widgets/loader.dart';
import 'package:dio/dio.dart';

final logger = Logger();

class _DialectDetailValue {
  const _DialectDetailValue({
    required this.displayLabel,
    required this.canonicalCode,
  });

  final String displayLabel;
  final String canonicalCode;
}

class _DialectDetailEntry {
  const _DialectDetailEntry({
    this.userGuess,
    this.aiPrediction,
    this.adminFinal,
    this.startOffset,
    this.endOffset,
  });

  final _DialectDetailValue? userGuess;
  final _DialectDetailValue? aiPrediction;
  final _DialectDetailValue? adminFinal;
  final Duration? startOffset;
  final Duration? endOffset;
}

class RecordingItem extends StatefulWidget {
  Recording recording;

  RecordingItem({Key? key, required this.recording}) : super(key: key);

  @override
  _RecordingItemState createState() => _RecordingItemState();
}

class _RecordingItemState extends State<RecordingItem> {
  bool loaded = false;
  late LatLng center;
  late List<RecordingPart> parts = [];
  late LocationService locationService;
  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool _isLoading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  CancelToken? _downloadCancelToken;
  double? _scrubProgress;

  List<_DialectDetailEntry> _dialectDetails = const [];
  bool _dialectDetailsLoading = false;
  Map<String, Color> _dialectColorsByCode = const {};

  final MapController _mapController = MapController();
  bool _mapReady = false;
  LatLng? _pendingCenter;

  String placeTitle = t('recListItem.placeTitle');

  double length = 0;
  int mililen = 0;

  String get _recordingTitle {
    final String? explicitName = widget.recording.name?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }
    return placeTitle;
  }

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    player.positionStream.listen((position) {
      setState(() {
        currentPosition = position;
      });
    });
    player.durationStream.listen((duration) {
      setState(() {
        totalDuration = duration ?? Duration.zero;
      });
    });
    player.playingStream.listen((playing) {
      setState(() {
        isPlaying = playing;
      });
    });
    _initializeRecording();
  }

  Future<void> _initializeRecording() async {
    await getParts();
    await _loadDialectDetails();

    logger.i(
        "[RecordingItem] initState: recording path: ${widget.recording.path}, downloaded: ${widget.recording.downloaded}");

    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      await getData();
      setState(() {
        loaded = true;
      });
    } else {
      List<RecordingPart> parts =
          await DatabaseNew.getPartsByRecordingId(widget.recording.BEId!);
      if (parts.isNotEmpty) {
        logger.i(
            "[RecordingItem] Recording path is empty. Starting concatenation of recording parts for recording id: ${widget.recording.id}");
        await DatabaseNew.concatRecordingParts(widget.recording.BEId!);
        logger.i(
            "[RecordingItem] Concatenation complete for recording id: ${widget.recording.id}. Fetching updated recording.");
        Recording? updatedRecording =
            await DatabaseNew.getRecordingFromDbById(widget.recording.BEId!);
        logger
            .i("[RecordingItem] Fetched updated recording: $updatedRecording");
        logger.i(
            "[RecordingItem] Original recording path: ${widget.recording.path}");
        setState(() {
          widget.recording.path =
              updatedRecording?.path ?? widget.recording.path;
          loaded = true;
        });
      } else {
        logger.w(
            "[RecordingItem] No recording parts found for recording id: ${widget.recording.id}");
        setState(() {
          loaded = true;
        });
      }
    }
  }

  _DialectDetailValue? _dialectDetailValueOrNull(String? raw) {
    if (raw == null) return null;
    final String english =
        (DialectKeywordTranslator.toEnglish(raw) ?? raw).trim();
    if (english.isEmpty) return null;
    const Set<String> hidden = <String>{
      'Unknown',
      'Unknown dialect',
      'Undetermined',
      'Unassessed',
    };
    if (hidden.contains(english)) return null;
    return _DialectDetailValue(
      displayLabel: DialectKeywordTranslator.toLocalized(english),
      canonicalCode: english,
    );
  }

  Future<void> _loadDialectDetails() async {
    final int? recordingId = widget.recording.id;
    if (recordingId == null) {
      if (!mounted) return;
      setState(() {
        _dialectDetails = const [];
        _dialectColorsByCode = const {};
        _dialectDetailsLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _dialectDetailsLoading = true;
      });
    }

    final List<_DialectDetailEntry> entries = <_DialectDetailEntry>[];

    try {
      final detectedDialects =
          await DatabaseNew.getDetectedDialectsByRecordingLocalId(recordingId);
      for (final d in detectedDialects) {
        final Duration? startOffset = d.filteredPartStartDate == null
            ? null
            : _offsetWithinConcatenated(d.filteredPartStartDate!);
        final Duration? rawEndOffset = d.filteredPartEndDate == null
            ? null
            : _offsetWithinConcatenated(d.filteredPartEndDate!);
        final Duration? endOffset = (startOffset != null &&
                rawEndOffset != null &&
                rawEndOffset < startOffset)
            ? startOffset
            : rawEndOffset;
        final entry = _DialectDetailEntry(
          userGuess: _dialectDetailValueOrNull(d.userGuessDialect),
          aiPrediction: _dialectDetailValueOrNull(d.predictedDialect),
          adminFinal: _dialectDetailValueOrNull(d.confirmedDialect),
          startOffset: startOffset,
          endOffset: endOffset,
        );
        if (entry.userGuess == null &&
            entry.aiPrediction == null &&
            entry.adminFinal == null) {
          continue;
        }
        entries.add(entry);
      }

      if (entries.isEmpty) {
        final legacyDialects =
            await DatabaseNew.getDialectsByRecordingId(recordingId);
        for (final d in legacyDialects) {
          final Duration startOffset = _offsetWithinConcatenated(d.startDate);
          final Duration rawEndOffset = _offsetWithinConcatenated(d.endDate);
          final Duration endOffset =
              rawEndOffset < startOffset ? startOffset : rawEndOffset;
          final entry = _DialectDetailEntry(
            userGuess: _dialectDetailValueOrNull(d.userGuessDialect),
            aiPrediction: null,
            adminFinal: _dialectDetailValueOrNull(d.adminDialect),
            startOffset: startOffset,
            endOffset: endOffset,
          );
          if (entry.userGuess == null && entry.adminFinal == null) continue;
          entries.add(entry);
        }
      }
    } catch (e, stackTrace) {
      logger.e('Failed to load dialect details for recording $recordingId: $e',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }

    final Set<String> seen = <String>{};
    final List<_DialectDetailEntry> unique = <_DialectDetailEntry>[];
    for (final entry in entries) {
      final key =
          '${entry.userGuess?.canonicalCode ?? ''}|${entry.aiPrediction?.canonicalCode ?? ''}|${entry.adminFinal?.canonicalCode ?? ''}|${entry.startOffset?.inMilliseconds ?? ''}|${entry.endOffset?.inMilliseconds ?? ''}';
      if (seen.add(key)) {
        unique.add(entry);
      }
    }

    final Set<String> requestedCodes = <String>{};
    for (final entry in unique) {
      if (entry.userGuess != null) {
        requestedCodes.add(entry.userGuess!.canonicalCode);
      }
      if (entry.aiPrediction != null) {
        requestedCodes.add(entry.aiPrediction!.canonicalCode);
      }
      if (entry.adminFinal != null) {
        requestedCodes.add(entry.adminFinal!.canonicalCode);
      }
    }

    Map<String, Color> colorMap = const {};
    if (requestedCodes.isNotEmpty) {
      final List<String> codes = requestedCodes.toList();
      try {
        final List<Color> colors = await DialectColorCache.getColors(codes);
        colorMap = <String, Color>{
          for (var i = 0; i < codes.length; i++)
            codes[i]: i < colors.length ? colors[i] : Colors.grey.shade400
        };
      } catch (e, stackTrace) {
        logger.e('Failed to resolve dialect detail colors: $e',
            error: e, stackTrace: stackTrace);
        colorMap = <String, Color>{
          for (final code in codes) code: Colors.grey.shade400,
        };
      }
    }

    if (!mounted) return;
    setState(() {
      _dialectDetails = unique;
      _dialectColorsByCode = colorMap;
      _dialectDetailsLoading = false;
    });
  }

  Future<void> getData() async {
    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      try {
        await player.setFilePath(widget.recording.path!);
        setState(() {
          isFileLoaded = true;
          currentPosition = Duration.zero;
          totalDuration = player.duration ?? Duration.zero;
        });
      } catch (e, stackTrace) {
        logger.e("Error loading audio file: $e",
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
    }
  }

  Future<void> getParts() async {
    logger.i('Recording ID: ${widget.recording.id}');
    var parts = await DatabaseNew.getPartsByRecordingId(widget.recording.id!);
    setState(() {
      this.parts = parts;
      if (parts.isNotEmpty) {
        _pendingCenter =
            LatLng(parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart);
      }
    });
    if (parts.isNotEmpty) {
      await reverseGeocode(
          parts[0].gpsLatitudeStart, parts[0].gpsLongitudeStart);
    }
    if (_mapReady && _pendingCenter != null) {
      _mapController.move(_pendingCenter!, 13.0);
    }
  }

  bool get _hasUnsentParts => parts.any((part) => !part.sent);

  bool get _hasIdleUnsentParts =>
      parts.any((part) => !part.sent && !part.sending);

  Future<void> _refreshRecordingState() async {
    final int? recordingId = widget.recording.id;
    if (recordingId == null) return;

    final Recording? refreshed =
        await DatabaseNew.getRecordingFromDbById(recordingId);
    if (!mounted || refreshed == null) return;

    setState(() {
      widget.recording = refreshed;
    });
  }

  Future<void> _fetchRecordings() async {
    await _refreshRecordingState();
    await getParts();
    await _loadDialectDetails();
  }

  Future<void> _resendUnsentPartsForCurrentRecording() async {
    final int? recordingId = widget.recording.id;
    if (recordingId == null) return;

    final bool? shouldResend = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('recListItem.dialogs.unsentParts.title')),
        content: Text(t('recListItem.dialogs.unsentParts.message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('recListItem.dialogs.unsentParts.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t('recListItem.dialogs.unsentParts.resend')),
          ),
        ],
      ),
    );

    if (shouldResend != true) return;

    await _withLoader(() async {
      try {
        await DatabaseNew.resendUnsentPartsForRecording(recordingId);
        await _refreshRecordingState();
        await getParts();
      } catch (e, stackTrace) {
        logger.e('Error resending unsent parts for recording $recordingId: $e',
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    });
  }

  Future<bool> _ensureFileLoaded() async {
    if (isFileLoaded) return true;
    if (widget.recording.path == null || widget.recording.path!.isEmpty) {
      return false;
    }
    await getData();
    return isFileLoaded;
  }

  void togglePlay() async {
    try {
      if (!await _ensureFileLoaded()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('recordingPage.status.errorDownloading'))),
          );
        }
        return;
      }
      final Duration total = _effectivePlaybackDuration();
      final bool atEnd = total > Duration.zero &&
          currentPosition >= total - const Duration(milliseconds: 300);
      if (player.playing) {
        await player.pause();
      } else {
        if (atEnd) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
    } catch (e, stackTrace) {
      logger.e("Error toggling playback: $e", error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  void seekRelative(int seconds) {
    final Duration total = _effectivePlaybackDuration();
    Duration newPosition = currentPosition + Duration(seconds: seconds);
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (total > Duration.zero && newPosition > total) {
      newPosition = total;
    }
    player.seek(newPosition);
  }

  String _formatPlayerTime(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Duration _effectivePlaybackDuration() {
    if (totalDuration > Duration.zero) {
      return totalDuration;
    }
    final int fallbackSeconds = widget.recording.totalSeconds?.round() ?? 0;
    if (fallbackSeconds <= 0) {
      return Duration.zero;
    }
    return Duration(seconds: fallbackSeconds);
  }

  Iterable<DialectTimeSegment> _dialectTimeSegments() sync* {
    for (final part in parts) {
      yield DialectTimeSegment(
        start: part.startTime,
        end: part.endTime,
      );
    }
  }

  Duration _offsetWithinConcatenated(DateTime timestamp) {
    return resolveDialectOffset(
      timestamp: timestamp,
      recordingCreatedAt: widget.recording.createdAt,
      parts: _dialectTimeSegments(),
      totalSeconds: widget.recording.totalSeconds,
    );
  }

  Duration _displayPlaybackPosition() {
    final Duration total = _effectivePlaybackDuration();
    if (_scrubProgress != null && total > Duration.zero) {
      final int scrubMs = (total.inMilliseconds * _scrubProgress!)
          .round()
          .clamp(0, total.inMilliseconds);
      return Duration(milliseconds: scrubMs);
    }
    if (total > Duration.zero && currentPosition > total) {
      return total;
    }
    if (currentPosition < Duration.zero) {
      return Duration.zero;
    }
    return currentPosition;
  }

  double _playbackProgress() {
    if (_scrubProgress != null) {
      return _scrubProgress!.clamp(0.0, 1.0);
    }
    final Duration total = _effectivePlaybackDuration();
    if (total.inMilliseconds <= 0) {
      return 0.0;
    }
    final Duration position = _displayPlaybackPosition();
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<void> _seekToProgress(double progress) async {
    final Duration total = _effectivePlaybackDuration();
    if (total <= Duration.zero) return;
    if (!await _ensureFileLoaded()) return;
    final int seekMs =
        (total.inMilliseconds * progress.clamp(0.0, 1.0)).round();
    await player.seek(Duration(milliseconds: seekMs));
  }

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // ignore repeated presses while loading
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  @override
  void dispose() {
    _downloadCancelToken?.cancel('Recording download canceled on dispose.');
    player.dispose();
    super.dispose();
  }

  Future<void> _downloadRecording() async {
    if (!await Config.hasBasicInternet) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('recListItem.dialogs.downloadUnavailable.title')),
          content: Text(t('recListItem.dialogs.downloadUnavailable.message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('auth.buttons.ok')),
            ),
          ],
        ),
      );
      return;
    }

    try {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
        _downloadCancelToken = CancelToken();
        loaded = false;
      });
      logger.i("Initiating download for recording id: ${widget.recording.id}");
      await DatabaseNew.downloadRecording(
        widget.recording.id!,
        cancelToken: _downloadCancelToken,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = progress.clamp(0.0, 1.0);
          });
        },
      );
      Recording? updatedRecording =
          await DatabaseNew.getRecordingFromDbById(widget.recording.id!);
      if (updatedRecording != null) {
        setState(() {
          widget.recording = updatedRecording;
        });
        await getData();
      }
      logger.i("Downloaded recording updated: ${widget.recording.path}");
      if (mounted) {
        setState(() {
          loaded = true;
          _isDownloading = false;
          _downloadCancelToken = null;
        });
      }
    } catch (e, stackTrace) {
      final bool wasCanceled =
          e is DioException && e.type == DioExceptionType.cancel;
      logger.e("Error downloading recording: $e",
          error: e, stackTrace: stackTrace);
      if (!wasCanceled) {
        Sentry.captureException(e, stackTrace: stackTrace);
      }
      if (mounted) {
        setState(() {
          loaded = true;
          _isDownloading = false;
          _downloadCancelToken = null;
        });
        if (wasCanceled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('recordingPage.status.downloadCanceled'))),
          );
          return;
        }
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('recListItem.errors.errorDownloading')),
            content: Text(t('recordingPage.status.errorDownloading')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('auth.buttons.ok')),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Permanently deletes the current recording both on the server (if already sent)
  /// and locally in the SQLite database.
  Future<void> _deleteRecording() async {
    try {
      // Always remove it from the local DB.
      await DatabaseNew.deleteRecording(widget.recording.id!);

      // Return to the previous screen so the list refreshes.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      logger.e('Error deleting recording: $e',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('recListItem.errors.errorDownloading'))),
        );
      }
    }
  }

  Future<void> reverseGeocode(double lat, double lon) async {
    final url = Uri.parse(
        "https://api.mapy.cz/v1/rgeocode?lat=$lat&lon=$lon&apikey=${Config.mapsApiKey}");

    logger.i("reverse geocode url: $url");
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${Config.mapsApiKey}',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final String? label = buildLocationLabel(data);
        if (label != null) {
          setState(() {
            placeTitle = label;
          });
        }
      } else {
        logger.e(
            "Reverse geocode failed with status code ${response.statusCode}");
      }
    } catch (e, stackTrace) {
      logger.e('Reverse geocode error: $e', error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  Color _dialectColorForCode(String canonicalCode) {
    return _dialectColorsByCode[canonicalCode] ?? Colors.grey.shade400;
  }

  String _formatDurationLabel(Duration value) {
    if (value <= Duration.zero) {
      return '0:00';
    }
    final int totalSeconds = value.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDialectTimeRange(Duration? start, Duration? end) {
    if (start == null || end == null) return '';
    final String startText = _formatDurationLabel(start);
    final String endText = _formatDurationLabel(end);
    if (startText == endText) {
      return startText;
    }
    return '$startText - $endText';
  }

  Widget _buildDialectDetailLine(String label, _DialectDetailValue value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _dialectColorForCode(value.canonicalCode),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black12),
          ),
        ),
        Expanded(
          child: Text(
            value.displayLabel,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildDialectDetailCard(_DialectDetailEntry entry) {
    final List<Widget> lines = <Widget>[];
    final bool hasEvaluatedGuess =
        entry.aiPrediction != null || entry.adminFinal != null;
    final String timeRange = hasEvaluatedGuess
        ? _formatDialectTimeRange(entry.startOffset, entry.endOffset)
        : '';

    if (timeRange.isNotEmpty) {
      lines.add(
        Text(
          timeRange,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    if (entry.userGuess != null) {
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 4));
      lines.add(_buildDialectDetailLine(
          t('recListItem.dialectDetails.userGuess'), entry.userGuess!));
    }
    if (entry.aiPrediction != null) {
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 4));
      lines.add(_buildDialectDetailLine(
          t('recListItem.dialectDetails.aiPrediction'), entry.aiPrediction!));
    }
    if (entry.adminFinal != null) {
      if (lines.isNotEmpty) lines.add(const SizedBox(height: 4));
      lines.add(_buildDialectDetailLine(
          t('recListItem.dialectDetails.adminFinal'), entry.adminFinal!));
    }

    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }

  Widget _buildDialectDetailsSection() {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('dialectBadge.title'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          if (_dialectDetailsLoading) ...[
            const SizedBox(height: 8),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ] else ...[
            const SizedBox(height: 8),
            for (final entry in _dialectDetails) _buildDialectDetailCard(entry),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDownloading &&
        !loaded &&
        widget.recording.path != null &&
        widget.recording.path!.isNotEmpty) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.list,
        appBarTitle: _recordingTitle,
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    return Loader(
        isLoading: _isLoading,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_recordingTitle),
            leading: IconButton(
              icon: Image.asset('assets/icons/backButton.png',
                  width: 30, height: 30),
              onPressed: () async {
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final updatedRecording = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          EditRecordingPage(recording: widget.recording),
                    ),
                  );
                  // If the user saved changes, rebuild to show the latest data
                  if (updatedRecording != null && mounted) {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _fetchRecordings,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  widget.recording.downloaded
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 12.0),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(14.0),
                              constraints: const BoxConstraints(maxWidth: 420),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.12),
                                    Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withOpacity(0.08),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.2),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cloud_download_outlined,
                                      size: 34),
                                  const SizedBox(height: 8),
                                  Text(
                                    t('recordingPage.status.notDownloaded'),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t('recListItem.noRecording'),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  if (_isDownloading) ...[
                                    SizedBox(
                                      width: 220,
                                      child: LinearProgressIndicator(
                                        value: _downloadProgress,
                                        minHeight: 6,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                        '${(_downloadProgress * 100).toStringAsFixed(1)}%'),
                                    const SizedBox(height: 4),
                                    TextButton(
                                      onPressed: () {
                                        _downloadCancelToken?.cancel(
                                            'User canceled recording download.');
                                      },
                                      child:
                                          Text(t('recListItem.buttons.cancel')),
                                    ),
                                  ] else
                                    ElevatedButton.icon(
                                      onPressed: _downloadRecording,
                                      icon: const Icon(Icons.download),
                                      label: Text(
                                          t('recListItem.buttons.download')),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      children: [
                        if (widget.recording.downloaded)
                          Container(
                            padding: const EdgeInsets.all(12.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.2),
                              ),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceVariant
                                  .withOpacity(0.3),
                            ),
                            child: Column(
                              children: [
                                Builder(builder: (context) {
                                  final Duration displayPosition =
                                      _displayPlaybackPosition();
                                  final Duration displayTotal =
                                      _effectivePlaybackDuration();
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _formatPlayerTime(displayPosition),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        _formatPlayerTime(displayTotal),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  );
                                }),
                                const SizedBox(height: 8),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 6,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7),
                                  ),
                                  child: Slider(
                                    value: _playbackProgress(),
                                    min: 0.0,
                                    max: 1.0,
                                    onChangeStart:
                                        _effectivePlaybackDuration() >
                                                Duration.zero
                                            ? (value) {
                                                setState(() {
                                                  _scrubProgress = value;
                                                });
                                              }
                                            : null,
                                    onChanged: _effectivePlaybackDuration() >
                                            Duration.zero
                                        ? (value) {
                                            setState(() {
                                              _scrubProgress = value;
                                            });
                                          }
                                        : null,
                                    onChangeEnd: _effectivePlaybackDuration() >
                                            Duration.zero
                                        ? (value) async {
                                            setState(() {
                                              _scrubProgress = value;
                                            });
                                            await _seekToProgress(value);
                                            if (!mounted) return;
                                            setState(() {
                                              _scrubProgress = null;
                                            });
                                          }
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                        icon: const Icon(Icons.replay_10,
                                            size: 28),
                                        onPressed: () => seekRelative(-10)),
                                    const SizedBox(width: 4),
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.15),
                                      ),
                                      child: IconButton(
                                        icon: Icon(isPlaying
                                            ? Icons.pause_circle_filled
                                            : Icons.play_circle_filled),
                                        iconSize: 56,
                                        onPressed: togglePlay,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                        icon: const Icon(Icons.forward_10,
                                            size: 28),
                                        onPressed: () => seekRelative(10)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10.0),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.recording.note ??
                                t('recListItem.notePlaceholder'),
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(3.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(t('recListItem.dateTime'))
                                      ],
                                    ),
                                    Text(
                                      formatDateTime(
                                          widget.recording.createdAt),
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_dialectDetailsLoading ||
                            _dialectDetails.isNotEmpty)
                          _buildDialectDetailsSection(),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${t('recListItem.estimatedBirdsCount')}: '),
                              Text(widget.recording.estimatedBirdsCount
                                  .toString()),
                            ],
                          ),
                        ),
                        Visibility(
                          visible: widget.recording.sent == false &&
                              widget.recording.sending == false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.send),
                              label: Text(t('recListItem.buttons.send')),
                              onPressed: () async {
                                await _withLoader(() async {
                                  try {
                                    setState(() {
                                      widget.recording.sending = true;
                                    });
                                    await DatabaseNew.sendRecordingBackground(
                                        widget.recording.id!);
                                    logger.i(
                                        "Sending recording: ${widget.recording.id}");
                                  } catch (e, stackTrace) {
                                    logger.e(
                                        'Error during send check/resend: $e',
                                        error: e,
                                        stackTrace: stackTrace);
                                    Sentry.captureException(e,
                                        stackTrace: stackTrace);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        Visibility(
                          visible: widget.recording.sent && _hasUnsentParts,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                  t('recListItem.buttons.resendUnsentParts')),
                              onPressed: _hasIdleUnsentParts
                                  ? _resendUnsentPartsForCurrentRecording
                                  : null,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ElevatedButton(
                            onPressed: () async {
                              await _withLoader(() async {
                                await DatabaseNew.deleteRecordingFromCache(
                                    widget.recording.id!);
                                if (mounted) {
                                  setState(() {
                                    // Optionally refresh UI or provide feedback
                                  });
                                }
                              });
                            },
                            child: Text(t('recListItem.buttons.deleteCache')),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ElevatedButton.icon(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                            label: Text(
                              t('recListItem.buttons.delete'),
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(t(
                                      'recListItem.dialogs.confirmDelete.title')),
                                  content: Text(t(
                                      'recListItem.dialogs.confirmDelete.message')),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: Text(t(
                                          'recListItem.dialogs.confirmDelete.cancel')),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: Text(t(
                                          'recListItem.dialogs.confirmDelete.delete')),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _withLoader(() async {
                                  await _deleteRecording();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      children: [
                        Row(children: [Text(placeTitle)]),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 300,
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                interactionOptions: InteractionOptions(
                                    flags: InteractiveFlag.none),
                                initialCenter: _pendingCenter ??
                                    (parts.isNotEmpty
                                        ? LatLng(parts[0].gpsLatitudeStart,
                                            parts[0].gpsLongitudeStart)
                                        : LatLng(0.0, 0.0)),
                                initialZoom: 13.0,
                                onMapReady: () {
                                  _mapReady = true;
                                  if (_pendingCenter != null) {
                                    _mapController.move(_pendingCenter!, 13.0);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://api.mapy.cz/v1/maptiles/outdoor/256/{z}/{x}/{y}?apikey=${Config.mapsApiKey}',
                                  userAgentPackageName: 'cz.delta.strnadi',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      width: 20.0,
                                      height: 20.0,
                                      point: _pendingCenter ??
                                          (parts.isNotEmpty
                                              ? LatLng(
                                                  parts[0].gpsLatitudeStart,
                                                  parts[0].gpsLongitudeStart)
                                              : LatLng(0.0, 0.0)),
                                      child: const Icon(
                                        Icons.my_location,
                                        color: Colors.blue,
                                        size: 30.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ));
  }

  void fetchRecPart(int id) async {
    final part = await DatabaseNew.fetchPartsFromDbById(id);
    setState(() {
      parts = part;
    });
  }

  String formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour}:${dateTime.minute}';
  }
}
