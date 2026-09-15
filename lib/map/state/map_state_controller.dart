import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/services/map_api_service.dart';
import 'package:strnadi/dialects/dialect_definition.dart';
import 'package:strnadi/map/filters/map_filter_defaults.dart';
import 'package:strnadi/map/filters/map_filter_selection.dart';
import 'package:strnadi/map/filters/recording_author_filter.dart';

/// Identity only: map state never stores access tokens.
@immutable
class MapSessionScope {
  const MapSessionScope({
    required this.host,
    this.sessionId,
    this.userId,
    this.verified = false,
  });
  final String host;
  final String? sessionId, userId;
  final bool verified;

  @override
  bool operator ==(Object other) =>
      other is MapSessionScope &&
      host == other.host &&
      sessionId == other.sessionId &&
      userId == other.userId &&
      verified == other.verified;
  @override
  int get hashCode => Object.hash(host, sessionId, userId, verified);
}

@immutable
class MapViewport {
  const MapViewport({
    required this.center,
    required this.zoom,
    required this.size,
    required this.devicePixelRatio,
  });
  final LatLng center;
  final double zoom, devicePixelRatio;
  final Size size;
  bool get isValid =>
      size.width > 0 &&
      size.height > 0 &&
      size.width.isFinite &&
      size.height.isFinite;
}

/// Owns server-feature state independently of Flutter Map and platform services.
class MapStateController extends ChangeNotifier {
  MapStateController({
    required MapDataSource api,
    required Future<MapSessionScope> Function() readScope,
    required String Function() currentHost,
    Logger? logger,
    MapFilterSelection initialFilters = mapFilterDefaults,
  }) : _api = api,
       _readScope = readScope,
       _currentHost = currentHost,
       _logger = logger ?? Logger(),
       _filters = initialFilters;

  final MapDataSource _api;
  final Future<MapSessionScope> Function() _readScope;
  final String Function() _currentHost;
  final Logger _logger;
  MapFilterSelection _filters;
  MapViewport? _viewport;
  MapSessionScope? _scope;
  List<MapCluster> _features = const [];
  // These are built-in legend definitions, never stand-in recording results.
  List<String> _legendCodes = List.unmodifiable(fallbackDialectHintCodes);
  bool _loading = true, _failed = false, _disposed = false;
  bool _canFilterByUser = false;
  Timer? _debounce;
  String? _legendHost, _legendLoadingHost;
  int _revision = 0, _legendRevision = 0;

  MapFilterSelection get filters => _filters;
  List<MapCluster> get features => _features;
  List<String> get legendCodes => _legendCodes;
  bool get isLoading => _loading;
  bool get refreshFailed => _failed;
  bool get canFilterByUser => _canFilterByUser;
  MapSessionScope? get scope => _scope;
  int get revision => _revision;

  bool isCurrentRevision(int revision) => !_disposed && revision == _revision;

  void updateViewport(MapViewport viewport, {bool immediate = false}) {
    if (_disposed) return;
    _viewport = viewport;
    invalidatePending();
    if (!viewport.isValid) return;
    if (immediate) {
      unawaited(refresh());
    } else {
      _debounce = Timer(const Duration(milliseconds: 250), refresh);
    }
  }

  /// Called while a programmatic camera animation is still in progress.
  void invalidatePending() {
    _revision++;
    _debounce?.cancel();
  }

  void applyFilters(MapFilterSelection next) {
    if (_disposed || next == _filters) return;
    final dataChanged =
        next.copyWith(satelliteView: _filters.satelliteView) != _filters;
    _filters = next;
    if (dataChanged) {
      invalidatePending();
      _features = const [];
      _scope = null;
      _failed = false;
    }
    notifyListeners();
    if (dataChanged) unawaited(refresh());
  }

  void resetFilters() => applyFilters(mapFilterDefaults);

