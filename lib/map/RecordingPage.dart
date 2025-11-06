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
import 'package:strnadi/database/Models/userData.dart';
import 'package:strnadi/localization/localization.dart';

import 'package:strnadi/localization/localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localRecordings/userBadge.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/user/settingsPages/userInfo.dart';
import 'package:strnadi/widgets/spectogram_painter.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import '../PostRecordingForm/RecordingForm.dart';
import '../config/config.dart'; // Contains MAPY_CZ_API_KEY

final logger = Logger();

enum _DialectConfidence { confirmed, predicted, userGuess }

class _DialectDisplayEntry {
  const _DialectDisplayEntry({
    required this.canonicalCode,
    required this.displayLabel,
    required this.isRepresentant,
    required this.startOffset,
    required this.endOffset,
    required this.confidence,
    required this.color,
  });

  final String canonicalCode;
  final String displayLabel;
  final bool isRepresentant;
  final Duration startOffset;
  final Duration endOffset;
  final _DialectConfidence confidence;
  final Color color;
}

class RecordingFromMap extends StatefulWidget {
  Recording recording;

  final UserData? user;

  RecordingFromMap(
      {super.key, required this.recording, required this.user});

  @override
  _RecordingFromMapState createState() => _RecordingFromMapState();
}

class _RecordingFromMapState extends State<RecordingFromMap> {
  bool loaded = false;
  late LatLng center;
  late List<RecordingPart?> parts = [];
  late LocationService locationService;
  final AudioPlayer player = AudioPlayer();
  bool isFileLoaded = false;
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  bool _isDownloading = false;
  bool _dialectsLoading = false;
  String? _dialectsError;
  List<_DialectDisplayEntry> _dialectEntries = const [];

  final MapController _mapController = MapController();

  String placeTitle = 'Mapa';

  double length = 0;
  int mililen = 0;

