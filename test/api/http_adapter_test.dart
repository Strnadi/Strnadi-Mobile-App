import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/http_adapter.dart' as adapter_http;

void main() {
  late dio.Dio client;
  late dio.HttpClientAdapter originalAdapter;
  late _QueuedHttpAdapter adapter;

  setUp(() {
    client = ApiDioClient.instance;
    originalAdapter = client.httpClientAdapter;
    adapter = _QueuedHttpAdapter();
    client.httpClientAdapter = adapter;
  });

  tearDown(() {
    client.httpClientAdapter = originalAdapter;
    adapter.verifyExhausted();
  });

  test('GET converts Dio bytes, headers, and request metadata to http',
      () async {
    adapter.enqueue(
      206,
      body: utf8.encode('partial response'),
      headers: <String, List<String>>{
        'content-type': <String>['text/plain; charset=utf-8'],
        'x-test': <String>['one', 'two'],
      },
      statusMessage: 'Partial Content',
    );
    final Uri uri = Uri.parse('https://adapter.example.test/items?page=2');

    final http.Response response = await adapter_http.get(
      uri,
      headers: const <String, String>{'x-client': 'test'},
    );

    expect(response.statusCode, 206);
    expect(response.body, 'partial response');
    expect(response.headers['x-test'], 'one,two');
    expect(response.reasonPhrase, 'Partial Content');
    expect(response.request?.method, 'GET');
    expect(response.request?.url, uri);
    expect(response.persistentConnection, isTrue);
    expect(adapter.requests.single.headers['x-client'], 'test');
    expect(adapter.requests.single.responseType, dio.ResponseType.bytes);
  });

  test('HEAD and bodyless DELETE preserve their methods and empty bodies',
      () async {
    adapter
      ..enqueue(204)
      ..enqueue(204);
    final Uri uri = Uri.parse('https://adapter.example.test/resource/7');

    final http.Response headResponse = await adapter_http.head(uri);
    final http.Response deleteResponse = await adapter_http.delete(uri);

    expect(headResponse.bodyBytes, isEmpty);
    expect(deleteResponse.bodyBytes, isEmpty);
    expect(
      adapter.requests.map((dio.RequestOptions request) => request.method),
      <String>['HEAD', 'DELETE'],
    );
    expect(adapter.requests[0].data, isNull);
    expect(adapter.requests[1].data, isNull);
  });

  test('POST preserves strings and string-keyed maps', () async {
    adapter
      ..enqueue(201)
      ..enqueue(201);
    final Uri uri = Uri.parse('https://adapter.example.test/resource');

    await adapter_http.post(uri, body: 'plain text');
    await adapter_http.post(
      uri,
      body: <String, dynamic>{'name': 'bird', 'count': 2},
    );

    expect(adapter.requests[0].data, 'plain text');
    expect(
      adapter.requests[1].data,
      <String, dynamic>{'name': 'bird', 'count': 2},
    );
  });

  test('PATCH normalizes non-string map keys and generic iterables', () async {
    adapter
      ..enqueue(200)
      ..enqueue(200);
    final Uri uri = Uri.parse('https://adapter.example.test/resource/7');

    await adapter_http.patch(uri, body: <Object, Object>{1: 'one'});
    await adapter_http.patch(uri, body: <String>{'cs', 'en'});

    expect(adapter.requests[0].data, <String, Object>{'1': 'one'});
    expect(adapter.requests[1].data, <String>['cs', 'en']);
  });

  test('PUT preserves byte lists and FormData', () async {
    adapter
      ..enqueue(200)
      ..enqueue(200);
    final Uri uri = Uri.parse('https://adapter.example.test/resource/7');
    final List<int> bytes = <int>[0, 1, 255];
    final dio.FormData formData = dio.FormData.fromMap(
      <String, dynamic>{'name': 'bird'},
    );

    await adapter_http.put(uri, body: bytes);
    await adapter_http.put(uri, body: formData);

    expect(adapter.requests[0].data, same(bytes));
    expect(adapter.requests[1].data, same(formData));
  });

  test('JSON content type serializes other encodable objects', () async {
    adapter.enqueue(200);
    final Uri uri = Uri.parse('https://adapter.example.test/resource');

    await adapter_http.post(
      uri,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: const _JsonBody('nightingale'),
    );

    expect(adapter.requests.single.data, '{"bird":"nightingale"}');
  });

  test('non-JSON objects use the requested text encoding', () async {
    adapter.enqueue(200);
    final Uri uri = Uri.parse('https://adapter.example.test/resource');

    await adapter_http.post(
      uri,
      body: const _TextBody('café'),
      encoding: latin1,
    );

    expect(adapter.requests.single.data, latin1.encode('café'));
  });

  test('Dio transport failures become http ClientException values', () async {
    adapter.enqueueError('mock connection refused');
    final Uri uri = Uri.parse('https://adapter.example.test/resource');

    await expectLater(
      adapter_http.get(uri),
      throwsA(
        isA<http.ClientException>()
            .having(
              (http.ClientException error) => error.message,
              'message',
              contains('mock connection refused'),
            )
            .having(
              (http.ClientException error) => error.uri,
              'uri',
              uri,
            ),
      ),
    );
  });
}

class _JsonBody {
  const _JsonBody(this.bird);

  final String bird;

  Map<String, String> toJson() => <String, String>{'bird': bird};
}

class _TextBody {
  const _TextBody(this.value);

  final String value;

  @override
  String toString() => value;
}

class _QueuedHttpAdapter implements dio.HttpClientAdapter {
  final Queue<_AdapterOutcome> _outcomes = Queue<_AdapterOutcome>();
  final List<dio.RequestOptions> requests = <dio.RequestOptions>[];

  void enqueue(
    int statusCode, {
    List<int> body = const <int>[],
    Map<String, List<String>> headers = const <String, List<String>>{},
    String? statusMessage,
  }) {
    _outcomes.add(
      _AdapterOutcome.response(
        statusCode: statusCode,
        body: body,
        headers: headers,
        statusMessage: statusMessage,
      ),
    );
  }

  void enqueueError(String message) {
    _outcomes.add(_AdapterOutcome.error(message));
  }

  @override
  Future<dio.ResponseBody> fetch(
    dio.RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_outcomes.isEmpty) {
      throw StateError('Unexpected mocked request to ${options.uri}.');
    }
    requests.add(options);
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    final _AdapterOutcome outcome = _outcomes.removeFirst();
    if (outcome.errorMessage != null) {
      throw dio.DioException(
        requestOptions: options,
        type: dio.DioExceptionType.connectionError,
        message: outcome.errorMessage,
      );
    }
    return dio.ResponseBody.fromBytes(
      outcome.body,
      outcome.statusCode!,
      headers: outcome.headers,
      statusMessage: outcome.statusMessage,
    );
  }

  @override
  void close({bool force = false}) {}

  void verifyExhausted() {
    if (_outcomes.isNotEmpty) {
      throw StateError('${_outcomes.length} mocked outcome(s) not consumed.');
    }
  }
}

class _AdapterOutcome {
  const _AdapterOutcome.response({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.statusMessage,
  }) : errorMessage = null;

  const _AdapterOutcome.error(this.errorMessage)
      : statusCode = null,
        body = const <int>[],
        headers = const <String, List<String>>{},
        statusMessage = null;

  final int? statusCode;
  final List<int> body;
  final Map<String, List<String>> headers;
  final String? statusMessage;
  final String? errorMessage;
}