  Future<void> refresh() async {
    if (_disposed || _viewport?.isValid != true) return;
    _debounce?.cancel();
    final requestId = ++_revision;
    final viewport = _viewport!;
    final filters = _filters;
    final host = _currentHost();
    MapSessionScope? requestedScope;
    _loading = true;
    _failed = false;
    notifyListeners();
    try {
      final scope = await _readScope();
      requestedScope = scope;
      if (!isCurrentRevision(requestId) ||
          host != _currentHost() ||
          scope.host != host)
        return;
      if (_scope != null && _scope != scope) {
        _features = const [];
        _scope = null;
      }
      if (_legendHost != host && _legendLoadingHost != host) {
        _legendCodes = List.unmodifiable(fallbackDialectHintCodes);
        unawaited(refreshLegend());
      }
      _canFilterByUser = scope.verified;
      notifyListeners();
      final effectiveFilters = filters.featureFilters.forUser(
        signedIn: scope.verified,
      );
      final author = resolveRecordingAuthorFilter(
        requestedFilter: filters.authorFilter,
        requiresUserId: effectiveFilters.hideOthersWithoutMeaningfulDialect,
        storedUserId: scope.verified ? scope.userId : null,
      );
      if (!author.isAvailable) {
        _features = const [];
        _scope = null;
        _canFilterByUser = false;
        _failed = true;
        return;
      }
      final response = await _api.fetchFeatures(
        MapClustersRequest(
          center: viewport.center,
          zoom: viewport.zoom,
          viewportWidthPx: viewport.size.width,
          viewportHeightPx: viewport.size.height,
          devicePixelRatio: viewport.devicePixelRatio,
          dialectMode: switch (filters.dialectVisibility) {
            DialectVisibilityMode.all => 'All',
            DialectVisibilityMode.aiAdmin => 'AiAdmin',
            DialectVisibilityMode.adminOnly => 'AdminOnly',
          },
          clustered: filters.clustered,
          featureFilters: effectiveFilters,
          ownerScope: switch (filters.authorFilter) {
            'me' => 'Mine',
            'others' => 'Others',
            _ => 'All',
          },
          userId: author.userId,
          createdFrom: switch (filters.recordingAge) {
            RecordingAgeFilter.newer => DateTime(2025, 1, 1),
            RecordingAgeFilter.older => DateTime(2011, 1, 1),
            RecordingAgeFilter.all => null,
          },
          createdTo: filters.recordingAge == RecordingAgeFilter.older
              ? DateTime(2016, 12, 31)
              : null,
        ),
        host: host,
      );
      if (!await _requestIsCurrent(requestId, scope)) return;
      _features = List.unmodifiable(response.features);
      _scope = scope;
      _failed = false;
    } catch (error) {
      if (isCurrentRevision(requestId) &&
          host == _currentHost() &&
          (requestedScope == null ||
              await _requestIsCurrent(requestId, requestedScope))) {
        _failed = true;
        _logger.w(
          error is MapApiException
              ? error.toString()
              : 'Current map data could not be loaded (${error.runtimeType}).',
        );
      }
    } finally {
      if (isCurrentRevision(requestId)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _requestIsCurrent(int requestId, MapSessionScope scope) async {
    if (!isCurrentRevision(requestId) || _currentHost() != scope.host) {
      return false;
    }
    try {
      final current = await _readScope();
      if (isCurrentRevision(requestId) && _scope != null && _scope != current) {
        _features = const [];
        _scope = null;
        _canFilterByUser = current.verified;
        notifyListeners();
      }
      return isCurrentRevision(requestId) &&
          current == scope &&
          _currentHost() == scope.host;
    } catch (_) {
      if (isCurrentRevision(requestId) && _currentHost() == scope.host) {
        _features = const [];
        _scope = null;
        _canFilterByUser = false;
        _failed = true;
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> isScopeCurrent() async {
    final scope = _scope;
    return scope != null && await _requestIsCurrent(_revision, scope);
  }

  Future<void> refreshLegend() async {
    final requestId = ++_legendRevision;
    final host = _currentHost();
    _legendLoadingHost = host;
    try {
      final codes = await _api.fetchLegend(host: host);
      if (_disposed || requestId != _legendRevision || host != _currentHost())
        return;
      if (codes.isNotEmpty) _legendCodes = List.unmodifiable(codes);
      _legendHost = host;
      notifyListeners();
    } catch (_) {
      // Keep reference definitions when the backend legend is unavailable.
    } finally {
      if (requestId == _legendRevision) _legendLoadingHost = null;
    }
  }

  Future<MapClusterItemsPage> loadClusterPage(
    MapCluster cluster,
    String cursor,
    int revision,
  ) async {
    final scope = _scope;
    if (scope == null || !await _requestIsCurrent(revision, scope)) {
      throw ClusterSnapshotExpired();
    }
    final page = await _api.fetchClusterItems(
      cluster.id,
      cursor,
      host: scope.host,
    );
    if (!await _requestIsCurrent(revision, scope)) {
      throw ClusterSnapshotExpired();
    }
    return page;
  }

  Future<MapRecordingDetail?> openRecording(int recordingId) async {
    final scope = _scope;
    final requestId = _revision;
    if (scope == null || !await _requestIsCurrent(requestId, scope))
      return null;
    try {
      final result = await _api.fetchRecording(recordingId, host: scope.host);
      return await _requestIsCurrent(requestId, scope) ? result : null;
    } catch (error) {
      _logger.w('Could not open map recording (${error.runtimeType}).');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    invalidatePending();
    _legendRevision++;
    super.dispose();
  }
}
