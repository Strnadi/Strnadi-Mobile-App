import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
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

  test('connected-account checks pin mocked auth, owner, host and redirects',
      () async {
    adapter.enqueue(404);
    adapter.enqueue(200);
    const AuthController controller = AuthController();

    final Response<dynamic> google = await controller.hasGoogleId(
      42,
      accessToken: 'captured-token',
      host: 'dev.example.test',
    );
    final Response<dynamic> apple = await controller.hasAppleId(
      42,
      accessToken: 'captured-token',
      host: 'dev.example.test',
    );

    expect(google.statusCode, 404);
    expect(apple.statusCode, 200);
    _expectAuthenticatedRequest(
      adapter.requests[0],
      Uri.parse(
        'https://dev.example.test/auth/has-google-id?userId=42',
      ),
      method: 'GET',
    );
    _expectAuthenticatedRequest(
      adapter.requests[1],
      Uri.parse(
        'https://dev.example.test/auth/has-apple-id?userId=42',
      ),
      method: 'GET',
    );
  });

  test('profile reads expose mocked auth failures without following redirects',
      () async {
    adapter.enqueue(401);
    const UserController controller = UserController();

    final Response<dynamic> response = await controller.getUserById(
      7,
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 401);
    _expectAuthenticatedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/users/7'),
      method: 'GET',
    );
  });

  test('profile updates return mocked validation failures to the UI', () async {
    adapter.enqueue(422);
    const UserController controller = UserController();

    final Response<dynamic> response = await controller.updateUserById(
      7,
      const <String, dynamic>{'firstName': 'Ada'},
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 422);
    _expectAuthenticatedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/users/7'),
      method: 'PATCH',
    );
  });

  test('profile photo upload is authenticated against the captured host',
      () async {
    adapter.enqueue(200);
    const UserController controller = UserController();

    final Response<dynamic> response = await controller.uploadProfilePhoto(
      userId: 7,
      photoBase64: 'mock-photo',
      format: 'png',
      accessToken: 'captured-token',
      host: 'api.example.test',
    );

    expect(response.statusCode, 200);
    _expectAuthenticatedRequest(
      adapter.requests.single,
      Uri.parse('https://api.example.test/users/7/upload-profile-photo'),
      method: 'POST',
    );
  });
}

void _expectAuthenticatedRequest(
  RequestOptions request,
  Uri expectedUri, {
  required String method,
}) {
  expect(request.uri, expectedUri);
  expect(request.method, method);
  expect(request.headers['Authorization'], 'Bearer captured-token');
  expect(request.followRedirects, isFalse);
  expect(request.maxRedirects, 0);
  expect(request.extra['authRequired'], isTrue);
  expect(request.validateStatus(399), isTrue);
  expect(request.validateStatus(404), isTrue);
  expect(request.validateStatus(499), isTrue);
  expect(request.validateStatus(500), isFalse);
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
