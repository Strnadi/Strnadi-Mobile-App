import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/post_json_with_redirect.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  late Dio dio;
  late _QueuedHttpAdapter adapter;

  setUp(() {
    dio = Dio();
    adapter = _QueuedHttpAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    adapter.verifyExhausted();
    dio.close(force: true);
  });

  test('replays one same-origin redirect with identical POST body and headers',
      () async {
    adapter
      ..enqueue(
        307,
        headers: <String, List<String>>{
          'location': <String>['/canonical/recordings'],
        },
      )
      ..enqueue(201, body: '900');
    final Map<String, Object?> body = <String, Object?>{
      'name': 'test',
      'expectedPartsCount': 2,
    };
    final Map<String, Object?> headers = <String, Object?>{
      'Authorization': 'Bearer captured-token',
      'Idempotency-Key': 'stable-key',
    };

    final Response<dynamic> response = await postJsonWithSameOriginRedirect(
      dio: dio,
      uri: Uri.parse('https://api.example.test/recordings'),
      body: body,
      headers: headers,
      beforePost: () async {},
    );

    expect(response.statusCode, 201);
    expect(adapter.requests, hasLength(2));
    expect(
      adapter.requests.map((RequestOptions request) => request.method),
      everyElement('POST'),
    );
    expect(adapter.requests.first.data, body);
    expect(adapter.requests.last.data, body);
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer captured-token',
    );
    expect(adapter.requests.last.headers['Idempotency-Key'], 'stable-key');
    expect(
      adapter.requests.last.uri,
      Uri.parse('https://api.example.test/canonical/recordings'),
    );
    expect(
        adapter.requests,
        everyElement(
          isA<RequestOptions>()
              .having((request) => request.followRedirects, 'followRedirects',
                  false)
              .having((request) => request.maxRedirects, 'maxRedirects', 0),
        ));
  });

  for (final String location in <String>[
    'https://evil.example.test/recordings',
    'http://api.example.test/recordings',
    'https://api.example.test:444/recordings',
  ]) {
    test('rejects unsafe redirect $location', () async {
      adapter.enqueue(
        307,
        headers: <String, List<String>>{
          'location': <String>[location],
        },
      );

      await expectLater(
        postJsonWithSameOriginRedirect(
          dio: dio,
          uri: Uri.parse('https://api.example.test/recordings'),
          body: <String, Object?>{'name': 'test'},
          headers: <String, Object?>{'Idempotency-Key': 'stable-key'},
          beforePost: () async {},
        ),
        throwsA(
          isA<UploadException>().having(
            (UploadException error) => error.statusCode,
            'statusCode',
            502,
          ),
        ),
      );

      expect(adapter.requests, hasLength(1));
    });
  }

  test('rejects redirect without location', () async {
    adapter.enqueue(308);

    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('https://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: const <String, Object?>{},
        beforePost: () async {},
      ),
      throwsA(isA<UploadException>()),
    );
  });

  test('rejects an insecure initial origin before sending credentials',
      () async {
    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('http://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: <String, Object?>{
          'Authorization': 'Bearer captured-token',
        },
        beforePost: () async {},
      ),
      throwsA(
        isA<UploadException>().having(
          (UploadException error) => error.statusCode,
          'statusCode',
          502,
        ),
      ),
    );

    expect(adapter.requests, isEmpty);
  });

  test('normalizes a malformed redirect location to an upload failure',
      () async {
    adapter.enqueue(
      307,
      headers: <String, List<String>>{
        'location': <String>['https://[::1'],
      },
    );

    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('https://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: const <String, Object?>{},
        beforePost: () async {},
      ),
      throwsA(
        isA<UploadException>().having(
          (UploadException error) => error.statusCode,
          'statusCode',
          502,
        ),
      ),
    );

    expect(adapter.requests, hasLength(1));
  });

  test('rejects a second redirect instead of looping', () async {
    adapter
      ..enqueue(
        307,
        headers: <String, List<String>>{
          'location': <String>['/canonical-one'],
        },
      )
      ..enqueue(
        308,
        headers: <String, List<String>>{
          'location': <String>['/canonical-two'],
        },
      );

    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('https://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: const <String, Object?>{},
        beforePost: () async {},
      ),
      throwsA(isA<UploadException>()),
    );

    expect(adapter.requests, hasLength(2));
  });

  test('revalidates immediately before a redirected POST replay', () async {
    adapter.enqueue(
      307,
      headers: <String, List<String>>{
        'location': <String>['/canonical/recordings'],
      },
    );
    int sessionChecks = 0;
    final StateError sessionChanged = StateError('session changed');

    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('https://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: <String, Object?>{
          'Authorization': 'Bearer captured-token',
          'Idempotency-Key': 'stable-key',
        },
        beforePost: () async {
          sessionChecks++;
          if (sessionChecks == 2) throw sessionChanged;
        },
      ),
      throwsA(same(sessionChanged)),
    );

    expect(sessionChecks, 2);
    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.uri,
      Uri.parse('https://api.example.test/recordings'),
    );
  });

  test('callback failure before the first POST sends no request', () async {
    final StateError sessionUnavailable =
        StateError('session provider unavailable');

    await expectLater(
      postJsonWithSameOriginRedirect(
        dio: dio,
        uri: Uri.parse('https://api.example.test/recordings'),
        body: <String, Object?>{'name': 'test'},
        headers: <String, Object?>{
          'Authorization': 'Bearer captured-token',
        },
        beforePost: () async => throw sessionUnavailable,
      ),
      throwsA(same(sessionUnavailable)),
    );

    expect(adapter.requests, isEmpty);
  });

  for (final int statusCode in <int>[300, 301, 302, 303, 304]) {
    test('rejects non-preserving $statusCode redirect without replay',
        () async {
      adapter.enqueue(
        statusCode,
        headers: <String, List<String>>{
          'location': <String>['/canonical/recordings'],
        },
      );
      int sessionChecks = 0;

      await expectLater(
        postJsonWithSameOriginRedirect(
          dio: dio,
          uri: Uri.parse('https://api.example.test/recordings'),
          body: <String, Object?>{'name': 'test'},
          headers: const <String, Object?>{},
          beforePost: () async {
            sessionChecks++;
          },
        ),
        throwsA(
          isA<UploadException>().having(
            (UploadException error) => error.statusCode,
            'statusCode',
            502,
          ),
        ),
      );

      expect(sessionChecks, 1);
      expect(adapter.requests, hasLength(1));
    });

    test('rebuilt POST rejects non-preserving $statusCode without replay',
        () async {
      int posts = 0;

      await expectLater(
        postRebuiltWithSameOriginRedirect(
          operation: 'Multipart upload',
          post: (String? overrideUrl) async {
            posts++;
            return Response<dynamic>(
              requestOptions: RequestOptions(
                path: overrideUrl ??
                    'https://api.example.test/recordings/part-new',
              ),
              statusCode: statusCode,
              headers: Headers.fromMap(
                <String, List<String>>{
                  'location': <String>[
                    '/canonical/recordings/part-new',
                  ],
                },
              ),
            );
          },
        ),
        throwsA(
          isA<UploadException>().having(
            (UploadException error) => error.statusCode,
            'statusCode',
            502,
          ),
        ),
      );

      expect(posts, 1);
    });
  }

  test('resolves redirects against the actual initial request origin', () {
    final Uri initial =
        Uri.parse('https://development.example.test/recordings/part-new');

    expect(
      resolveSameOriginHttpsRedirect(
        initialUri: initial,
        location: '/canonical-part-upload',
        operation: 'Recording part upload',
      ),
      Uri.parse(
        'https://development.example.test/canonical-part-upload',
      ),
    );
    expect(
      () => resolveSameOriginHttpsRedirect(
        initialUri: initial,
        location: 'https://production.example.test/canonical-part-upload',
        operation: 'Recording part upload',
      ),
      throwsA(isA<UploadException>()),
    );
  });
}

class _QueuedHttpAdapter implements HttpClientAdapter {
  final Queue<_AdapterResponse> _responses = Queue<_AdapterResponse>();
  final List<RequestOptions> requests = <RequestOptions>[];

  void enqueue(
    int statusCode, {
    String body = '',
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) {
    _responses.add(
      _AdapterResponse(
        statusCode: statusCode,
        body: body,
        headers: headers,
      ),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_responses.isEmpty) {
      throw StateError('Unexpected mocked HTTP request to ${options.uri}.');
    }
    final _AdapterResponse response = _responses.removeFirst();
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}

  void verifyExhausted() {
    if (_responses.isNotEmpty) {
      throw StateError(
        '${_responses.length} mocked HTTP responses were not consumed.',
      );
    }
  }
}

class _AdapterResponse {
  const _AdapterResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
}
