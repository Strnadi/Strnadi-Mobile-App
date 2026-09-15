import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/api/controllers/maps_controller.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/services/map_api_service.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/locationService.dart';
import 'package:strnadi/map/filters/map_filter_sheet.dart';
import 'package:strnadi/map/layers/kfme_grid.dart';
import 'package:strnadi/map/layers/map_marker_layout.dart';
import 'package:strnadi/map/layers/map_tile_layers.dart';
import 'package:strnadi/map/screens/recording_detail_page.dart';
import 'package:strnadi/map/search/map_search_bar.dart';
import 'package:strnadi/map/state/map_camera_controller.dart';
import 'package:strnadi/map/state/map_state_controller.dart';
import 'package:strnadi/map/widgets/map_cluster_picker.dart';
import 'package:strnadi/map/widgets/map_controls.dart';
import 'package:strnadi/map/widgets/map_legend_sheet.dart';
import 'package:strnadi/navigation/scaffold_with_bottom_bar.dart';

class MapScreenV2 extends StatefulWidget {
  const MapScreenV2({super.key});

  @override
  State<MapScreenV2> createState() => _MapScreenV2State();
}

class _MapScreenV2State extends State<MapScreenV2> {
  final _mapController = MapController();
  late final _camera = MapCameraController(_mapController);
  late final _state = MapStateController(
    api: const MapApiService(),
    readScope: _readScope,
    currentHost: () => Config.host,
  );
  final _logger = Logger();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<MapEvent>? _mapSubscription;
  LatLng _position = initialMapPosition;
  List<Polyline> _grid = const [];
  Size? _size;
  double _devicePixelRatio = 1;
  bool _mapReady = false;

  Future<MapSessionScope> _readScope() async {
    final host = Config.host;
    final session = await activatedAuthSessions.capture();
    return MapSessionScope(
      host: host,
      sessionId: session?.sessionId,
      userId: session?.userId,
      verified: session?.verified == true,
    );
  }

