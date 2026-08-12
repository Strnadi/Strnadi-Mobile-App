import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/recordings_controller.dart';
import 'package:strnadi/api/dio_client.dart';

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
