import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/services/map_api_service.dart';
import 'package:strnadi/map/filters/map_filter_defaults.dart';
import 'package:strnadi/map/filters/map_filter_selection.dart';
import 'package:strnadi/map/state/map_state_controller.dart';

import '../map_feature_fixtures.dart';

class _MapApi implements MapDataSource {
  final requests = <({MapClustersRequest request, String host})>[];
  final responses = <Completer<MapClustersResponse>>[];
  late final page = Completer<MapClusterItemsPage>();
  late final detail = Completer<MapRecordingDetail>();
  late final legend = Completer<List<String>>();
  int detailRequests = 0;
  int pageRequests = 0;

  @override
  Future<MapClustersResponse> fetchFeatures(
    MapClustersRequest request, {
    required String host,
  }) {
    requests.add((request: request, host: host));
    final result = Completer<MapClustersResponse>();
    responses.add(result);
    return result.future;
  }

  @override
  Future<MapClusterItemsPage> fetchClusterItems(
    String id,
    String cursor, {
    required String host,
  }) {
    pageRequests++;
    return page.future;
  }

  @override
  Future<MapRecordingDetail> fetchRecording(int id, {required String host}) {
    detailRequests++;
    return detail.future;
  }

  @override
  Future<List<String>> fetchLegend({required String host}) => legend.future;

  void succeed(int index) => responses[index].complete(
    MapClustersResponse.fromResponseData(responseJson()),
  );
}

const _viewport = MapViewport(
  center: LatLng(50, 14),
  zoom: 13,
  size: Size(390, 800),
  devicePixelRatio: 3,
);
const _guest = MapSessionScope(host: 'api.example');
const _signedIn = MapSessionScope(
  host: 'api.example',
  sessionId: 'session-a',
  userId: '42',
  verified: true,
);

