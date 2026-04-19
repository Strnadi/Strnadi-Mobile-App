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
import 'dart:convert';

import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/userData.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'dart:math' as math;
import 'package:scidart/numdart.dart' as numdart;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/map/RecordingPage.dart';
import 'package:strnadi/map/mapUtils/dialect_marker_selection.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:strnadi/map/mapUtils/recordingParser.dart';
import 'package:strnadi/map/searchBar.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import '../config/config.dart';
import 'dart:async';
import 'package:strnadi/locationService.dart'; // Use the location service

import '../database/Models/detectedDialect.dart';
import '../database/Models/filteredRecordingPart.dart';
import '../database/databaseNew.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';

import '../navigation/scaffold_with_bottom_bar.dart';

final logger = Logger();
final MAPY_CZ_API_KEY = Config.mapsApiKey;

enum DialectVisibilityMode {
  all,
  aiAdmin,
  adminOnly,
}

enum RecordingAgeFilter {
  all,
  newer,
  older,
}

enum _MapMarkerStatus {
  none,
  aiAssisted,
  adminConfirmed,
}

/// Global mode deciding which dialect source is used on the map.
///
/// Default: AI+Admin
DialectVisibilityMode dialectVisibilityMode = DialectVisibilityMode.aiAdmin;

/// Global switch that decides whether recordings without any selected dialect
/// after filtering are shown on the map.
bool showDialectlessRecordings = true;

class _RecordingDialectSelection {
  final List<String> dialects;
  final bool hasAnySelectedDialect;
  final _MapMarkerStatus markerStatus;

  const _RecordingDialectSelection({
    required this.dialects,
    required this.hasAnySelectedDialect,
    required this.markerStatus,
  });
}

class MapScreenV2 extends StatefulWidget {
  const MapScreenV2({Key? key}) : super(key: key);

  @override
  State<MapScreenV2> createState() => _MapScreenV2State();
}

class _MapScreenV2State extends State<MapScreenV2> {
  static const FilteredRecordingsController _filteredRecordingsController =
      FilteredRecordingsController();
  static const RecordingsController _recordingsController =
      RecordingsController();
  static const UserController _userController = UserController();

  late bool _clusterPoints = false;

  List<Widget> markersWidgets = [];
  List<Marker> _visibleMarkers = [];
  List<FilteredRecordingPart> _cachedFilteredParts = [];
  List<DetectedDialect> _cachedDetectedDialects = [];
  bool _hasCachedDialectData = false;
  bool _isLoadingRecordings = true;
  int _activeRecordingsRequestId = 0;

  /// Loads filtered recording parts from the public BE endpoint instead of the local DB cache.
  /// When [verified] is true, the BE returns only FRPs with workflow states indicating verification (1 or 2).
  /// When false, the BE can return also unverified FRPs.
  Future<({List<FilteredRecordingPart> frps, List<DetectedDialect> dds})>
      _fetchFilteredPartsFromApi({
    int? recordingId,
    required bool verified,
  }) async {
    try {
      logger.i(
          '[MapV2] GET /recordings/filtered recordingId=$recordingId verified=$verified');
      final resp = await _filteredRecordingsController.fetchFilteredParts(
        recordingId: recordingId,
        verified: verified,
      );

      if (resp.statusCode == 204) {
        logger.i('[MapV2] /recordings/filtered returned 204 No Content');
        return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
      }
      if (resp.statusCode != 200) {
        logger.e('[MapV2] /recordings/filtered failed: ' +
            resp.statusCode.toString() +
            ' body=' +
            resp.data.toString());
        return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
      }

      final dynamic decoded =
          resp.data is String ? jsonDecode(resp.data as String) : resp.data;
      if (decoded is! List) {
        logger.w('[MapV2] /recordings/filtered returned non-list payload');
        return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
      }
      final List<dynamic> jsonArr = decoded;
      final frps = <FilteredRecordingPart>[];
      final dds = <DetectedDialect>[];

      for (final item in jsonArr) {
        if (item is! Map<String, dynamic>) continue;
        final frp = FilteredRecordingPart.fromBEJson(item);
        frps.add(frp);

        final List<dynamic>? dialects =
            item['detectedDialects'] as List<dynamic>?;
        if (dialects != null) {
          for (final d in dialects) {
            if (d is! Map<String, dynamic>) continue;
            final row = DetectedDialect.fromBEJson(d,
                parentFilteredPartBEID: frp.BEId ?? -1);
            dds.add(row);
          }
        }
      }

      logger.i('[MapV2] /recordings/filtered parsed: FRPs=' +
          frps.length.toString() +
          ', DDs=' +
          dds.length.toString());
      return (frps: frps, dds: dds);
    } catch (e, st) {
      logger.e('[MapV2] /recordings/filtered exception: ' + e.toString(),
          error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
      return (frps: <FilteredRecordingPart>[], dds: <DetectedDialect>[]);
    }
  }

  final MapController _mapController = MapController();
  // Legend dialect codes (start with local defaults; replace with BE list when available)
  List<String> _legendCodes = DynamicIcon.getDefaultDialectKeys();
  bool _isSatelliteView = false;
  String _recordingAuthorFilter = 'all';
  RecordingAgeFilter _recordingAgeFilter = RecordingAgeFilter.all;
  DialectVisibilityMode _dialectVisibilityMode = dialectVisibilityMode;
  bool _showDialectlessRecordings = showDialectlessRecordings;
  List<Polyline> _gridLines = [];
  Map<int, _RecordingDialectSelection> _dialectsByRecording = {};
  Set<int> _hiddenRecordingIds = <int>{};
  // Map local recordingId -> BEId (server id) for consistent lookups
  final Map<int, int> _recLocalToBE = {};
  final Map<int, Recording> _recordingsByBeId = {};
  static final DateTime _oldRecordingCutoff = DateTime(2024, 1, 1);
  static const double _autoClusterZoomThreshold = 9.2;
  static const double _ungroupedBoundsPaddingFactor = 0.18;

  final secureStorage = const FlutterSecureStorage();
  StreamSubscription? _positionStreamSubscription;
  StreamSubscription<MapEvent>? _mapEventSubscription;

  bool get _shouldUseClusterRendering =>
      _clusterPoints || _currentZoom <= _autoClusterZoomThreshold;

  String _canonicalizeDialect(String? value) {
    if (value == null) return '';
    final english = DialectKeywordTranslator.toEnglish(value) ?? value.trim();
    if (english.isEmpty) return '';
    switch (english) {
      case 'Unassessed':
      case 'Undetermined':
      case 'Unknown dialect':
        return 'Unknown';
      default:
        return english;
    }
  }

  List<String> _canonicalizeDialectList(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in values) {
      final canonical = _canonicalizeDialect(raw);
      if (canonical.isEmpty) continue;
      if (seen.add(canonical)) {
        result.add(canonical);
      }
    }
    return result;
  }

