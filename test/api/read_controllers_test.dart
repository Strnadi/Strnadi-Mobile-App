import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/api/controllers/achievements_controller.dart';
import 'package:strnadi/api/controllers/articles_controller.dart';
import 'package:strnadi/api/controllers/dialects_controller.dart';
import 'package:strnadi/api/controllers/health_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late Dio dio;
  late HttpClientAdapter originalAdapter;
  late _QueuedHttpAdapter adapter;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (_) async => null);
    await Config.loadConfig();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  setUp(() {
    dio = ApiDioClient.instance;
    originalAdapter = dio.httpClientAdapter;
    adapter = _QueuedHttpAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    dio.httpClientAdapter = originalAdapter;
    adapter.verifyExhausted();
  });

  group('ArticlesController', () {
    test('builds article, category, and markdown requests', () async {
      adapter
        ..enqueue(200, body: '[]')
        ..enqueue(200, body: '[]')
        ..enqueue(200, body: '# article');
      const ArticlesController controller = ArticlesController();

      await controller.fetchArticles();
      await controller.fetchArticleCategories(includeArticles: false);
      await controller.fetchArticleMarkdown(
        articleId: 17,
        languageTag: 'cs-CZ',
      );

      expect(adapter.requests, hasLength(3));
      _expectRequest(
        adapter.requests[0],
        Uri.parse('https://${Config.host}/articles'),
      );
      _expectRequest(
        adapter.requests[1],
        Uri.parse('https://${Config.host}/articles/categories?articles=false'),
      );
      _expectRequest(
        adapter.requests[2],
        Uri.parse('https://${Config.host}/articles/17/cs-CZ.md'),
      );
      expect(adapter.requests[0].headers['accept'], 'application/json');
      expect(adapter.requests[1].headers['accept'], 'application/json');
      expect(adapter.requests[2].headers['accept'], 'application/json');
      expect(adapter.requests[2].responseType, ResponseType.bytes);
    });

    test('returns the preferred article language without fallback', () async {
      adapter.enqueue(200, body: '# Deutsch');

      final Response<dynamic> response =
          await const ArticlesController().fetchArticleMarkdownWithFallback(
        articleId: 8,
        preferredLanguageTag: 'de-DE',
      );

      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.path, '/articles/8/de-DE.md');
    });

    test('falls back to English after a missing preferred translation',
        () async {
      adapter
        ..enqueue(404)
        ..enqueue(200, body: '# English');

      final Response<dynamic> response =
          await const ArticlesController().fetchArticleMarkdownWithFallback(
        articleId: 8,
        preferredLanguageTag: 'de-DE',
      );

      expect(response.statusCode, 200);
      expect(
        adapter.requests.map((RequestOptions request) => request.uri.path),
        <String>['/articles/8/de-DE.md', '/articles/8/en-US.md'],
      );
    });

    test('trims and de-duplicates a preferred fallback language', () async {
      adapter
        ..enqueue(404)
        ..enqueue(200, body: '# Czech');

      final Response<dynamic> response =
          await const ArticlesController().fetchArticleMarkdownWithFallback(
        articleId: 9,
        preferredLanguageTag: ' en-US ',
      );

      expect(response.statusCode, 200);
      expect(
        adapter.requests.map((RequestOptions request) => request.uri.path),
        <String>['/articles/9/en-US.md', '/articles/9/cs-CZ.md'],
      );
    });

    test('returns the last non-auth response when every language fails',
        () async {
      adapter
        ..enqueue(404)
        ..enqueue(410)
        ..enqueue(503);

      final Response<dynamic> response =
          await const ArticlesController().fetchArticleMarkdownWithFallback(
        articleId: 10,
        preferredLanguageTag: 'de-DE',
      );

      expect(response.statusCode, 503);
      expect(adapter.requests, hasLength(3));
    });

    for (final int statusCode in <int>[401, 403]) {
      test('does not hide or retry an HTTP $statusCode response', () async {
        adapter.enqueue(statusCode);

        final Response<dynamic> response =
            await const ArticlesController().fetchArticleMarkdownWithFallback(
          articleId: 11,
          preferredLanguageTag: 'de-DE',
        );

        expect(response.statusCode, statusCode);
        expect(adapter.requests, hasLength(1));
      });
    }

    test('rethrows an authentication DioException without retrying', () async {
      adapter.enqueueError(statusCode: 401);

      await expectLater(
        const ArticlesController().fetchArticleMarkdownWithFallback(
          articleId: 12,
          preferredLanguageTag: 'de-DE',
        ),
        throwsA(
          isA<DioException>().having(
            (DioException error) => error.response?.statusCode,
            'statusCode',
            401,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('tries every language and preserves the last connection failure',
        () async {
      adapter
        ..enqueueError(message: 'preferred unavailable')
        ..enqueueError(message: 'English unavailable')
        ..enqueueError(message: 'Czech unavailable');

      await expectLater(
        const ArticlesController().fetchArticleMarkdownWithFallback(
          articleId: 13,
          preferredLanguageTag: 'de-DE',
        ),
        throwsA(
          isA<DioException>().having(
            (DioException error) => error.message,
            'message',
            contains('Czech unavailable'),
          ),
        ),
      );
      expect(adapter.requests, hasLength(3));
    });
  });

  group('simple read controllers', () {
    test('achievements routes distinguish global and per-user reads', () async {
      adapter
        ..enqueue(200)
        ..enqueue(200);
      const AchievementsController controller = AchievementsController();

      await controller.fetchAll();
      await controller.fetchForUser(42);

      _expectRequest(
        adapter.requests[0],
        Uri.parse('https://${Config.host}/achievements'),
      );
      _expectRequest(
        adapter.requests[1],
        Uri.parse('https://${Config.host}/achievements?userId=42'),
      );
      expect(
        adapter.requests,
        everyElement(
          isA<RequestOptions>().having(
            (RequestOptions request) => request.contentType,
            'contentType',
            Headers.jsonContentType,
          ),
        ),
      );
    });

    test('dialect routes include the recording id and honor a custom host',
        () async {
      adapter
        ..enqueue(200)
        ..enqueue(200);
      const DialectsController controller = DialectsController();

      await controller.fetchDialectsForRecording(91);
      await controller.fetchDialectPalette(host: 'dev.example.test');

      _expectRequest(
        adapter.requests[0],
        Uri.parse('https://${Config.host}/dialects?recordingId=91'),
      );
      _expectRequest(
        adapter.requests[1],
        Uri.parse('https://dev.example.test/recordings/dialects'),
      );
    });

    test('dialect palette defaults to the configured host', () async {
      adapter.enqueue(200);

      await const DialectsController().fetchDialectPalette();

      _expectRequest(
        adapter.requests.single,
        Uri.parse('https://${Config.host}/recordings/dialects'),
      );
    });

    test('health check uses HEAD and explicitly disables authentication',
        () async {
      adapter.enqueue(204);

      final Response<dynamic> response = await const HealthController()
          .checkBackendHealth(host: 'health.example.test');

      expect(response.statusCode, 204);
      _expectRequest(
        adapter.requests.single,
        Uri.parse('https://health.example.test/utils/health'),
        method: 'HEAD',
      );
      expect(adapter.requests.single.extra['authRequired'], isFalse);
      expect(adapter.requests.single.headers['Authorization'], isNull);
    });
  });
}

void _expectRequest(
  RequestOptions request,
  Uri expectedUri, {
  String method = 'GET',
}) {
  expect(request.uri, expectedUri);
  expect(request.method, method);
}

class _QueuedHttpAdapter implements HttpClientAdapter {
  final Queue<_AdapterOutcome> _outcomes = Queue<_AdapterOutcome>();
  final List<RequestOptions> requests = <RequestOptions>[];

  void enqueue(int statusCode, {String body = ''}) {
    _outcomes.add(
      _AdapterOutcome.response(statusCode: statusCode, body: body),
    );
  }

  void enqueueError({int? statusCode, String message = 'mock network error'}) {
    _outcomes.add(
      _AdapterOutcome.error(statusCode: statusCode, message: message),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
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
    if (outcome.isError) {
      throw DioException(
        requestOptions: options,
        response: outcome.statusCode == null
            ? null
            : Response<dynamic>(
                requestOptions: options,
                statusCode: outcome.statusCode,
              ),
        type: outcome.statusCode == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
        message: outcome.message,
      );
    }
    return ResponseBody.fromString(outcome.body, outcome.statusCode!);
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
  const _AdapterOutcome.response({required this.statusCode, required this.body})
      : isError = false,
        message = '';

  const _AdapterOutcome.error({required this.statusCode, required this.message})
      : isError = true,
        body = '';

  final int? statusCode;
  final String body;
  final bool isError;
  final String message;
}