void main() {
  late _MapApi api;
  late MapSessionScope scope;
  late MapStateController controller;
  late bool disposed;
  late bool scopeUnavailable;

  setUp(() {
    api = _MapApi();
    scope = _signedIn;
    disposed = false;
    scopeUnavailable = false;
    controller = MapStateController(
      api: api,
      readScope: () async {
        if (scopeUnavailable) throw StateError('Storage unavailable');
        return scope;
      },
      currentHost: () => scope.host,
      logger: Logger(level: Level.off),
    );
  });
  tearDown(() {
    if (!disposed) controller.dispose();
  });

  testWidgets(
    'initial request uses shared defaults and exact viewport contract',
    (tester) async {
      controller.updateViewport(_viewport, immediate: true);
      await tester.pump();
      final request = api.requests.single.request;
      expect(controller.filters, mapFilterDefaults);
      expect(
        request.toQueryParameters(),
        containsPair('dialectMode', 'AiAdmin'),
      );
      expect(request.clustered, isFalse);
      expect(request.ownerScope, 'All');
      expect(request.userId, 42);
      expect(request.createdFrom, DateTime(2025, 1, 1));
      expect(request.createdTo, isNull);
      expect(request.viewportWidthPx, 390);
      expect(request.viewportHeightPx, 800);
      expect(request.devicePixelRatio, 3);
      expect(api.requests.single.host, scope.host);
      expect(controller.isLoading, isTrue);
      api.succeed(0);
      await tester.pump();
      expect(controller.features, hasLength(2));
      expect(controller.isLoading, isFalse);
    },
  );

  testWidgets('guest defaults do not require an owner identity', (
    tester,
  ) async {
    scope = _guest;
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    final request = api.requests.single.request;
    expect(request.userId, isNull);
    expect(request.featureFilters.onlyMeaningfulDialects, isTrue);
    expect(request.featureFilters.hideOthersWithoutMeaningfulDialect, isFalse);
    expect(controller.canFilterByUser, isFalse);
    api.succeed(0);
    await tester.pump();
  });

  testWidgets('invalid owner identity fails closed and supports retry', (
    tester,
  ) async {
    scope = const MapSessionScope(
      host: 'api.example',
      sessionId: 'bad',
      userId: '',
      verified: true,
    );
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    expect(api.requests, isEmpty);
    expect(controller.features, isEmpty);
    expect(controller.refreshFailed, isTrue);
    expect(controller.isLoading, isFalse);
    scope = _signedIn;
    final retry = controller.refresh();
    await tester.pump();
    api.succeed(0);
    await retry;
    expect(controller.refreshFailed, isFalse);
  });

  testWidgets('camera movement debounces to the final viewport', (
    tester,
  ) async {
    controller.updateViewport(_viewport);
    await tester.pump(const Duration(milliseconds: 200));
    expect(api.requests, isEmpty);
    controller.updateViewport(
      const MapViewport(
        center: LatLng(49, 15),
        zoom: 12,
        size: Size(800, 390),
        devicePixelRatio: 2,
      ),
    );
    await tester.pump(const Duration(milliseconds: 249));
    expect(api.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.requests, hasLength(1));
    expect(api.requests.single.request.center, const LatLng(49, 15));
    expect(api.requests.single.request.viewportWidthPx, 800);
    api.succeed(0);
    await tester.pump();
  });

  testWidgets('tile style changes do not request recording data; reset does', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    api.succeed(0);
    await tester.pump();
    controller.applyFilters(controller.filters.copyWith(satelliteView: true));
    await tester.pump();
    expect(api.requests, hasLength(1));
    expect(controller.features, hasLength(2));
    controller.applyFilters(
      controller.filters.copyWith(
        clustered: true,
        recordingAge: RecordingAgeFilter.older,
        dialectVisibility: DialectVisibilityMode.adminOnly,
        authorFilter: 'me',
      ),
    );
    expect(controller.features, isEmpty);
    await tester.pump();
    final request = api.requests.last.request;
    expect(request.createdFrom, DateTime(2011, 1, 1));
    expect(request.createdTo, DateTime(2016, 12, 31));
    expect(request.dialectMode, 'AdminOnly');
    expect(request.ownerScope, 'Mine');
    controller.resetFilters();
    await tester.pump();
    expect(controller.filters, mapFilterDefaults);
    expect(api.requests.last.request.clustered, isFalse);
    api.succeed(1);
    await tester.pump();
    expect(controller.features, isEmpty);
    expect(controller.isLoading, isTrue);
    api.succeed(2);
    await tester.pump();
    expect(controller.features, hasLength(2));
  });

  testWidgets('late successes and failures cannot replace the newest request', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    final newest = controller.refresh();
    await tester.pump();
    api.responses.first.completeError(StateError('obsolete failure'));
    await tester.pump();
    expect(controller.refreshFailed, isFalse);
    expect(controller.isLoading, isTrue);
    api.succeed(1);
    await newest;
    expect(controller.features, hasLength(2));
    expect(controller.isLoading, isFalse);
    final failed = controller.refresh();
    await tester.pump();
    api.responses.last.completeError(StateError('current failure'));
    await failed;
    expect(controller.refreshFailed, isTrue);
    expect(controller.features, hasLength(2));
  });

  for (final changed in [
    const MapSessionScope(
      host: 'other.example',
      sessionId: 'session-a',
      userId: '42',
      verified: true,
    ),
    const MapSessionScope(
      host: 'api.example',
      sessionId: 'session-b',
      userId: '99',
      verified: true,
    ),
    _guest,
  ]) {
    testWidgets(
      'rejects pending data after scope change to ${changed.host}/${changed.sessionId}',
      (tester) async {
        controller.updateViewport(_viewport, immediate: true);
        await tester.pump();
        scope = changed;
        api.succeed(0);
        await tester.pump();
        expect(controller.features, isEmpty);
        expect(controller.refreshFailed, isFalse);
        expect(await controller.isScopeCurrent(), isFalse);
        final retry = controller.refresh();
        await tester.pump();
        api.succeed(1);
        await retry;
        expect(controller.scope, changed);
      },
    );
  }

  testWidgets(
    'a refresh clears previously rendered data belonging to another account',
    (tester) async {
      controller.updateViewport(_viewport, immediate: true);
      await tester.pump();
      api.succeed(0);
      await tester.pump();
      scope = _guest;
      final refresh = controller.refresh();
      await tester.pump();
      expect(controller.features, isEmpty);
      api.succeed(1);
      await refresh;
    },
  );

  testWidgets('cluster pagination expires when filters change while loading', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    api.succeed(0);
    await tester.pump();
    final future = controller.loadClusterPage(
      controller.features.last,
      'cursor',
      controller.revision,
    );
    Object? pageError;
    unawaited(
      future.then<void>(
        (_) => fail('An expired page must not be returned'),
        onError: (Object error) {
          pageError = error;
        },
      ),
    );
    await tester.pump();
    expect(api.pageRequests, 1);
    controller.applyFilters(controller.filters.copyWith(clustered: true));
    api.page.complete(MapClusterItemsPage.fromResponseData(pageJson()));
    await tester.pump();
    expect(pageError, isA<ClusterSnapshotExpired>());
    api.succeed(1);
    await tester.pump();
  });

  testWidgets('recording selection cannot fetch after the map scope changes', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    api.succeed(0);
    await tester.pump();
    scope = _guest;
    expect(await controller.openRecording(20), isNull);
    expect(api.detailRequests, 0);
  });

  testWidgets('legend from another environment is discarded', (tester) async {
    final initialCodes = controller.legendCodes;
    final loading = controller.refreshLegend();
    scope = const MapSessionScope(host: 'other.example');
    api.legend.complete(['BC']);
    await loading;
    expect(controller.legendCodes, initialCodes);
  });

  testWidgets('scope storage failure becomes a recoverable map error', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    scopeUnavailable = true;
    api.succeed(0);
    await tester.pump();
    expect(controller.features, isEmpty);
    expect(controller.refreshFailed, isTrue);
    expect(controller.isLoading, isFalse);
    scopeUnavailable = false;
    final retry = controller.refresh();
    await tester.pump();
    api.succeed(1);
    await retry;
    expect(controller.refreshFailed, isFalse);
    expect(controller.features, hasLength(2));
  });

  testWidgets('dispose cancels debounce and ignores late callbacks', (
    tester,
  ) async {
    controller.updateViewport(_viewport, immediate: true);
    await tester.pump();
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.updateViewport(_viewport);
    controller.dispose();
    disposed = true;
    api.succeed(0);
    await tester.pump(const Duration(seconds: 1));
    expect(api.requests, hasLength(1));
    expect(notifications, 0);
  });
}