  String _dialectVisibilityModeForLog() {
    switch (_dialectVisibilityMode) {
      case DialectVisibilityMode.all:
        return 'all';
      case DialectVisibilityMode.aiAdmin:
        return 'aiAdmin';
      case DialectVisibilityMode.adminOnly:
        return 'adminOnly';
    }
  }

  DialectSummaryMode _dialectSummaryMode() {
    switch (_dialectVisibilityMode) {
      case DialectVisibilityMode.all:
        return DialectSummaryMode.all;
      case DialectVisibilityMode.aiAdmin:
        return DialectSummaryMode.aiAdmin;
      case DialectVisibilityMode.adminOnly:
        return DialectSummaryMode.adminOnly;
    }
  }

  // Store the current camera values.
  LatLng _currentCenter = LatLng(50.0755, 14.4378);
  LatLng _currentPosition = LatLng(50.0755, 14.4378);
  double _currentZoom = 13;

  List<Part> _recordings = [];

  List<Recording> _fullRecordings = [];

  late int length = 0;

  Size? _mapSize;

  late bool _isGuestUser = false;

  Future<void> _loadGuestStatus() async {
    final storage = const FlutterSecureStorage();
    final userId = await storage.read(key: 'userId');
    if (!mounted) return;
    setState(() {
      _isGuestUser = userId == null || userId.isEmpty;
    });
  }

  void _setRecordingsLoading(bool value) {
    if (!mounted || _isLoadingRecordings == value) {
      return;
    }
    setState(() {
      _isLoadingRecordings = value;
    });
  }

  bool _matchesRecordingAge(Recording recording) {
    switch (_recordingAgeFilter) {
      case RecordingAgeFilter.all:
        return true;
      case RecordingAgeFilter.newer:
        return !recording.createdAt.isBefore(_oldRecordingCutoff);
      case RecordingAgeFilter.older:
        return recording.createdAt.isBefore(_oldRecordingCutoff);
    }
  }

