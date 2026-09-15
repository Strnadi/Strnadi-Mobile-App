import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/dialects_controller.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/services/map_api_service.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_feature_fixtures.dart';

class _Recordings extends RecordingsController {
  int status = 200;
  dynamic payload;
  String? receivedHost;
  Response<dynamic> response() => Response<dynamic>(
    requestOptions: RequestOptions(path: '/recordings/map-clusters'),
    statusCode: status,
    data: payload,
  );

  @override
  Future<Response<dynamic>> fetchMapClusters(
    MapClustersRequest request, {
    String? host,
  }) async {
    receivedHost = host;
    return response();
  }

  @override
  Future<Response<dynamic>> fetchMapClusterItems(
    String clusterId,
    String cursor, {
    required String host,
    int pageSize = 5,
  }) async {
    receivedHost = host;
    return response();
  }
}

class _Dialects extends DialectsController {
  dynamic payload;
  @override
  Future<Response<dynamic>> fetchDialectPalette({String? host}) async =>
      Response(
        requestOptions: RequestOptions(path: '/recordings/dialects'),
        statusCode: 200,
        data: payload,
      );
}

const _request = MapClustersRequest(
  center: LatLng(50, 14),
  zoom: 13,
  viewportWidthPx: 390,
  viewportHeightPx: 800,
  devicePixelRatio: 3,
  dialectMode: 'AiAdmin',
);

void main() {
  test('viewport JSON is decoded and validated at the API boundary', () async {
    final recordings = _Recordings()..payload = responseJson();
    final api = MapApiService(recordings: recordings);
    final response = await api.fetchFeatures(_request, host: 'preprod.example');
    expect(recordings.receivedHost, 'preprod.example');
    expect(response.features, hasLength(2));
    recordings.payload = {'features': 'invalid'};
    await expectLater(
      api.fetchFeatures(_request, host: 'preprod.example'),
      throwsFormatException,
    );
  });

  test(
    'failure exposes only bounded structured backend error fields',
    () async {
      final recordings = _Recordings()
        ..status = 422
        ..payload = {
          'error': 'invalid_viewport',
          'message': 'Invalid\nviewport',
          'token': 'private-test-value',
          'recordings': [
            {'note': 'private-note'},
          ],
        };
      final api = MapApiService(recordings: recordings);
      try {
        await api.fetchFeatures(_request, host: 'api.example');
        fail('Request should fail');
      } on MapApiException catch (error) {
        final message = error.toString();
        expect(message, contains('422'));
        expect(message, contains('invalid_viewport'));
        expect(message, isNot(contains('\n')));
        expect(message, isNot(contains('private-test-value')));
        expect(message, isNot(contains('private-note')));
      }
    },
  );

  for (final status in [409, 410]) {
    test('cluster HTTP $status becomes snapshot expiry', () async {
      final recordings = _Recordings()..status = status;
      await expectLater(
        MapApiService(
          recordings: recordings,
        ).fetchClusterItems('cluster/a', 'opaque', host: 'api.example'),
        throwsA(isA<ClusterSnapshotExpired>()),
      );
    });
  }

  test('cluster continuation is parsed into typed data', () async {
    final recordings = _Recordings()..payload = pageJson();
    final page = await MapApiService(
      recordings: recordings,
    ).fetchClusterItems('cluster/a', 'opaque', host: 'api.example');
    expect(page.items.single.recordingId, 6);
    expect(page.hasMoreItems, isFalse);
  });

  test(
    'legend preserves backend hint ordering and canonical code names',
    () async {
      final dialects = _Dialects()
        ..payload = [
          {'dialectCode': 'BE', 'hintOrder': 2, 'isDialect': true},
          {'dialectCode': 'BC', 'hintOrder': 1, 'isDialect': true},
          {'dialectCode': 'Unknown', 'hintOrder': 0, 'isDialect': false},
        ];
      final codes = await MapApiService(
        dialects: dialects,
      ).fetchLegend(host: 'api.example');
      expect(codes, ['BE', 'BC']);
    },
  );
}
