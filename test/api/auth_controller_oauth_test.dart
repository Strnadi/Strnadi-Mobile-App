import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';

class OAuthAdapter implements HttpClientAdapter {
  int status = 200;
  String body = '{"access_token":"token"}';
  bool fail = false;
  final requests = <RequestOptions>[];
  String? encodedBody;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    if (fail) throw StateError('secret transport error');
    if (stream != null) {
      encodedBody =
          utf8.decode(await stream.fold<List<int>>([], (a, b) => a..addAll(b)));
    }
    return ResponseBody.fromString(body, status);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpClientAdapter original;
  late OAuthAdapter adapter;
  final endpoint = Uri.parse('https://administration.example/connect/token');
  const controller = AuthController();
  setUp(() {
    original = ApiDioClient.authorization.httpClientAdapter;
    adapter = OAuthAdapter();
    ApiDioClient.authorization.httpClientAdapter = adapter;
  });
  tearDown(() => ApiDioClient.authorization.httpClientAdapter = original);

  test(
      'controller sends form data through shared Dio setup without Bearer or redirects',
      () async {
    final response = await controller.postForm(
        endpoint, {'grant_type': 'authorization_code', 'code': 'a+b&c'});
    expect(response['access_token'], 'token');
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.contentType, Headers.formUrlEncodedContentType);
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.followRedirects, isFalse);
    expect(adapter.encodedBody, contains('code=a%2Bb%26c'));
  });
  for (final grant in [
    'authorization_code',
    'refresh_token',
    'urn:ietf:params:oauth:grant-type:token-exchange'
  ]) {
    for (final status in [400, 401, 403, 408, 429, 500, 503, 302]) {
      test('$grant $status is sanitized and never retried', () async {
        adapter.status = status;
        adapter.body = '{"error":"invalid_grant","error_description":"secret"}';
        final kind = ![400, 401, 403].contains(status)
            ? OAuthFailureKind.server
            : grant == 'refresh_token'
                ? OAuthFailureKind.loginRequired
                : grant.contains('token-exchange')
                    ? OAuthFailureKind.exchangeDenied
                    : OAuthFailureKind.denied;
        await expectLater(controller.postForm(endpoint, {'grant_type': grant}),
            throwsA(isA<OAuthFailure>().having((e) => e.kind, 'kind', kind)));
        expect(adapter.requests, hasLength(1));
      });
    }
  }
  test('malformed JSON and network failures produce safe error categories',
      () async {
    adapter.body = 'secret invalid JSON';
    await expectLater(
        controller.postForm(endpoint, {}),
        throwsA(isA<OAuthFailure>()
            .having((e) => e.kind, 'kind', OAuthFailureKind.invalidResponse)));
    adapter.fail = true;
    await expectLater(
        controller.postForm(endpoint, {}),
        throwsA(isA<OAuthFailure>()
            .having((e) => e.kind, 'kind', OAuthFailureKind.network)));
  });
}