  @override
  void initState() {
    super.initState();
    locationService = LocationService();
    getParts();
    _loadDialects();
    logger.i(
        "[RecordingItem] initState: recording path: ${widget.recording.path}, downloaded: ${widget.recording.downloaded}");

    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
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

      getData().then((_) {
        setState(() {
          loaded = true;
        });
      });
    } else {
      doSomeShit();
    }
  }

  // this is in init but init can't be async so i did this piece of thing
  Future<void> doSomeShit() async {
    // Check if any parts exist for this recording
    widget.recording.id = await DatabaseNew.fetchRecordingFromBE(widget.recording.BEId!);
    List<RecordingPart> parts =
    await DatabaseNew.getPartsByRecordingId(widget.recording.id!);
    if (parts.isNotEmpty) {
      logger.i(
          "[RecordingItem] Recording path is empty. Starting concatenation of recording parts for recording id: ${widget.recording.id}");
      DatabaseNew.concatRecordingParts(widget.recording.BEId!).then((_) {
        logger.i(
            "[RecordingItem] Concatenation complete for recording id: ${widget.recording.id}. Fetching updated recording.");
        DatabaseNew.getRecordingFromDbById(widget.recording.BEId!)
            .then((updatedRecording) {
          logger.i(
              "[RecordingItem] Fetched updated recording: $updatedRecording");
          logger.i(
              "[RecordingItem] Original recording path: ${widget.recording.path}");
          if (updatedRecording?.path != null &&
              updatedRecording!.path!.isNotEmpty) {
            logger.i(
                "[RecordingItem] Updated recording path: ${updatedRecording.path}");
          } else {
            logger
                .w("[RecordingItem] Updated recording path is null or empty.");
          }
          setState(() {
            widget.recording.path =
                updatedRecording?.path ?? widget.recording.path;
            loaded = true;
          });
        });
      });
    } else {
      logger.w(
          "[RecordingItem] No recording parts found for recording id: ${widget.recording.id}");
      setState(() {
        loaded = true;
      });
    }
  }

  Future<void> getData() async {
    if (widget.recording.path != null && widget.recording.path!.isNotEmpty) {
      try {
        await player.setFilePath(widget.recording.path!);
        setState(() {
          isFileLoaded = true;
        });
      } catch (e, stackTrace) {
        print("Error loading audio file: $e");
      }
    }
  }

  Future<void> getParts() async {
    List<RecordingPart?> varts = List.empty(growable: true);
    varts.add(await DatabaseNew.getRecordingPartByBEID(widget.recording.BEId!));

    setState(() {
      parts = varts;
    });

    await reverseGeocode(
        this.parts[0]!.gpsLatitudeStart, this.parts[0]!.gpsLongitudeStart);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(
          LatLng(parts[0]!.gpsLatitudeStart, parts[0]!.gpsLongitudeStart),
          13.0);
    });
  }

  Future<void> _fetchRecordings() async {
    await getParts();
    await _loadDialects();
  }

  void togglePlay() async {
    if (!isFileLoaded) return;
    try {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
    } catch (e, stackTrace) {
      print("Error toggling playback: $e");
    }
  }

  void seekRelative(int seconds) {
    final newPosition = currentPosition + Duration(seconds: seconds);
    player.seek(newPosition);
  }

  String _formatDuration() {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    logger.i('${length.toInt()}:$mililen');
    logger.i('Total Time => ${widget.recording.totalSeconds}');
    double td = widget.recording.totalSeconds ?? 0.0;

    int seconds = td.toInt();
    int milliseconds = ((td - seconds) * 1000).toInt();

    logger.i('TimeInit => $seconds:$milliseconds');

    return '$seconds:$milliseconds';
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> _downloadRecording() async {
    try {
      setState(() {
        _isDownloading = true;
        // While we download, show the spinner screen even if a path exists
        loaded = false;
      });
      logger.i("Initiating download for recording id: ${widget.recording.BEId}");
      int? id = await DatabaseNew.downloadRecording(widget.recording.BEId!);
      if (id == null) throw Exception('Download returned null id');
      Recording? updatedRecording = await DatabaseNew.getRecordingFromDbById(id);
      if (updatedRecording != null) {
        setState(() {
          widget.recording = updatedRecording;
        });
        // Initialize audio player with the newly downloaded file
        await getData();
      }
      logger.i("Downloaded recording updated: ${widget.recording.path}");
      // Mark as fully loaded to exit the spinner state
      if (mounted) {
        setState(() {
          loaded = true;
          _isDownloading = false;
        });
      }
    } catch (e, stackTrace) {
      logger.e("Error downloading recording: $e", error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          // Exit spinner and show the regular screen with the download button again
          loaded = true;
          _isDownloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('recordingPage.status.errorDownloading'))),
        );
      }
    }
  }

  Future<void> _loadDialects() async {
    final int? beId = widget.recording.BEId;
    if (beId == null) {
      if (!mounted) return;
      setState(() {
        _dialectsLoading = false;
        _dialectEntries = const [];
        _dialectsError = null;
      });
      return;
    }

    setState(() {
      _dialectsLoading = true;
      _dialectsError = null;
    });

    List<_DialectDisplayEntry> entries = const [];
    String? error;

    try {
      entries = await _fetchDialectsFromBackend(beId);
    } catch (e, stackTrace) {
      logger.e('Failed to load dialects for recording $beId',
          error: e, stackTrace: stackTrace);
      error = e is Exception ? e.toString() : 'Failed to load dialects';
    }

    if (!mounted) return;

    setState(() {
      _dialectsLoading = false;
      _dialectEntries = entries;
      _dialectsError = error;
    });
  }

  Future<List<_DialectDisplayEntry>> _fetchDialectsFromBackend(int recordingBeId) async {
    final uri = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/recordings/filtered',
      queryParameters: {
        'recordingId': recordingBeId.toString(),
        'verified': 'false',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 204) {
      return const [];
    }

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      return const [];
    }

    final List<({
      String code,
      String label,
      bool representant,
      Duration start,
      Duration end,
      _DialectConfidence confidence,
    })> drafts = [];
    final Set<String> codes = <String>{};

    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final map = item;
      final bool isRepresentant = _parseBool(map['representantFlag']);

      final String? startStr = map['startDate'] as String?;
      final String? endStr = map['endDate'] as String?;
      if (startStr == null || endStr == null) continue;

      DateTime? startDate;
      DateTime? endDate;
      try {
        startDate = DateTime.parse(startStr);
        endDate = DateTime.parse(endStr);
      } catch (_) {
        continue;
      }

      final Duration startOffset = _offsetWithinRecording(startDate);
      final Duration endOffset = _offsetWithinRecording(endDate);
      final Duration safeEnd = endOffset < startOffset ? startOffset : endOffset;

      final dynamic rawDialects = map['detectedDialects'];
      if (rawDialects is List && rawDialects.isNotEmpty) {
        for (final dd in rawDialects) {
          if (dd is! Map<String, dynamic>) continue;
          final selected = _selectDialect(dd);
          final String? rawCode = selected.code;
          if (rawCode == null) continue;
          final String english =
              DialectKeywordTranslator.toEnglish(rawCode) ?? rawCode.trim();
          if (english.isEmpty) continue;
          final String label = DialectKeywordTranslator.toLocalized(english);
          drafts.add((
            code: english,
            label: label,
            representant: isRepresentant,
            start: startOffset,
            end: safeEnd,
            confidence: selected.confidence,
          ));
          codes.add(english);
        }
      } else {
        final String? rawCode = map['dialectCode'] as String?;
        if (rawCode == null) continue;
        final String english =
            DialectKeywordTranslator.toEnglish(rawCode) ?? rawCode.trim();
        if (english.isEmpty) continue;
        final String label = DialectKeywordTranslator.toLocalized(english);
        drafts.add((
          code: english,
          label: label,
          representant: isRepresentant,
          start: startOffset,
          end: safeEnd,
          confidence: _DialectConfidence.predicted,
        ));
        codes.add(english);
      }
    }

    if (drafts.isEmpty) {
      return const [];
    }

    final List<String> uniqueCodes = codes.toList();
    final List<Color> colors = await DialectColorCache.getColors(uniqueCodes);
    final Map<String, Color> colorByCode = <String, Color>{};
    for (var i = 0; i < uniqueCodes.length; i++) {
      colorByCode[uniqueCodes[i]] =
          i < colors.length ? colors[i] : Colors.grey.shade400;
    }

    final entries = drafts
        .map(
          (draft) => _DialectDisplayEntry(
            canonicalCode: draft.code,
            displayLabel: draft.label,
            isRepresentant: draft.representant,
            startOffset: draft.start,
            endOffset: draft.end,
            confidence: draft.confidence,
            color: colorByCode[draft.code] ?? Colors.grey.shade400,
          ),
        )
        .toList();

    entries.sort((a, b) {
      if (a.isRepresentant != b.isRepresentant) {
        return a.isRepresentant ? -1 : 1;
      }
      final int startCompare = a.startOffset.compareTo(b.startOffset);
      if (startCompare != 0) return startCompare;
      final int endCompare = a.endOffset.compareTo(b.endOffset);
      if (endCompare != 0) return endCompare;
      return a.displayLabel.compareTo(b.displayLabel);
    });

    return entries;
  }

  ({String? code, _DialectConfidence confidence}) _selectDialect(
      Map<String, dynamic> row) {
    String? pick(String key) {
      final value = row[key];
      if (value == null) return null;
      final trimmed = value.toString().trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final confirmed = pick('confirmedDialect');
    if (confirmed != null) {
      return (code: confirmed, confidence: _DialectConfidence.confirmed);
    }

    final predicted = pick('predictedDialect');
    if (predicted != null) {
      return (code: predicted, confidence: _DialectConfidence.predicted);
    }

    final guessed = pick('userGuessDialect');
    if (guessed != null) {
      return (code: guessed, confidence: _DialectConfidence.userGuess);
    }

    final fallback = pick('dialectCode');
    if (fallback != null) {
      return (code: fallback, confidence: _DialectConfidence.userGuess);
    }

    return (code: null, confidence: _DialectConfidence.userGuess);
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Duration _offsetWithinRecording(DateTime timestamp) {
    final DateTime base = widget.recording.createdAt.toUtc();
    final Duration raw = timestamp.toUtc().difference(base);
    return _clampDuration(raw);
  }

  Duration _clampDuration(Duration value) {
    if (value.isNegative) {
      return Duration.zero;
    }
    final double? totalSeconds = widget.recording.totalSeconds;
    if (totalSeconds == null || totalSeconds <= 0) {
      return value;
    }
    final Duration maxDuration =
        Duration(milliseconds: (totalSeconds * 1000).round());
    if (value > maxDuration) {
      return maxDuration;
    }
    return value;
  }

  Widget _buildDialectsSection() {
    final decoration = BoxDecoration(
      border: Border.all(color: Colors.grey),
      borderRadius: BorderRadius.circular(10),
    );
    const titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );

    if (_dialectsLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Row(
          children: [
            Expanded(
              child: Text(
                t('dialectBadge.title'),
                style: titleStyle,
              ),
            ),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }

    if (_dialectsError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('dialectBadge.title'),
              style: titleStyle,
            ),
            const SizedBox(height: 6),
            Text(
              t('map.dialogs.error.title'),
              style: TextStyle(color: Colors.red.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_dialectEntries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10.0),
        decoration: decoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('dialectBadge.title'),
              style: titleStyle,
            ),
            const SizedBox(height: 6),
            Text(
              t('dialectKeywords.unknown'),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10.0),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('dialectBadge.title'),
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          for (final entry in _dialectEntries) _buildDialectTile(entry),
        ],
      ),
    );
  }

  Widget _buildDialectTile(_DialectDisplayEntry entry) {
    final Color baseColor = entry.color;
    final Color borderColor = entry.isRepresentant
        ? baseColor
        : Colors.grey.shade400;
    final Color background = baseColor.withOpacity(0.12);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor, width: entry.isRepresentant ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: baseColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (entry.isRepresentant)
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: baseColor,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeRange(entry.startOffset, entry.endOffset),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeRange(Duration start, Duration end) {
    final String startText = _formatDurationLabel(start);
    final String endText = _formatDurationLabel(end);
    if (startText == endText) {
      return startText;
    }
    return '$startText - $endText';
  }

  String _formatDurationLabel(Duration value) {
    if (value <= Duration.zero) {
      return '0:00';
    }
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds ~/ 60) % 60;
    final int seconds = totalSeconds % 60;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    final int totalMinutes = totalSeconds ~/ 60;
    return '${totalMinutes}:${twoDigits(seconds)}';
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
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final results = data['items'];
        if (results.isNotEmpty) {
          logger.i("Reverse geocode result: $results");
          setState(() {
            placeTitle = results[0]['name'];
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

  @override
  Widget build(BuildContext context) {
    if (_isDownloading || (!loaded && widget.recording.path != null)) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.list,
        appBarTitle: widget.recording.name ?? '',
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recording.name ?? ''),
        leading: IconButton(
          icon:
          Image.asset('assets/icons/backButton.png', width: 30, height: 30),
          onPressed: () async {
            Navigator.pop(context);
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRecordings,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              widget.recording.path != null && widget.recording.path!.isNotEmpty
                  ? SizedBox(
                height: 200,
                width: double.infinity,
              )
                  : SizedBox(
                height: 200,
                width: double.infinity,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t('recListItem.noRecording')),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _downloadRecording,
                        child: Text(t('recListItem.buttons.download')),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Text(_formatDuration(),
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.replay_10, size: 32),
                            onPressed: () => seekRelative(-10)),
                        IconButton(
                          icon: Icon(isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled),
                          iconSize: 72,
                          onPressed: togglePlay,
                        ),
                        IconButton(
                            icon: const Icon(Icons.forward_10, size: 32),
                            onPressed: () => seekRelative(10)),
                      ],
                    ),
                    if (widget.user != null) UserBadge(user: widget.user!),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      width: double.infinity,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                widget.recording.note ??
                                    'K tomuto zaznamu neni poznamka',
                                style: TextStyle(fontSize: 16))
                          ]),
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
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [Text(t('recListItem.dateTime'))],
                                ),
                                Text(
                                  formatDateTime(widget.recording.createdAt),
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildDialectsSection(),
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
                          Text(t("Predpokladany pocet strnadu: ")),
                          Text(widget.recording.estimatedBirdsCount.toString()),
                        ],
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
                            interactionOptions:
                            InteractionOptions(flags: InteractiveFlag.none),
                            initialCenter: parts.isNotEmpty
                                ? LatLng(parts[0]!.gpsLatitudeStart,
                                parts[0]!.gpsLongitudeStart)
                                : LatLng(0.0, 0.0),
                            initialZoom: 13.0,
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
                                  point: parts.isNotEmpty
                                      ? LatLng(parts[0]!.gpsLatitudeStart,
                                      parts[0]!.gpsLongitudeStart)
                                      : LatLng(0.0, 0.0),
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
    );
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