  @override
  void initState() {
    super.initState();
    _position = LocationService().lastKnownPosition ?? initialMapPosition;
    _state.addListener(_redraw);
    unawaited(_state.refreshLegend());
    unawaited(_locate());
    _positionSubscription = LocationService().positionStream.listen((position) {
      if (mounted) {
        setState(
          () => _position = LatLng(position.latitude, position.longitude),
        );
      }
    });
    _mapSubscription = _mapController.mapEventStream.listen((event) {
      if (!mounted) return;
      if (event is MapEventWithMove) {
        if (event.source == MapEventSource.mapController &&
            _camera.isAnimating) {
          return;
        }
        _camera.cancelAnimation();
        _refreshViewport();
      }
      if (event is MapEventMoveEnd ||
          event is MapEventFlingAnimationEnd ||
          event is MapEventDoubleTapZoomEnd) {
        _updateGrid();
        _refreshViewport();
      }
    });
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _refreshViewport({bool immediate = false}) {
    if (!mounted || !_mapReady || _size == null) return;
    _state.updateViewport(
      MapViewport(
        center: _mapController.camera.center,
        zoom: _mapController.camera.zoom,
        size: _size!,
        devicePixelRatio: _devicePixelRatio,
      ),
      immediate: immediate,
    );
  }

  void _updateGrid() {
    if (!_mapReady || !mounted) return;
    final camera = _mapController.camera;
    setState(
      () => _grid = buildKfmeGrid(
        bounds: camera.visibleBounds,
        zoom: camera.zoom,
      ),
    );
  }

  void _moveTo(LatLng location) {
    if (!_mapReady || !mounted) return;
    _camera.cancelAnimation();
    _mapController.move(location, _mapController.camera.zoom);
    _updateGrid();
    _refreshViewport(immediate: true);
  }

  Future<void> _locate() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!mounted) return;
      if (!serviceEnabled) {
        _showLocationMessage(t('map.notifications.enableLocation'));
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (!mounted) return;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (!mounted) return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;
      final location = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(
          () => _position = LatLng(location.latitude, location.longitude),
        );
      }
    } catch (error) {
      _logger.w('Could not retrieve map location (${error.runtimeType}).');
    } finally {
      if (mounted) _moveTo(_position);
    }
  }

  void _showLocationMessage(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.notification.title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _selectFeature(MapCluster feature) async {
    final revision = _state.revision;
    if (!await _state.isScopeCurrent()) {
      if (mounted) unawaited(_state.refresh());
      return;
    }
    if (!mounted || !_state.isCurrentRevision(revision)) return;
    if (feature.isRecording) {
      await _openRecording(feature.recording!.recordingId);
      return;
    }
    final target = clusterZoomTarget(
      feature,
      _mapController.camera.zoom,
      _size ?? Size.zero,
    );
    if (target == null) {
      await _showClusterPicker(feature);
      return;
    }
    _state.invalidatePending();
    _camera.animateTo(
      center: LatLng(target.latitude, target.longitude),
      zoom: target.zoom,
      onSettled: () {
        _updateGrid();
        _refreshViewport(immediate: true);
      },
    );
  }

  Future<void> _showClusterPicker(MapCluster feature) {
    final revision = _state.revision;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return MapClusterPicker(
          cluster: feature,
          isCurrent: () =>
              mounted &&
              _state.isCurrentRevision(revision) &&
              _state.scope?.host == Config.host,
          loadPage: (cursor) =>
              _state.loadClusterPage(feature, cursor, revision),
          onExpired: () {
            Navigator.pop(sheetContext);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t('map.clusterPicker.expired'))),
            );
            unawaited(_state.refresh());
          },
          onSelect: (id) {
            Navigator.pop(sheetContext);
            if (_state.isCurrentRevision(revision))
              unawaited(_openRecording(id));
          },
        );
      },
    );
  }

  Future<void> _openRecording(int id) async {
    final detail = await _state.openRecording(id);
    if (!mounted || detail == null) return;
    showCupertinoSheet(
      context: context,
      builder: (context) =>
          RecordingFromMap(recording: detail.recording, user: detail.user),
    );
  }

  Future<void> _openFilters() async {
    var canFilterByUser = false;
    try {
      canFilterByUser = (await _readScope()).verified;
    } catch (_) {
      // Account-independent filters remain usable if storage is unavailable.
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => MapFilterSheet(
        selection: _state.filters,
        canFilterByUser: canFilterByUser,
        onChanged: (selection) {
          final wasAnimating = _camera.isAnimating;
          _camera.cancelAnimation();
          if (wasAnimating) _refreshViewport();
          _state.applyFilters(selection);
        },
      ),
    );
  }

  void _openLegend() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: _state,
      builder: (context, _) => MapLegendSheet(dialectCodes: _state.legendCodes),
    ),
  );

  @override
  void dispose() {
    _state.removeListener(_redraw);
    _state.dispose();
    _camera.dispose();
    _mapSubscription?.cancel();
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.map,
      appBarTitle: null,
      isGuestUser: !_state.canFilterByUser,
      showNotificationBell: false,
      content: LayoutBuilder(
        builder: (context, constraints) {
          if (_size != constraints.biggest || _devicePixelRatio != ratio) {
            _size = constraints.biggest;
            _devicePixelRatio = ratio;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _updateGrid();
              _refreshViewport(immediate: true);
            });
          }
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _position,
                  initialZoom: initialMapZoom,
                  minZoom: 1,
                  maxZoom: 19,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onMapReady: () {
                    _mapReady = true;
                    // Location may have resolved before the first map frame.
                    _moveTo(_position);
                  },
                ),
                children: [
                  MapTileLayer(
                    style: _state.filters.satelliteView
                        ? MapTileStyle.aerial
                        : MapTileStyle.outdoor,
                  ),
                  if (_state.filters.satelliteView)
                    const MapTileLayer(style: MapTileStyle.namesOverlay),
                  PolylineLayer(polylines: _grid),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 20,
                        height: 20,
                        point: _position,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                  MapFeatureLayer(
                    key: ValueKey(_state.scope),
                    features: _state.features,
                    onTap: _selectFeature,
                  ),
                ],
              ),
              if (_state.isLoading)
                const Positioned(
                  top: 140,
                  left: 16,
                  right: 16,
                  child: MapLoadingNotice(),
                ),
              if (_state.refreshFailed && !_state.isLoading)
                Positioned(
                  top: 140,
                  left: 16,
                  right: 16,
                  child: MapRefreshErrorNotice(onRetry: _state.refresh),
                ),
              Positioned(
                top: 80,
                left: 16,
                right: 16,
                child: MapSearchToolbar(
                  search: SearchBarWidget(onLocationSelected: _moveTo),
                  onLegend: _openLegend,
                ),
              ),
              Positioned(
                bottom: 108 + bottomInset,
                right: 20,
                child: MapActionButtons(
                  onFilters: _openFilters,
                  onLocate: _locate,
                ),
              ),
              Positioned(
                bottom: 98 + bottomInset,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 2,
                    horizontal: 4,
                  ),
                  color: Colors.white70,
                  child: Text(
                    t('map.legend.mapyCz'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
