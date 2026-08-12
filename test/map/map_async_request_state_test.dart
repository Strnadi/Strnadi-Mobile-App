import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/map_async_request_state.dart';

void main() {
  group('MapLoadingTracker', () {
    test('one overlapping operation cannot hide another active operation', () {
      final MapLoadingTracker tracker = MapLoadingTracker();

      final int recordingsToken = tracker.begin();
      final int dialectToken = tracker.begin();

      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 2);

      expect(tracker.finish(recordingsToken), isTrue);
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);

      expect(tracker.finish(dialectToken), isTrue);
      expect(tracker.isLoading, isFalse);
      expect(tracker.activeCount, 0);
    });

    test('a replacement retires obsolete work without an idle transition', () {
      final MapLoadingTracker tracker = MapLoadingTracker();
      final int oldToken = tracker.begin();

      final int currentToken = tracker.replace(oldToken);

      expect(currentToken, isNot(oldToken));
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);
      expect(tracker.finish(oldToken), isFalse);
      expect(tracker.isLoading, isTrue);
      expect(tracker.activeCount, 1);

      expect(tracker.finish(currentToken), isTrue);
      expect(tracker.isLoading, isFalse);
    });

    test('finishing an unknown or already finished token is harmless', () {
      final MapLoadingTracker tracker = MapLoadingTracker();
      final int token = tracker.begin();

      expect(tracker.finish(token), isTrue);
      expect(tracker.finish(token), isFalse);
      expect(tracker.finish(999), isFalse);
      expect(tracker.activeCount, 0);
    });
  });

  group('isMapDialectRequestCurrent', () {
    test('accepts a request only when every captured generation is current',
        () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 7,
          activeRecordingsRequestId: 7,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isTrue,
      );
    });

    test('rejects an older dialect API response', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 3,
          activeDialectRequestId: 4,
          recordingsRequestId: 7,
          activeRecordingsRequestId: 7,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test('rejects a response belonging to an older recordings request', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 6,
          activeRecordingsRequestId: 7,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test('rejects a response for stale recording or filter data', () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 7,
          activeRecordingsRequestId: 7,
          dataGeneration: 10,
          activeDataGeneration: 11,
        ),
        isFalse,
      );
    });

    test('accepts a cache refresh captured from the current recordings data',
        () {
      expect(
        isMapDialectRequestCurrent(
          dialectRequestId: 4,
          activeDialectRequestId: 4,
          recordingsRequestId: 99,
          activeRecordingsRequestId: 99,
          dataGeneration: 11,
          activeDataGeneration: 11,
        ),
        isTrue,
      );
    });
  });

  group('MapScreenV2 request-safety wiring', () {
    late String source;

    setUpAll(() {
      source = File('lib/map/mapv2.dart').readAsStringSync();
    });

    test('guards stale recording responses before mutating shared length', () {
      final int methodStart = source.indexOf(
        'Future<int?> _applyRecordingsPayload({',
      );
      final int methodEnd = source.indexOf(
        'Future<void> _loadSavedMapDataThenRefresh()',
        methodStart,
      );
      final String method = source.substring(methodStart, methodEnd);

      final int localCalculation = method.indexOf('final int totalLength');
      final int currentRequestGuard = method.indexOf(
        'if (!_isCurrentRecordingsRequest(requestId))',
        localCalculation,
      );
      final int sharedMutation = method.indexOf('length = totalLength;');

      expect(localCalculation, greaterThanOrEqualTo(0));
      expect(currentRequestGuard, greaterThan(localCalculation));
      expect(sharedMutation, greaterThan(currentRequestGuard));
      expect(method, isNot(contains('length +=')));
    });

    test('keeps saved markers until both current payloads are available', () {
      final int methodStart =
          source.indexOf('Future<void> getRecordings() async');
      final int methodEnd =
          source.indexOf('void _clearRecordingResults()', methodStart);
      final String method = source.substring(methodStart, methodEnd);

      final int recordingsAwait =
          method.indexOf('_recordingsController.fetchRecordings(');
      final int filteredPartsAwait =
          method.indexOf('_filteredPartsApiLoader.fetch(', recordingsAwait);
      final int applyCurrentPayload =
          method.indexOf('_applyRecordingsPayload(', filteredPartsAwait);

      expect(recordingsAwait, greaterThanOrEqualTo(0));
      expect(filteredPartsAwait, greaterThan(recordingsAwait));
      expect(applyCurrentPayload, greaterThan(filteredPartsAwait));
    });

    test('guards API results before updating dialect caches and selection', () {
      final int methodStart =
          source.indexOf('Future<_DialectRefreshResult> _fetchDialects({');
      final int methodEnd =
          source.indexOf('List<String> _dialectsForRecordingId', methodStart);
      final String method = source.substring(methodStart, methodEnd);

      final int apiAwait =
          method.indexOf('await _filteredPartsApiLoader.fetch(');
      final int firstCurrentGuard = method.indexOf(
        'if (!_isCurrentDialectRequest(',
        apiAwait,
      );
      final int cacheMutation =
          method.indexOf('_cachedFilteredParts = frps;', apiAwait);
      final int finalCurrentGuard = method.lastIndexOf(
        'if (!_isCurrentDialectRequest(',
      );
      final int selectionMutation =
          method.indexOf('_dialectsByRecording = byRecording;');

      expect(apiAwait, greaterThanOrEqualTo(0));
      expect(firstCurrentGuard, greaterThan(apiAwait));
      expect(cacheMutation, greaterThan(firstCurrentGuard));
      expect(finalCurrentGuard, greaterThan(cacheMutation));
      expect(selectionMutation, greaterThan(finalCurrentGuard));
      expect(
        method,
        contains('final int dialectRequestId = ++_activeDialectRequestId;'),
      );
    });

    test('uses supersedable loading tokens for both operation types', () {
      expect(
        source,
        contains(
          '_mapLoadingTracker.replace(_recordingsLoadingToken)',
        ),
      );
      expect(
        source,
        contains(
          '_mapLoadingTracker.replace(_dialectRefreshLoadingToken)',
        ),
      );
      expect(source, contains('_syncRecordingsLoading();'));
    });

    test('wires fallback visibility into the final map marker policy', () {
      final int dialectMethodStart = source.indexOf(
        'Future<_DialectRefreshResult> _fetchDialects({',
      );
      final int dialectMethodEnd = source.indexOf(
        'List<String> _dialectsForRecordingId',
        dialectMethodStart,
      );
      final String dialectMethod =
          source.substring(dialectMethodStart, dialectMethodEnd);
      final int visibilityMethodStart =
          source.indexOf('bool _shouldShowRecordingOnMap(');
      final int visibilityMethodEnd = source.indexOf(
        'Future<void> _rebuildMapMarkers()',
        visibilityMethodStart,
      );
      final String visibilityMethod =
          source.substring(visibilityMethodStart, visibilityMethodEnd);

      expect(
        dialectMethod,
        contains(
          'final bool isVisibleInSelectedMode = '
          'shouldRenderDialectMarker(',
        ),
      );
      expect(
        dialectMethod,
        contains(
          'isVisibleInSelectedMode: isVisibleInSelectedMode,',
        ),
      );
      expect(
        dialectMethod,
        contains('hasSubstantiveConfirmedDialect:'),
      );
      expect(
        dialectMethod,
        contains('hasAuthoritativeNoDialect:'),
      );
      expect(
        dialectMethod,
        contains(
          'if (summary.hasAuthoritativeNoDialect) {\n'
          '          hiddenRecordingIds.add(beId);',
        ),
      );
      expect(
        dialectMethod,
        contains('List<String> out = dialectsForMapMarker(summary);'),
      );
      expect(visibilityMethod, contains('shouldShowMapRecording('));
      expect(
        visibilityMethod,
        contains(
          'isVisibleInSelectedMode: entry?.isVisibleInSelectedMode,',
        ),
      );
      expect(
        visibilityMethod,
        isNot(contains('return entry.hasAnySelectedDialect;')),
      );
    });

    test('programmatic map moves refresh bounds before rebuilding markers', () {
      final int moveMethodStart =
          source.indexOf('void _moveMapToLocation(LatLng location)');
      final int moveMethodEnd = source.indexOf(
        'Future<void> _rebuildMapMarkers()',
        moveMethodStart,
      );
      final String moveMethod =
          source.substring(moveMethodStart, moveMethodEnd);

      final int cameraMove =
          moveMethod.indexOf('_mapController.move(location, _currentZoom);');
      final int centerUpdate =
          moveMethod.indexOf('_currentCenter = _mapController.camera.center;');
      final int zoomUpdate =
          moveMethod.indexOf('_currentZoom = _mapController.camera.zoom;');
      final int markerRebuild =
          moveMethod.indexOf('unawaited(_rebuildMapMarkers());');

      expect(moveMethodStart, greaterThanOrEqualTo(0));
      expect(cameraMove, greaterThanOrEqualTo(0));
      expect(centerUpdate, greaterThan(cameraMove));
      expect(zoomUpdate, greaterThan(centerUpdate));
      expect(markerRebuild, greaterThan(zoomUpdate));
      expect(
        source,
        contains(
          'onLocationSelected: (LatLng location) {\n'
          '                          _moveMapToLocation(location);',
        ),
      );
      expect(
        source,
        contains('_moveMapToLocation(_currentPosition);'),
      );
    });

    test('initial and reset recenter paths have one synchronized owner', () {
      expect(
        source,
        contains(
          '_currentPosition = lastKnownPosition;\n'
          '      _currentCenter = lastKnownPosition;',
        ),
      );

      final int locationMethodStart =
          source.indexOf('Future<void> _getCurrentLocation() async');
      final int locationMethodEnd =
          source.indexOf('@override\n  void initState()', locationMethodStart);
      final String locationMethod =
          source.substring(locationMethodStart, locationMethodEnd);
      expect(
        '_moveMapToLocation(_currentPosition);'.allMatches(locationMethod),
        hasLength(1),
      );

      final int resetStart = source.indexOf("heroTag: 'reset'");
      final int resetEnd =
          source.indexOf('backgroundColor: Colors.white', resetStart);
      final String resetButton = source.substring(resetStart, resetEnd);
      expect(resetButton, contains('await _getCurrentLocation();'));
      expect(resetButton, isNot(contains('_moveMapToLocation(')));
    });
  });
}
