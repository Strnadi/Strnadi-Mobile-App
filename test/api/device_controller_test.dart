import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/device_controller.dart';
import 'package:strnadi/api/dio_client.dart';

void main() {
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _QueuedResponseAdapter adapter;

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
    adapter = _QueuedResponseAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyComplete();
  });

  test('registration uses captured host and JWT with mocked response',
      () async {
    adapter.enqueue(201);
    const DeviceController controller = DeviceController();
    const Map<String, dynamic> body = <String, dynamic>{
      'fcmToken': 'fcm-new',
      'devicePlatform': 'test-platform',
      'deviceModel': 'test-model',
      'userId': 42,
    };

    final Response<dynamic> response = await controller.addDevice(
      body,
      host: 'old-origin.example.test',
      accessToken: 'captured-jwt',
    );

    expect(response.statusCode, 201);
    _expectBoundRequest(
      adapter.requests.single,
      Uri.parse('https://old-origin.example.test/devices/add'),
      method: 'POST',
      data: body,
    );
  });

  test('refresh update pins both tokens and refuses mocked redirects',
      () async {
    adapter.enqueue(302);
    const DeviceController controller = DeviceController();
    const Map<String, dynamic> body = <String, dynamic>{
      'oldFCMToken': 'fcm-old',
      'newFCMToken': 'fcm-new',
    };

    final Response<dynamic> response = await controller.updateDevice(
      body,
      host: 'captured.example.test',
      accessToken: 'captured-jwt',
    );

    expect(response.statusCode, 302);
    _expectBoundRequest(
      adapter.requests.single,
      Uri.parse('https://captured.example.test/devices/update'),
      method: 'PATCH',
      data: body,
    );
  });

  test('logout deletes against the binding original mocked origin', () async {
    adapter.enqueue(404);
    const DeviceController controller = DeviceController();

    final Response<dynamic> response = await controller.deleteDeviceToken(
      'fcm-old',
      host: 'original.example.test',
      accessToken: 'captured-jwt',
    );

    expect(response.statusCode, 404);
    _expectBoundRequest(
      adapter.requests.single,
      Uri.parse('https://original.example.test/devices/delete/fcm-old'),
      method: 'DELETE',
      data: null,
    );
  });
}

void _expectBoundRequest(
  RequestOptions request,
  Uri expectedUri, {
  required String method,
  required Object? data,
}) {
  expect(request.uri, expectedUri);
  expect(request.method, method);
  expect(request.data, data);
  expect(request.headers['Authorization'], 'Bearer captured-jwt');
  expect(request.followRedirects, isFalse);
  expect(request.maxRedirects, 0);
  expect(request.extra['authRequired'], isFalse);
}

class _QueuedResponseAdapter implements HttpClientAdapter {
  final List<int> _statuses = <int>[];
  final List<RequestOptions> requests = <RequestOptions>[];

  void enqueue(int statusCode) => _statuses.add(statusCode);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requests.length >= _statuses.length) {
      throw StateError('Unexpected mocked request to ${options.uri}.');
    }
    requests.add(options);
    return ResponseBody.fromString('', _statuses[requests.length - 1]);
  }

  @override
  void close({bool force = false}) {}

  void verifyComplete() {
    expect(requests, hasLength(_statuses.length));
  }
}
