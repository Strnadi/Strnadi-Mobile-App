import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'map_feature_fixtures.dart';

void main() {
  test(
    'serializes clustering, ownership and dates without removed parameters',
    () {
      final q = MapClustersRequest(
        center: LatLng(50, 14),
        zoom: 12.5,
        viewportWidthPx: 390.2,
        viewportHeightPx: 843.6,
        devicePixelRatio: 3,
        dialectMode: 'AiAdmin',
        clustered: false,
        ownerScope: 'Mine',
        userId: 42,
        createdFrom: DateTime(2025, 1, 1),
        createdTo: DateTime(2026, 9, 8),
      ).toQueryParameters();
      expect(q['ownerScope'], 'Mine');
      expect(q['userId'], 42);
      expect(q['clustered'], false);
      expect(q['mixDialects'], true);
      expect(q['viewportHeightPx'], 844);
      expect(q['viewportWidthPx'], 390);
      expect(q['createdTo'], '2026-09-08');
      expect(q['createdFrom'], '2025-01-01');
      expect(q.containsKey('verified'), false);
      expect(q.containsKey('contractVersion'), false);
      expect(q.containsKey('maxItemsPerCluster'), false);
    },
  );
  test(
    'parses both kinds and preserves weighted percentages and fallback GPS ids',
    () {
      final r = MapClustersResponse.fromResponseData(
        jsonEncode(responseJson()),
      );
      expect(r.visibleRecordingCount, 7);
      expect(r.features.first.recording!.representativePartId, isNull);
      expect(r.features.first.recording!.locationPartId, 120);
      final c = r.features.last;
      expect(c.count, 6);
      expect(c.items.length, 5);
      expect(c.hasMoreItems, true);
      expect(c.dialects.first.contributionCount, 4);
      expect(c.dialects.first.percentage, 50);
      expect(c.dialects.first.color, 0xffff0000);
      expect(c.dialects.last.code, 'unknown');
      expect(c.bounds!.coincident, true);
      expect(
        MapClusterItemsPage.fromResponseData(
          pageJson(),
        ).items.single.recordingId,
        6,
      );
    },
  );
  test('supports empty and unclustered maps and antimeridian bounds', () {
    final j = responseJson()
      ..['features'] = []
      ..['visibleRecordingCount'] = 0
      ..['clustered'] = false;
    expect(MapClustersResponse.fromResponseData(j).features, isEmpty);
    final b = MapBounds.fromJson({
      'north': 10,
      'south': -10,
      'west': 179,
      'east': -179,
    });
    expect(b.longitudeSpan, 2);
  });
  test(
    'rejects old schema and malformed features instead of silently losing data',
    () {
      expect(
        () => MapClustersResponse.fromResponseData({'clusters': []}),
        throwsFormatException,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['kind'] = 'other',
        (j) => j['latitude'] = double.nan,
        (j) => j['dialects'] = [dialectJson(color: 'bad')],
        (j) => j['dialects'] = [dialectJson(percentage: 80)],
        (j) => j['nextItemsCursor'] = null,
        (j) => j['items'] = [itemJson(1)],
      ]) {
        final j = clusterJson();
        mutate(j);
        expect(() => MapCluster.fromJson(j), throwsFormatException);
      }
    },
  );
  test(
    'summarizes structured API errors without logging their full payload',
    () {
      final MapClustersApiError error = MapClustersApiError.fromResponse(
        statusCode: 422,
        payload: <String, dynamic>{
          'error': <String, dynamic>{
            'code': 'invalid_viewport',
            'reason': 'bounds_are_inverted',
            'message': 'north must be greater than south',
          },
          'requestId': 'req-42',
          'unrelatedPayload': List<String>.filled(300, 'do-not-log'),
        },
      );

      expect(
        error.toLogMessage(),
        'map-clusters request failed (status=422, error=invalid_viewport, '
        'reason=bounds_are_inverted, '
        'message=north must be greater than south, traceId=req-42)',
      );
      expect(error.toLogMessage(), isNot(contains('unrelatedPayload')));
      expect(error.toLogMessage(), isNot(contains('do-not-log')));
    },
  );

  test('handles plain and malformed error payloads safely', () {
    expect(
      MapClustersApiError.fromResponse(
        statusCode: 500,
        payload: '{not json}',
      ).toLogMessage(),
      'map-clusters request failed (status=500)',
    );
    expect(
      MapClustersApiError.fromResponse(
        statusCode: 400,
        payload: '{"error":"invalid_viewport","reason":"zoom_range"}',
      ).toLogMessage(),
      'map-clusters request failed '
      '(status=400, error=invalid_viewport, reason=zoom_range)',
    );
  });
}
