import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/map/map_clusters.dart';
import 'package:strnadi/map/map_feature_filters.dart';
import 'package:latlong2/latlong.dart';

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _SingleResponseAdapter adapter;

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyUsed();
  });

  test('delete returns a mocked 404 to reconciliation policy', () async {
    adapter = _SingleResponseAdapter(404);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();

    final Response<dynamic> response = await controller.deleteRecording(
      101,
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 404);
    _expectPinnedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/recordings/101'),
      method: 'DELETE',
    );
  });

  test('single-record fetch returns a mocked 404 instead of throwing',
      () async {
    adapter = _SingleResponseAdapter(404);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();

    final Response<dynamic> response = await controller.fetchRecordingById(
      202,
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 404);
    _expectPinnedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/recordings/202?parts=true'),
      method: 'GET',
    );
  });

  test('incomplete scan pins auth and host on a mocked 401', () async {
    adapter = _SingleResponseAdapter(401);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();

    final Response<dynamic> response =
        await controller.fetchIncompleteRecordings(
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 401);
    _expectPinnedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/recordings/incomplete'),
      method: 'GET',
    );
  });

  test('metadata update exposes a mocked validation failure', () async {
    adapter = _SingleResponseAdapter(422);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();

    final Response<dynamic> response = await controller.updateRecording(
      303,
      const <String, Object?>{'name': 'updated'},
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 422);
    _expectPinnedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/recordings/303'),
      method: 'PATCH',
    );
  });

  test('parent creation revalidates immediately before mocked POST', () async {
    adapter = _SingleResponseAdapter(201);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();
    int sessionChecks = 0;

    final Response<dynamic> response = await controller.createRecording(
      const <String, Object?>{'name': 'recording'},
      accessToken: 'captured-token',
      idempotencyKey: 'recording:stable-key',
      host: 'api.example.test',
      beforePost: () async {
        sessionChecks++;
      },
    );

    expect(response.statusCode, 201);
    expect(sessionChecks, 1);
    final RequestOptions request = adapter.requests.single;
    expect(request.uri, Uri.parse('https://api.example.test/recordings'));
    expect(request.method, 'POST');
    expect(request.headers['Authorization'], 'Bearer captured-token');
    expect(request.headers['Idempotency-Key'], 'recording:stable-key');
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
  });

  test('map filter options reach the HTTP request unchanged', () async {
    adapter = _SingleResponseAdapter(200);
    dio.httpClientAdapter = adapter;
    await const RecordingsController().fetchMapClusters(
      MapClustersRequest(
        center: LatLng(50, 14),
        zoom: 12,
        viewportWidthPx: 390,
        viewportHeightPx: 844,
        devicePixelRatio: 2,
        dialectMode: 'All',
        ownerScope: 'Others',
        userId: 42,
        clustered: false,
        featureFilters: const MapFeatureFilters(
          mixDialects: false,
          mixSources: false,
          onlyMeaningfulDialects: true,
          hideOthersWithoutMeaningfulDialect: true,
        ),
      ),
      host: 'api.example.test',
    );
    final query = adapter.requests.single.uri.queryParameters;
    expect(query['mixDialects'], 'false');
    expect(query['mixSources'], 'false');
    expect(query['onlyMeaningfulDialects'], 'true');
    expect(query['hideOthersWithoutMeaningfulDialect'], 'true');
    expect(query['ownerScope'], 'Others');
    expect(query['userId'], '42');
    expect(query['clustered'], 'false');
  });

  test('map clusters sends only a mocked viewport request', () async {
    adapter = _SingleResponseAdapter(422);
    dio.httpClientAdapter = adapter;
    const RecordingsController controller = RecordingsController();

    final Response<dynamic> response = await controller.fetchMapClusters(
      MapClustersRequest(
        center: LatLng(50.1, 14.4),
        zoom: 12.5,
        viewportWidthPx: 390,
        viewportHeightPx: 844,
        devicePixelRatio: 3,
        dialectMode: 'AiAdmin',
        ownerScope: 'Mine',
        userId: 12,
      ),
      host: 'api.example.test',
    );

    expect(response.statusCode, 422);
    final RequestOptions request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/recordings/map-clusters');
    expect(request.uri.queryParameters, <String, String>{
      'centerLat': '50.1',
      'centerLng': '14.4',
      'zoom': '12.5',
      'viewportWidthPx': '390',
      'viewportHeightPx': '844',
      'devicePixelRatio': '3.0',
      'dialectMode': 'AiAdmin',
      'ownerScope': 'Mine',
      'clustered': 'true',
      'mixDialects': 'true',
      'mixSources': 'true',
      'onlyMeaningfulDialects': 'false',
      'hideOthersWithoutMeaningfulDialect': 'false',
      'userId': '12',
    });
    expect(request.validateStatus(422), isTrue);
    expect(request.validateStatus(500), isFalse);
  });
  for (final status in [200, 409, 410]) {
    test('cluster detail encodes opaque IDs and cursor and returns $status',
        () async {
      adapter = _SingleResponseAdapter(status);
      dio.httpClientAdapter = adapter;
      final response = await const RecordingsController().fetchMapClusterItems(
          'cluster/a', 'cursor+/?=',
          host: 'api.example.test');
      expect(response.statusCode, status);
      final r = adapter.requests.single;
      expect(r.uri.pathSegments,
          ['recordings', 'map-clusters', 'cluster/a', 'items']);
      expect(r.uri.queryParameters, {'cursor': 'cursor+/?=', 'pageSize': '5'});
      expect(r.followRedirects, false);
      expect(r.maxRedirects, 0);
    });
  }
}

void _expectPinnedRequest(
  RequestOptions request,
  Uri expectedUri, {
  required String method,
}) {
  expect(request.uri, expectedUri);
  expect(request.method, method);
  expect(request.headers['Authorization'], 'Bearer captured-token');
  expect(request.followRedirects, isFalse);
  expect(request.maxRedirects, 0);
  expect(request.validateStatus(399), isTrue);
  expect(request.validateStatus(404), isTrue);
  expect(request.validateStatus(499), isTrue);
  expect(request.validateStatus(500), isFalse);
}

class _SingleResponseAdapter implements HttpClientAdapter {
  _SingleResponseAdapter(this.statusCode);

  final int statusCode;
  final List<RequestOptions> requests = <RequestOptions>[];
  bool _used = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_used) {
      throw StateError('Unexpected second mocked request to ${options.uri}.');
    }
    _used = true;
    requests.add(options);
    return ResponseBody.fromString('', statusCode);
  }

  @override
  void close({bool force = false}) {}

  void verifyUsed() {
    if (!_used) {
      throw StateError('The mocked HTTP response was not consumed.');
    }
  }
}