  Future<void> _refreshLegendCodes() async {
    try {
      final beCodes = await DynamicIcon.fetchAllDialectCodesFromServer();
      if (!mounted) return;
      if (beCodes.isNotEmpty) {
        final canonicalCodes = _canonicalizeDialectList(beCodes);
        // Sort with 'Unknown' last to keep UI neat
        canonicalCodes.sort((a, b) {
          if (a == 'Unknown') return 1;
          if (b == 'Unknown') return -1;
          return a.toLowerCase().compareTo(b.toLowerCase());
        });
        setState(() {
          _legendCodes = canonicalCodes;
        });
        logger.i('[MapV2] Legend codes updated from BE (' +
            canonicalCodes.length.toString() +
            ')');
      } else {
        logger.w('[MapV2] Legend codes: BE returned empty; keeping defaults');
      }
    } catch (e, st) {
      logger.w('[MapV2] Legend codes refresh failed: ' + e.toString(),
          error: e, stackTrace: st);
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.notification.title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage("Please enable location services");
        logger.w("Location services are not enabled");
        setState(() {
          _currentPosition = LatLng(50.0755, 14.4378);
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w("Location permissions are denied");
          setState(() {
            _currentPosition = LatLng(50.0755, 14.4378);
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        logger.w("Location permissions are permanently denied");
        setState(() {
          _currentPosition = LatLng(50.0755, 14.4378);
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      logger.t('current possition initialized');
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController.move(_currentPosition, _currentZoom);
    } catch (e, stackTrace) {
      logger.e("Error retrieving location: $e",
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGuestStatus();
    _currentPosition = LatLng(
        LocationService().lastKnownPosition?.latitude ?? 0.0,
        LocationService().lastKnownPosition?.longitude ?? 0.0);

    _getCurrentLocation();

    unawaited(getRecordings());

    // Subscribe to the centralized location stream.
    _positionStreamSubscription =
        LocationService().positionStream.listen((Position position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    });

    _mapEventSubscription = _mapController.mapEventStream.listen((event) {
      if (event is MapEventMoveEnd) {
        final bool wasUsingClusterRendering = _shouldUseClusterRendering;
        _currentCenter = event.camera.center;
        _currentZoom = event.camera.zoom;
        _updateGrid();
        final bool isUsingClusterRendering = _shouldUseClusterRendering;
        if (isUsingClusterRendering != wasUsingClusterRendering ||
            !isUsingClusterRendering) {
          unawaited(_rebuildMapMarkers());
        }
      }
    });

    // Warm legend codes from BE (non-blocking). UI shows defaults immediately.
    // When BE responds, we update the list without showing an empty placeholder.
    unawaited(_refreshLegendCodes());
  }

  Future<void> fetchClusters() async {
    final markers = getDialectSeparatedRecordings();
    final entries = markers.entries.toList();
    final dialectKeys =
        entries.map((entry) => entry.key).toList(growable: false);
    final colors = dialectKeys.isEmpty
        ? const <Color>[]
        : await DialectColorCache.getColors(dialectKeys);
    final fallbackColors = await DialectColorCache.getColors(['Unknown']);
    final fallbackColor =
        fallbackColors.isNotEmpty ? fallbackColors.first : Colors.grey;
    final Map<String, Color> colorByDialect = <String, Color>{};
    for (int i = 0; i < dialectKeys.length && i < colors.length; i++) {
      colorByDialect[dialectKeys[i]] = colors[i];
    }
    final builtWidgets = entries
        .map((entry) => _createClusterLayer(
              entry.value,
              colorByDialect[entry.key] ?? fallbackColor,
            ))
        .toList(growable: false);

    if (!mounted || !_shouldUseClusterRendering) return;
    setState(() {
      markersWidgets = builtWidgets;
    });

    logger.i('[MapV2] clusters rebuilt: buckets=' + markers.length.toString());
  }

  bool _shouldShowRecordingOnMap(int recordingBEId) {
    final Recording? recording = _recordingsByBeId[recordingBEId];
    if (recording != null && !_matchesRecordingAge(recording)) {
      return false;
    }
    if (_hiddenRecordingIds.contains(recordingBEId)) {
      return false;
    }
    final entry = _dialectsByRecording[recordingBEId];
    if (entry == null) return true;
    return _showDialectlessRecordings || entry.hasAnySelectedDialect;
  }

  Future<void> _rebuildMapMarkers() async {
    final bool shouldUseClusterRendering = _shouldUseClusterRendering;
    final markers = shouldUseClusterRendering
        ? const <Marker>[]
        : _buildRecordingMarkers(
            visibleBounds: _expandedVisibleBoundsForUngrouped(),
          );
    if (!mounted) return;
    setState(() {
      _visibleMarkers = markers;
      if (!shouldUseClusterRendering) {
        markersWidgets = const <Widget>[];
      }
    });

    if (!shouldUseClusterRendering) {
      return;
    }

    await fetchClusters();
  }

  Future<void> getRecordings() async {
    final int requestId = ++_activeRecordingsRequestId;
    _setRecordingsLoading(true);
    try {
      int? userId;
      //String? email;
      if (_recordingAuthorFilter == 'me') {
        userId = int.parse((await secureStorage.read(key: 'userId'))!);
      }

      final response = await _recordingsController.fetchRecordings(
        userId: userId?.toString(),
        includeParts: true,
        includeSound: false,
      );
      if (response.statusCode == 200) {
        logger.i('Recordings fetched');
        final dynamic decoded = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (decoded is! List) {
          logger
              .e('Failed to parse recordings payload: ${decoded.runtimeType}');
          return;
        }
        final List<dynamic> data = decoded;
        final String responseBody = response.data is String
            ? response.data as String
            : jsonEncode(data);
        final List<Part> parts = getParts(jsonEncode(data));
        final List<Recording> recordings = await GetRecordings(responseBody);

        length = 0;
        for (int i = 0; i < parts.length; i++) {
          length += parts[i].length ?? 0;
        }
        if (!mounted || requestId != _activeRecordingsRequestId) {
          return;
        }
        _recordingsByBeId
          ..clear()
          ..addEntries(
            recordings
                .where((recording) => recording.BEId != null)
                .map((recording) => MapEntry(recording.BEId!, recording)),
          );
        // Build local->BE id map for consistent lookups
        _recLocalToBE.clear();
        for (final r in recordings) {
          if (r.id != null && r.BEId != null) {
            _recLocalToBE[r.id!] = r.BEId!;
          }
        }
        setState(() {
          _recordings = parts;
          _fullRecordings = recordings;
          _visibleMarkers = const <Marker>[];
        });
        logger.i(
            '[MapV2] getRecordings(): parts=${parts.length}, totalLength=$length');
        logger.i('[MapV2] getRecordings(): local->BE map size=' +
            _recLocalToBE.length.toString());
        logger
            .i('[MapV2] getRecordings(): fullRecordings=${recordings.length}');
        await _fetchDialects(refreshFromApi: true, requestId: requestId);
      } else {
        logger.e(
            'Failed to fetch recordings ${response.statusCode} | ${response.data}');
      }
    } catch (error, stackTrace) {
      logger.e("Error generariong map $error",
          error: error, stackTrace: stackTrace);
    } finally {
      if (requestId == _activeRecordingsRequestId) {
        _setRecordingsLoading(false);
      }
    }
  }

  Future<void> _fetchDialects({
    bool refreshFromApi = true,
    int? requestId,
  }) async {
    try {
      // Snapshot sizes for quick diagnosis
      logger.i('[MapV2] _fetchDialects(): start; fullRecs=' +
          _fullRecordings.length.toString() +
          ', dialectMode=' +
          _dialectVisibilityModeForLog() +
          ', showDialectless=' +
          _showDialectlessRecordings.toString());

      // Always fetch all FRPs from BE to keep map filtering fully client-side.
      final List<FilteredRecordingPart> frps;
      final List<DetectedDialect> dds;
      if (refreshFromApi || !_hasCachedDialectData) {
        final api = await _fetchFilteredPartsFromApi(
          verified: false,
        );
        if (requestId != null && requestId != _activeRecordingsRequestId) {
          return;
        }
        frps = api.frps;
        dds = api.dds;
        _cachedFilteredParts = frps;
        _cachedDetectedDialects = dds;
        _hasCachedDialectData = true;
      } else {
        frps = _cachedFilteredParts;
        dds = _cachedDetectedDialects;
        logger.i('[MapV2] _fetchDialects(): using cached filtered data');
      }
      if (frps.isNotEmpty) {
        logger.d('[MapV2] example FRP beId/state: ' +
            (frps.first.BEId?.toString() ?? 'null') +
            '/' +
            frps.first.state.toString());
      }

      logger.i('[MapV2] _fetchDialects(): fetched from BE; FRPs=' +
          frps.length.toString() +
          ', DDs=' +
          dds.length.toString());

      final Map<int, List<FilteredRecordingPart>> frpsByRecording =
          <int, List<FilteredRecordingPart>>{};
      for (final frp in frps) {
        final int? recordingBeId = frp.recordingBEID;
        if (recordingBeId == null) continue;
        frpsByRecording
            .putIfAbsent(recordingBeId, () => <FilteredRecordingPart>[])
            .add(frp);
      }

      final Map<int, List<DetectedDialect>> ddsByFilteredPart =
          <int, List<DetectedDialect>>{};
      for (final row in dds) {
        final int? filteredPartBeId = row.filteredPartBEID;
        if (filteredPartBeId == null) continue;
        ddsByFilteredPart
            .putIfAbsent(filteredPartBeId, () => <DetectedDialect>[])
            .add(row);
      }

      final Map<int, _RecordingDialectSelection> byRecording = {};
      final Set<int> hiddenRecordingIds = <int>{};
      int recsWithNoCodes = 0;

      for (final rec in _fullRecordings) {
        final int? beId = rec.BEId;
        if (beId == null) {
          logger.w('[MapV2] rec has null BEId, skipping');
          continue;
        }

        final recFrps =
            frpsByRecording[beId] ?? const <FilteredRecordingPart>[];
        if (recFrps.isEmpty) {
          hiddenRecordingIds.add(beId);
          continue;
        }

        final Set<String> allDialectCodes = <String>{};
        for (final frp in recFrps) {
          final rows = frp.BEId == null
              ? const <DetectedDialect>[]
              : (ddsByFilteredPart[frp.BEId!] ?? const <DetectedDialect>[]);
          for (final d in rows) {
            allDialectCodes.addAll(_allDialectCodesForRecording(d));
          }
        }
        if (allDialectCodes.isNotEmpty &&
            allDialectCodes.every(_isNoDialectCode)) {
          hiddenRecordingIds.add(beId);
          continue;
        }

        // Only representative filtered parts for this recording (by BE id)
        final reps = recFrps.where((f) => f.isRepresentant).toList();
        final bool hasState6 = reps.any((f) => f.state == 6);

        final List<DetectedDialectSnapshot> representativeRows =
            <DetectedDialectSnapshot>[];
        for (final frp in reps) {
          // Join detected dialects by BE link
          final rows = frp.BEId == null
              ? const <DetectedDialect>[]
              : (ddsByFilteredPart[frp.BEId!] ?? const <DetectedDialect>[]);

          for (final d in rows) {
            representativeRows.add(
              DetectedDialectSnapshot(
                confirmed: d.confirmedDialect,
                predicted: d.predictedDialect,
                guessed: d.userGuessDialect,
              ),
            );
          }
        }

        final summary = summarizeRecordingDialects(
          rows: representativeRows,
          mode: _dialectSummaryMode(),
          canonicalize: _canonicalizeDialect,
        );

        // Fallback when no codes collected
        List<String> out;
        if (!summary.hasAnySelectedDialect) {
          recsWithNoCodes++;
          logger.w('[MapV2] recBE=' +
              beId.toString() +
              ': no dialect codes collected; fallback=Unknown (repFRPs=' +
              reps.length.toString() +
              ')');
          out = <String>['Unknown'];
        } else {
          out = List<String>.from(summary.dialects);

          logger.i('[MapV2] recBE=' +
              beId.toString() +
              ': codes=[' +
              out.join(',') +
              '] tier=' +
              summary.selectedTier.name);
        }

        // Clamp to two dialects to enable diagonal split; more than two would fall back to mix otherwise
        if (out.length > 2) {
          logger.w('[MapV2] recBE=' +
              beId.toString() +
              ': >2 dialects detected; clamping to first two for split visual');
          out = out.take(2).toList();
        }

        final normalized =
            _canonicalizeDialectList(out.isEmpty ? <String>['Unknown'] : out);
        final _MapMarkerStatus markerStatus =
            summary.selectedTier == SelectedDialectTier.confirmed
                ? _MapMarkerStatus.adminConfirmed
                : (summary.selectedTier == SelectedDialectTier.predicted ||
                        (!summary.hasAnySelectedDialect && hasState6))
                    ? _MapMarkerStatus.aiAssisted
                    : _MapMarkerStatus.none;
        byRecording[beId] = _RecordingDialectSelection(
          dialects: normalized,
          hasAnySelectedDialect: summary.hasAnySelectedDialect,
          markerStatus: markerStatus,
        );
      }

      if (!mounted ||
          (requestId != null && requestId != _activeRecordingsRequestId)) {
        return;
      }
      setState(() {
        _dialectsByRecording = byRecording;
        _hiddenRecordingIds = hiddenRecordingIds;
      });
      logger.i('[MapV2] _fetchDialects(): done; records=' +
          byRecording.length.toString() +
          ', hidden=' +
          hiddenRecordingIds.length.toString() +
          ', visible=' +
          (_fullRecordings.length - hiddenRecordingIds.length).toString() +
          ', emptyOrUnknown=' +
          recsWithNoCodes.toString());
      await _rebuildMapMarkers();
    } catch (e, stackTrace) {
      logger.e('Failed to fetch representative dialects: ' + e.toString(),
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  List<String> _dialectsForRecordingId(int recordingBEId) {
    final entry = _dialectsByRecording[recordingBEId];
    if (entry == null || entry.dialects.isEmpty) return const ['Unknown'];
    return _canonicalizeDialectList(entry.dialects);
  }

  _MapMarkerStatus _markerStatusForRecording(int beId) =>
      _dialectsByRecording[beId]?.markerStatus ?? _MapMarkerStatus.none;

  List<String> _allDialectCodesForRecording(DetectedDialect row) {
    final List<String> codes = <String>[];

    void addIfPresent(String? value) {
      final String canonical = _canonicalizeDialect(value);
      if (canonical.isNotEmpty) {
        codes.add(canonical);
      }
    }

    addIfPresent(row.confirmedDialect);
    addIfPresent(row.predictedDialect);
    addIfPresent(row.userGuessDialect);

    return codes;
  }

  bool _isNoDialectCode(String value) {
    return _canonicalizeDialect(value) == 'No Dialect';
  }

  LatLngBounds? _expandedVisibleBoundsForUngrouped() {
    if (_mapSize == null) {
      return null;
    }
    final bounds = calculateBounds();
    final double latPadding =
        (bounds.north - bounds.south) * _ungroupedBoundsPaddingFactor;
    final double lonPadding =
        (bounds.east - bounds.west) * _ungroupedBoundsPaddingFactor;
    return LatLngBounds.unsafe(
      north: math.min(LatLngBounds.maxLatitude, bounds.north + latPadding),
      south: math.max(LatLngBounds.minLatitude, bounds.south - latPadding),
      east: math.min(LatLngBounds.maxLongitude, bounds.east + lonPadding),
      west: math.max(LatLngBounds.minLongitude, bounds.west - lonPadding),
    );
  }

  Map<int, Part> _latestPartPerRecording() {
    // Keep only the last part we saw for each recordingId (assuming parts arrive in chronological order)
    final Map<int, Part> lastPartByRecording = <int, Part>{};
    for (final p in _recordings) {
      lastPartByRecording[p.recordingId] = p; // last wins
    }
    return lastPartByRecording;
  }

  List<Marker> _buildRecordingMarkers({
    LatLngBounds? visibleBounds,
  }) {
    final lastPartByRecording = _latestPartPerRecording();

    final markers = <Marker>[];
    lastPartByRecording.forEach((recId, part) {
      final point = LatLng(part.gpsLatitudeStart, part.gpsLongitudeStart);
      if (visibleBounds != null && !visibleBounds.contains(point)) {
        return;
      }
      final beId =
          _recLocalToBE[recId] ?? recId; // fall back if equal in some datasets
      if (!_shouldShowRecordingOnMap(beId)) return;
      final dList = _dialectsForRecordingId(beId);
      final markerStatus = _markerStatusForRecording(beId);
      final dialects = dList;
      markers.add(
        Marker(
          width: 30.0,
          height: 30.0,
          point: point,
          child: KeyedSubtree(
            key: ValueKey('marker_${beId}_${dialects.join('+')}'),
            child: GestureDetector(
              onTap: () {
                getRecordingFromPartId(beId);
              },
              child: SizedBox(
                width: 30.0,
                height: 30.0,
                child: Center(
                  child: DynamicIcon(
                    key: ValueKey('rec_${beId}_${dialects.join('+')}'),
                    icon: Icons.circle,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.transparent,
                    dialects:
                        dialects, // <- array, e.g. ['BC','XB'] or ['Unknown']
                    cacheKey: 'be:' +
                        beId.toString() +
                        ';dialects:' +
                        dialects.join('+'),
                    showCenterDot: markerStatus == _MapMarkerStatus.aiAssisted,
                    dotColor: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    logger.i('[MapV2] visible markers rebuilt=' + markers.length.toString());
    return markers;
  }

  Map<String, List<Marker>> getDialectSeparatedRecordings() {
    final Map<String, List<Marker>> dialectMarkers = <String, List<Marker>>{};

    final lastPartByRecording = _latestPartPerRecording();

    lastPartByRecording.forEach((localId, rec) {
      final beId = _recLocalToBE[localId] ?? localId;
      if (!_shouldShowRecordingOnMap(beId)) {
        return;
      }
      var dialects = _dialectsForRecordingId(beId);
      final markerStatus = _markerStatusForRecording(beId);
      final point = LatLng(rec.gpsLatitudeStart, rec.gpsLongitudeStart);

      var marker = Marker(
        width: 30.0,
        height: 30.0,
        point: point,
        child: KeyedSubtree(
          key: ValueKey('marker_${beId}_${dialects.join('+')}'),
          child: GestureDetector(
            onTap: () {
              getRecordingFromPartId(beId);
            },
            child: SizedBox(
              width: 30.0,
              height: 30.0,
              child: Center(
                child: DynamicIcon(
                  key: ValueKey('rec_${beId}_${dialects.join('+')}'),
                  icon: Icons.circle,
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  dialects:
                      dialects, // <- array, e.g. ['BC','XB'] or ['Unknown']
                  cacheKey: 'be:' +
                      beId.toString() +
                      ';dialects:' +
                      dialects.join('+'),
                  showCenterDot: markerStatus == _MapMarkerStatus.aiAssisted,
                  dotColor: Colors.black,
                ),
              ),
            ),
          ),
        ),
      );

      if (dialects.length == 1) {
        var dialect = dialects[0];
        if (dialectMarkers.containsKey(dialect)) {
          dialectMarkers[dialect]!.add(marker);
        } else {
          dialectMarkers[dialect] = [marker];
        }
      } else {
        if (dialectMarkers.containsKey('rest')) {
          dialectMarkers['rest']!.add(marker);
        } else {
          dialectMarkers['rest'] = [marker];
        }
      }
    });
    logger.i(
        '[MapV2] cluster buckets rebuilt=' + dialectMarkers.length.toString());
    return dialectMarkers;
  }

  Future<(String?, String?)?> getProfilePic(int? userId_) async {
    final int? userId = userId_;
    if (userId == null) {
      return null;
    }

    try {
      final value = await _userController.getProfilePhoto(userId);
      if (value.statusCode == 200) {
        final dynamic payload = value.data is String
            ? jsonDecode(value.data as String)
            : value.data;
        if (payload is Map) {
          final map = payload.cast<String, dynamic>();
          return (map['photoBase64']?.toString(), map['format']?.toString());
        }
      } else {
        logger.e(
            "Profile picture download failed with status code ${value.statusCode}");
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Future<UserData?> getUser(Recording rec) async {
    final int? userId = rec.userId;
    if (userId == null) {
      return null;
    }

    try {
      final userResponse = await _userController.getUserById(userId);
      if (userResponse.statusCode != 200) {
        logger.e(
            'Failed to fetch user profile. status=${userResponse.statusCode}');
        return null;
      }

      final dynamic payload = userResponse.data is String
          ? json.decode(userResponse.data as String)
          : userResponse.data;
      if (payload is! Map) {
        logger
            .e('Failed to parse user profile payload: ${payload.runtimeType}');
        return null;
      }

      final resp = UserData.fromJson(payload.cast<String, dynamic>());
      await getProfilePic(userId);
      return resp;
      // if (profilePicData!.$1 == null || profilePicData.$2 == null){
      //   logger.i(resp);
      //   return resp;
      // }
      // else{
      //   resp.ProfilePic = profilePicData.$1;
      //   resp.format = profilePicData.$2;
      //   return resp;
      // }
    } catch (e) {
      Sentry.captureException(e, stackTrace: StackTrace.current);
      return null;
    }
  }

  void getRecordingFromPartId(int id) async {
    for (int rec = 0; rec < _fullRecordings.length; rec++) {
      if (_fullRecordings[rec].BEId == id) {
        UserData? user = await getUser(_fullRecordings[rec]);
        await DatabaseNew.getRecordingPartByBEID(_fullRecordings[rec].BEId!);

        if (!mounted) return;
        showCupertinoSheet(
          context: context,
          builder: (context) => RecordingFromMap(
            recording: _fullRecordings[rec],
            user: user,
          ),
        );
        return;
      }
    }

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(t('map.dialogs.error.title')),
              content: Text('${t('Nahrávka nenalezena')} $id'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('map.dialogs.error.close')),
                ),
              ],
            ));
  }

  Widget _createClusterLayer(List<Marker> markers, Color color) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 45,
        size: const Size(40, 40),
        alignment: Alignment.center,
        markers: markers,
        builder: (context, clusteredMarkers) {
          return Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                clusteredMarkers.length.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomSystemInset = MediaQuery.of(context).viewPadding.bottom;
    final double controlsBottomOffset = 20 + bottomSystemInset;
    final double mapyLegendBottomOffset = 10 + bottomSystemInset;

    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.map,
      appBarTitle: null,
      isGuestUser: _isGuestUser,
      showNotificationBell: false,
      content: LayoutBuilder(
        builder: (context, constraints) {
          Size newSize = constraints.biggest;
          if (_mapSize == null || _mapSize != newSize) {
            _mapSize = newSize;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateGrid();
            });
          }
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentPosition,
                  initialZoom: 13,
                  interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  minZoom: 1,
                  maxZoom: 19,
                  initialRotation: 0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapy.cz/v1/maptiles/${_isSatelliteView ? 'aerial' : 'outdoor'}/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                    userAgentPackageName: 'cz.delta.strnadi',
                  ),
                  if (_isSatelliteView)
                    TileLayer(
                      urlTemplate:
                          'https://api.mapy.cz/v1/maptiles/names-overlay/256/{z}/{x}/{y}?apikey=$MAPY_CZ_API_KEY',
                      userAgentPackageName: 'cz.delta.strnadi',
                    ),
                  PolylineLayer(
                    polylines: _gridLines,
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 20.0,
                        height: 20.0,
                        point: _currentPosition,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 30.0,
                        ),
                      ),
                    ],
                  ),
                  if (_shouldUseClusterRendering)
                    for (var widget in markersWidgets) widget,
                  if (!_shouldUseClusterRendering)
                    MarkerLayer(
                      markers: _visibleMarkers,
                    ),
                ],
              ),
              if (_isLoadingRecordings)
                Positioned(
                  top: 140,
                  left: 16,
                  right: 16,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 360),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t('map.loading.title'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    t('map.loading.subtitle'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final height = 48.0; // match the SearchBar height
                        return SizedBox(
                          width: height,
                          height: height,
                          child: FloatingActionButton(
                            heroTag: 'info',
                            mini: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            backgroundColor: Colors.white,
                            onPressed: _showLegendDialog,
                            tooltip: 'Info',
                            child: Image.asset('assets/icons/info.png',
                                width: 30, height: 30),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SearchBarWidget(
                        onLocationSelected: (LatLng location) {
                          _mapController.move(location, _currentZoom);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: controlsBottomOffset,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: FloatingActionButton(
                        heroTag: 'mapSettings',
                        mini: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.white,
                        onPressed: _openMapFilter,
                        tooltip: 'Map Settings',
                        child: Image.asset('assets/icons/sort.png',
                            width: 24, height: 24),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: FloatingActionButton(
                        heroTag: 'reset',
                        mini: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tooltip: 'Reset orientation & recenter',
                        onPressed: () async {
                          await _getCurrentLocation();
                          _mapController.move(_currentPosition, _currentZoom);
                          _updateGrid();
                        },
                        backgroundColor: Colors.white,
                        child: Image.asset('assets/icons/location.png',
                            width: 24, height: 24),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: mapyLegendBottomOffset,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  color: Colors.white70,
                  child: Text(
                    t('map.legend.mapyCz'),
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Offset latLngToPixel(LatLng latlng, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double x = (latlng.longitude + 180) / 360 * nTiles * tileSize;
    double latRad = latlng.latitude * math.pi / 180;
    double y =
        (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
            2 *
            nTiles *
            tileSize;
    return Offset(x, y);
  }

  LatLng pixelToLatLng(Offset pixel, double zoom) {
    const double tileSize = 256.0;
    double nTiles = math.pow(2, zoom).toDouble();
    double lon = pixel.dx / (nTiles * tileSize) * 360 - 180;
    double yTile = pixel.dy / (nTiles * tileSize);
    double latRad = math.atan(numdart.sinh(math.pi * (1 - 2 * yTile)));
    double lat = latRad * 180 / math.pi;
    return LatLng(lat, lon);
  }

  LatLngBounds calculateBounds() {
    if (_mapSize == null) return LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    Offset centerPixel = latLngToPixel(_currentCenter, _currentZoom);
    double width = _mapSize!.width;
    double height = _mapSize!.height;
    Offset topLeftPixel = centerPixel - Offset(width / 2, height / 2);
    Offset bottomRightPixel = centerPixel + Offset(width / 2, height / 2);
    LatLng topLeft = pixelToLatLng(topLeftPixel, _currentZoom);
    LatLng bottomRight = pixelToLatLng(bottomRightPixel, _currentZoom);
    return LatLngBounds(
      LatLng(bottomRight.latitude, topLeft.longitude),
      LatLng(topLeft.latitude, bottomRight.longitude),
    );
  }

  void _updateGrid() {
    if (_currentZoom < 7) {
      if (_gridLines.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _gridLines = [];
      });
      return;
    }
    if (_mapSize == null) return;
    final bounds = calculateBounds();
    final double northBound = bounds.north;
    final double southBound = bounds.south;
    final double westBound = bounds.west;
    final double eastBound = bounds.east;

    const double gridCellHeight = 6 / 60;
    const double gridCellWidth = 10 / 60;
    // The fixed top left (origin) of the grid:
    const double originLat = 56.0; // 56°0'N
    const double originLon = 5 + 40 / 60; // 5°40'E, i.e. ~5.666667

    List<Polyline> newGridLines = [];

    int kStartLon = ((westBound - originLon) / gridCellWidth).ceil();
    for (int k = kStartLon;; k++) {
      double gridLon = originLon + k * gridCellWidth;
      if (gridLon > eastBound) break;
      newGridLines.add(Polyline(
        points: [LatLng(northBound, gridLon), LatLng(southBound, gridLon)],
        strokeWidth: 1.0,
        color: Colors.red,
      ));
    }

    int kStartLat = ((originLat - northBound) / gridCellHeight).floor();
    for (int k = kStartLat;; k++) {
      double gridLat = originLat - k * gridCellHeight;
      if (gridLat < southBound) break;
      newGridLines.add(Polyline(
        points: [LatLng(gridLat, westBound), LatLng(gridLat, eastBound)],
        strokeWidth: 1.0,
        color: Colors.red,
      ));
    }

    setState(() {
      _gridLines = newGridLines;
    });
  }

  Future<void> _refreshDialectSelectionFromCache() async {
    _setRecordingsLoading(true);
    try {
      await _fetchDialects(refreshFromApi: false);
    } finally {
      _setRecordingsLoading(false);
    }
  }

  void _applyMapFilterSelection({
    required bool nextIsSatelliteView,
    required String nextRecordingAuthorFilter,
    required RecordingAgeFilter nextRecordingAgeFilter,
    required DialectVisibilityMode nextDialectVisibilityMode,
    required bool nextShowDialectlessRecordings,
    required bool nextClusterPoints,
  }) {
    final bool shouldReloadRecordings =
        nextRecordingAuthorFilter != _recordingAuthorFilter;
    final bool shouldRefreshDialects = !shouldReloadRecordings &&
        nextDialectVisibilityMode != _dialectVisibilityMode;
    final bool shouldRebuildMarkers = !shouldReloadRecordings &&
        !shouldRefreshDialects &&
        (nextRecordingAgeFilter != _recordingAgeFilter ||
            nextShowDialectlessRecordings != _showDialectlessRecordings ||
            nextClusterPoints != _clusterPoints);
    final bool shouldUpdateViewOnly = nextIsSatelliteView != _isSatelliteView;

    if (!shouldReloadRecordings &&
        !shouldRefreshDialects &&
        !shouldRebuildMarkers &&
        !shouldUpdateViewOnly) {
      return;
    }

    setState(() {
      _isSatelliteView = nextIsSatelliteView;
      _recordingAuthorFilter = nextRecordingAuthorFilter;
      _recordingAgeFilter = nextRecordingAgeFilter;
      _dialectVisibilityMode = nextDialectVisibilityMode;
      _showDialectlessRecordings = nextShowDialectlessRecordings;
      _clusterPoints = nextClusterPoints;
      dialectVisibilityMode = nextDialectVisibilityMode;
      showDialectlessRecordings = nextShowDialectlessRecordings;
    });

    if (shouldReloadRecordings) {
      unawaited(getRecordings());
      return;
    }
    if (shouldRefreshDialects) {
      unawaited(_refreshDialectSelectionFromCache());
      return;
    }
    if (shouldRebuildMarkers) {
      unawaited(_rebuildMapMarkers());
    }
  }

  void _openMapFilter() {
    bool tempIsSatelliteView = _isSatelliteView;
    String tempRecordingAuthorFilter = _recordingAuthorFilter;
    RecordingAgeFilter tempRecordingAgeFilter = _recordingAgeFilter;
    DialectVisibilityMode tempDialectVisibilityMode = _dialectVisibilityMode;
    bool tempShowDialectlessRecordings = _showDialectlessRecordings;
    bool tempClusterPoints = _clusterPoints;
    void applyCurrentSelection() {
      _applyMapFilterSelection(
        nextIsSatelliteView: tempIsSatelliteView,
        nextRecordingAuthorFilter: tempRecordingAuthorFilter,
        nextRecordingAgeFilter: tempRecordingAgeFilter,
        nextDialectVisibilityMode: tempDialectVisibilityMode,
        nextShowDialectlessRecordings: tempShowDialectlessRecordings,
        nextClusterPoints: tempClusterPoints,
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.2,
          maxChildSize: 0.9,
          builder: (BuildContext context, ScrollController controller) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setModalState) {
                  return Scrollbar(
                    controller: controller,
                    thumbVisibility: true,
                    child: ListView(
                      controller: controller,
                      children: [
                        Container(
                          alignment: Alignment.center,
                          child: Container(
                            width: 80,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Icon(
                            Icons.unfold_more_rounded,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            t('Nastavení mapy'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('Zobrazení mapy:')),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempIsSatelliteView = false;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: !tempIsSatelliteView
                                            ? Colors.black
                                            : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child:
                                        Text(t('map.filters.mapView.classic')),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempIsSatelliteView = true;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: tempIsSatelliteView
                                            ? Colors.black
                                            : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                        t('map.filters.mapView.satellite')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('map.filters.recordingAge.title')),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempRecordingAgeFilter =
                                          RecordingAgeFilter.older;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempRecordingAgeFilter ==
                                              RecordingAgeFilter.older
                                          ? Colors.black
                                          : Colors.grey.shade200,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      Text(t('map.filters.recordingAge.older')),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempRecordingAgeFilter =
                                          RecordingAgeFilter.newer;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempRecordingAgeFilter ==
                                              RecordingAgeFilter.newer
                                          ? Colors.black
                                          : Colors.grey.shade200,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      Text(t('map.filters.recordingAge.newer')),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempRecordingAgeFilter =
                                          RecordingAgeFilter.all;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempRecordingAgeFilter ==
                                              RecordingAgeFilter.all
                                          ? Colors.black
                                          : Colors.grey.shade200,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      Text(t('map.filters.recordingAge.all')),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('Autor nahrávky:')),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempRecordingAuthorFilter = 'all';
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color:
                                            tempRecordingAuthorFilter == 'all'
                                                ? Colors.black
                                                : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      t('map.filters.recordingAuthor.all'),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempRecordingAuthorFilter = 'me';
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: tempRecordingAuthorFilter == 'me'
                                            ? Colors.black
                                            : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                        t('map.filters.recordingAuthor.me')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Dialect visibility:'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempDialectVisibilityMode =
                                          DialectVisibilityMode.all;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempDialectVisibilityMode ==
                                              DialectVisibilityMode.all
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                      'Show all (incl. user suggestions)'),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempDialectVisibilityMode =
                                          DialectVisibilityMode.aiAdmin;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempDialectVisibilityMode ==
                                              DialectVisibilityMode.aiAdmin
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Show AI+Admin'),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempDialectVisibilityMode =
                                          DialectVisibilityMode.adminOnly;
                                    });
                                    applyCurrentSelection();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    side: BorderSide(
                                      color: tempDialectVisibilityMode ==
                                              DialectVisibilityMode.adminOnly
                                          ? Colors.black
                                          : Colors.grey,
                                    ),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Admin only'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('Zobrazovat nahrávky bez dialektu:')),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempShowDialectlessRecordings = false;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: !tempShowDialectlessRecordings
                                            ? Colors.black
                                            : Colors.grey,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(t('Skrýt')),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempShowDialectlessRecordings = true;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: tempShowDialectlessRecordings
                                            ? Colors.black
                                            : Colors.grey,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(t('Zobrazit')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('map.filters.clustering.title')),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempClusterPoints = true;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: tempClusterPoints
                                            ? Colors.black
                                            : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(t('map.filters.clustering.on')),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setModalState(() {
                                        tempClusterPoints = false;
                                      });
                                      applyCurrentSelection();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      side: BorderSide(
                                        color: !tempClusterPoints
                                            ? Colors.black
                                            : Colors.grey.shade200,
                                      ),
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child:
                                        Text(t('map.filters.clustering.off')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: () {
                              setModalState(() {
                                tempIsSatelliteView = false;
                                tempRecordingAuthorFilter = 'all';
                                tempRecordingAgeFilter = RecordingAgeFilter.all;
                                tempDialectVisibilityMode =
                                    DialectVisibilityMode.aiAdmin;
                                tempShowDialectlessRecordings = true;
                                tempClusterPoints = false;
                              });
                              applyCurrentSelection();
                            },
                            child: Text(t('map.buttons.resetFilters')),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showLegendDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        final double bottomSystemInset =
            MediaQuery.of(context).viewPadding.bottom;
        return Container(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomSystemInset),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
                Text(
                  t('map.legend.title'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildAutoDialectLegend(), // <-- auto dialects
                      // _buildSymbolLegendItem('Vzácné', 'Vzácné'),
                      // _buildSymbolLegendItem('Přechodný', 'Přechodný'),
                      // _buildSymbolLegendItem('Mix', 'Mix'),
                      // _buildSymbolLegendItem('Atypický', 'Atypický'),
                      // _buildSymbolLegendItem('Unfinished', 'Unfinished'),
                      // _buildCircleLegendItem(Colors.black, 'Nepoužitelný'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildMarkerStatusLegendItem(
                        _MapMarkerStatus.aiAssisted,
                        t('map.legend.status.aiAssisted'),
                      ),
                      _buildMarkerStatusLegendItem(
                        _MapMarkerStatus.adminConfirmed,
                        t('map.legend.status.adminConfirmed'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: const Color(0xFFFFD641),
                        foregroundColor: const Color(0xFF2D2B18),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: Text(t('map.dialogs.error.close')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutoDialectLegend() {
    final codes = List<String>.from(_legendCodes);
    // Ensure 'Unknown' appears last
    codes.sort((a, b) {
      if (a == 'Unknown') return 1;
      if (b == 'Unknown') return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });

    final items = <Widget>[];
    for (final code in codes) {
      items.add(_buildDialectLegendItem(code));
    }

    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: items,
    );
  }

  Widget _buildDialectLegendItem(String englishCode) {
    final label = englishCode == 'Unknown'
        ? t('dialectKeywords.unassessed')
        : DialectKeywordTranslator.toLocalized(englishCode);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DynamicIcon(
            icon: Icons.circle,
            iconSize: 18,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.transparent,
            dialects: [englishCode],
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildMarkerStatusLegendItem(_MapMarkerStatus status, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DynamicIcon(
            icon: Icons.circle,
            iconSize: 18,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            border: Border.all(color: Colors.black54),
            showCenterDot: status == _MapMarkerStatus.aiAssisted,
            dotColor: Colors.black,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
