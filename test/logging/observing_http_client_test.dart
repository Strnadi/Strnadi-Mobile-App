import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:strnadi/api/map_tile_provider.dart';
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/observing_http_client.dart';

class _Sink implements AppLogSink {
  final records = <AppLogRecord>[];

  @override
  void add(AppLogRecord record) => records.add(record);
}

class _Client extends http.BaseClient {
  _Client(this.respond);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest) respond;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      respond(request);

  @override
  void close() => closeCount++;
}

class _ResponseWithUrl extends http.StreamedResponse
    implements http.BaseResponseWithUrl {
  _ResponseWithUrl(super.stream, super.statusCode, this.url);

  @override
  final Uri url;
}

void main() {
  late _Sink sink;
  late AppLogger logger;
  final uri = Uri.parse('https://api.test/tiles/1/2/3.png?token=secret');

  setUp(() {
    sink = _Sink();
    logger = AppLogger(scope: 'test.http', consoleSink: sink);
  });

  test(
    'preserves request identity, abort trigger, metadata and lazy bytes',
    () async {
      final abort = Completer<void>();
      final request =
          http.AbortableRequest('GET', uri, abortTrigger: abort.future)
            ..followRedirects = false
            ..maxRedirects = 2
            ..headers['Authorization'] = 'Bearer secret';
      final bytes = [0, 1, 2, 3];
      var listened = false;
      final controller = StreamController<List<int>>(
        onListen: () => listened = true,
      );
      final inner = _Client((actual) {
        expect(identical(actual, request), isTrue);
        expect(
          identical((actual as http.Abortable).abortTrigger, abort.future),
          isTrue,
        );
        return http.StreamedResponse(
          controller.stream,
          200,
          contentLength: bytes.length,
          request: actual,
          headers: {'etag': 'v1', 'cache-control': 'max-age=300'},
          isRedirect: true,
          persistentConnection: false,
          reasonPhrase: 'OK',
        );
      });
      final client = ObservingHttpClient(inner, logger: logger);
      final response = await client.send(request);
      expect(listened, isFalse);
      expect(response.request, same(request));
      expect(response.contentLength, bytes.length);
      expect(response.headers['etag'], 'v1');
      expect(response.headers['cache-control'], 'max-age=300');
      expect(response.isRedirect, isTrue);
      expect(response.persistentConnection, isFalse);
      expect(response.reasonPhrase, 'OK');
      expect(sink.records.single.context['statusCode'], 200);
      expect(sink.records.single.context['durationMs'], isNonNegative);
      expect(
        sink.records.single.context['endpoint'],
        'https://api.test/tiles/1/2/3.png',
      );
      expect(sink.records.single.failure, isNull);

      final result = response.stream.toList();
      controller.add(bytes);
      await controller.close();
      expect((await result).single, same(bytes));
      expect(sink.records, hasLength(1));
      client.close();
    },
  );

  test(
    'preserves final redirect URL when the transport supplies one',
    () async {
      final finalUri = Uri.parse('https://cdn.test/final.png');
      final client = ObservingHttpClient(
        _Client((_) => _ResponseWithUrl(const Stream.empty(), 200, finalUri)),
        logger: logger,
      );
      final response = await client.send(http.Request('GET', uri));
      expect((response as http.BaseResponseWithUrl).url, finalUri);
      await response.stream.drain<void>();
      client.close();
    },
  );

  test(
    'reports protected redirect rejection while preserving tile cache status',
    () async {
      final observation = HttpRequestObservation(
        method: 'GET',
        uri: uri,
        logger: logger,
      );
      await observation
          .observeResponse(
            const Stream.empty(),
            statusCode: 302,
            treatRedirectsAsFailure: true,
          )
          .drain<void>();
      expect(sink.records.single.context['statusCode'], 302);
      expect(sink.records.single.failure!.expected, isTrue);
      expect(
        sink.records.single.reason,
        'Protected attachment redirect was rejected',
      );

      await HttpRequestObservation(
        method: 'GET',
        uri: uri,
        logger: logger,
      ).observeResponse(const Stream.empty(), statusCode: 304).drain<void>();
      expect(sink.records.last.context['statusCode'], 304);
      expect(sink.records.last.failure, isNull);
    },
  );

  for (final status in [400, 401, 422, 500]) {
    test(
      'records status $status and bounded API reason without altering bytes',
      () async {
        final body = utf8.encode(
          jsonEncode({
            'error': {
              'code': 'request_rejected',
              'reason': 'Attachment unavailable',
            },
            'access_token': 'never-log-this',
          }),
        );
        final client = ObservingHttpClient(
          _Client(
            (_) => http.StreamedResponse(
              Stream.fromIterable([body.sublist(0, 12), body.sublist(12)]),
              status,
              headers: {'x-request-id': 'request-17'},
            ),
          ),
          logger: logger,
        );
        final response = await client.send(http.Request('GET', uri));
        expect(await response.stream.toBytes(), body);
        expect(sink.records, hasLength(1));
        final record = sink.records.single;
        expect(record.context['statusCode'], status);
        expect(record.reason, 'Attachment unavailable');
        expect(record.context['errorCode'], 'request_rejected');
        expect(record.context['traceId'], 'request-17');
        expect(record.failure!.expected, status < 500);
        expect(record.stackTrace, isNotNull);
        expect(record.context.toString(), isNot(contains('never-log-this')));
        client.close();
      },
    );
  }

  test(
    'inspects at most the bounded error prefix and forwards the whole body',
    () async {
      final body = utf8.encode(
        jsonEncode({'reason': 'x' * (ApiDiagnostics.maximumBodyBytes + 100)}),
      );
      final client = ObservingHttpClient(
        _Client((_) => http.StreamedResponse(Stream.value(body), 502)),
        logger: logger,
      );
      final response = await client.send(http.Request('GET', uri));
      expect(await response.stream.toBytes(), body);
      expect(
        sink.records.single.reason,
        'Invalid response from upstream server',
      );
      expect(
        sink.records.single.reason!.length,
        lessThanOrEqualTo(ApiDiagnostics.maximumFieldLength),
      );
      client.close();
    },
  );

  test(
    'keeps transport exceptions and their original stack without a status',
    () async {
      const error = SocketException('Offline');
      final stack = StackTrace.fromString('original transport stack');
      final client = ObservingHttpClient(
        _Client((_) => Error.throwWithStackTrace(error, stack)),
        logger: logger,
      );
      try {
        await client.send(http.Request('GET', uri));
        fail('Request must fail');
      } catch (actual, actualStack) {
        expect(actual, same(error));
        expect(actualStack.toString(), stack.toString());
      }
      expect(sink.records.single.context, isNot(contains('statusCode')));
      expect(sink.records.single.failure!.expected, isTrue);
      expect(sink.records.single.stackTrace.toString(), stack.toString());
      client.close();
    },
  );

  test(
    'classifies aborted requests as expected and preserves the exception',
    () async {
      final error = http.RequestAbortedException(uri);
      final client = ObservingHttpClient(
        _Client((_) => throw error),
        logger: logger,
      );
      await expectLater(
        client.send(http.Request('GET', uri)),
        throwsA(same(error)),
      );
      expect(sink.records.single.failure!.expected, isTrue);
      expect(sink.records.single.context['transportType'], 'cancelled');
      client.close();
    },
  );

  test(
    'forwards pause, resume, cancellation and reports a partial error once',
    () async {
      var pauses = 0, resumes = 0, cancels = 0;
      final controller = StreamController<List<int>>(
        onPause: () => pauses++,
        onResume: () => resumes++,
        onCancel: () => cancels++,
      );
      final client = ObservingHttpClient(
        _Client((_) => http.StreamedResponse(controller.stream, 500)),
        logger: logger,
      );
      final response = await client.send(http.Request('GET', uri));
      final subscription = response.stream.listen((_) {});
      subscription.pause();
      expect(pauses, 1);
      subscription.resume();
      expect(resumes, 1);
      await subscription.cancel();
      expect(cancels, 1);
      expect(sink.records, hasLength(1));
      expect(sink.records.single.context['statusCode'], 500);
      await controller.close();
      client.close();
    },
  );

  test(
    'records early stream cancellation without inventing an HTTP status',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final observation = HttpRequestObservation(
        method: 'GET',
        uri: uri,
        logger: logger,
      );
      final subscription = observation
          .observeResponse(source.stream, statusCode: 200)
          .listen((_) {});
      await subscription.cancel();
      expect(cancelled, isTrue);
      expect(sink.records, hasLength(2));
      expect(sink.records.last.failure!.expected, isTrue);
      expect(sink.records.last.context['transportType'], 'cancelled');
      expect(sink.records.last.context, isNot(contains('statusCode')));
      expect(sink.records.last.stackTraceOrigin, 'logger');
      await source.close();
    },
  );

  test(
    'preserves errors raised while streaming successful protected downloads',
    () async {
      const error = SocketException('connection closed while receiving');
      final stack = StackTrace.fromString('original streaming stack');
      final observation = HttpRequestObservation(
        method: 'GET',
        uri: uri,
        logger: logger,
      );
      final stream = observation.observeResponse(
        Stream<List<int>>.error(error, stack),
        statusCode: 200,
      );
      await expectLater(stream.drain<void>(), throwsA(same(error)));
      expect(sink.records, hasLength(2));
      final failure = sink.records.last;
      expect(failure.context, isNot(contains('statusCode')));
      expect(failure.failure!.expected, isTrue);
      expect(failure.stackTrace.toString(), stack.toString());
      logger.e('Outer attachment catch', error: error, stackTrace: stack);
      expect(sink.records.last.failure, same(failure.failure));
    },
  );

  test(
    'retains observed HTTP status if reading its error body fails',
    () async {
      const error = SocketException('truncated error body');
      final stack = StackTrace.fromString('error body read stack');
      final observation = HttpRequestObservation(
        method: 'GET',
        uri: uri,
        logger: logger,
      );
      final stream = observation.observeResponse(
        Stream<List<int>>.error(error, stack),
        statusCode: 500,
      );
      await expectLater(stream.drain<void>(), throwsA(same(error)));
      expect(sink.records, hasLength(1));
      expect(sink.records.single.context['statusCode'], 500);
      expect(sink.records.single.stackTrace.toString(), stack.toString());
      logger.e('Outer attachment catch', error: error, stackTrace: stack);
      expect(sink.records.last.failure, same(sink.records.first.failure));
    },
  );

  test(
    'leaves RetryClient retries intact and records only the final response',
    () async {
      var calls = 0;
      final inner = _Client((_) {
        calls++;
        return http.StreamedResponse(
          const Stream.empty(),
          calls == 1 ? 503 : 200,
        );
      });
      final client = ObservingHttpClient(
        RetryClient(inner, delay: (_) => Duration.zero),
        logger: logger,
      );
      final response = await client.send(http.Request('GET', uri));
      await response.stream.drain<void>();
      expect(calls, 2);
      expect(sink.records, hasLength(1));
      expect(sink.records.single.context['statusCode'], 200);
      client.close();
      client.close();
      expect(inner.closeCount, 1);
    },
  );

  test(
    'tile provider retains caching/cancellation defaults and owns disposal',
    () async {
      final inner = _Client(
        (_) => http.StreamedResponse(const Stream.empty(), 200),
      );
      final provider = createMapTileProvider(httpClient: inner, logger: logger);
      expect(provider.supportsCancelLoading, isTrue);
      expect(provider.abortObsoleteRequests, isTrue);
      expect(provider.cachingProvider, isNull);
      expect(provider.attemptDecodeOfHttpErrorResponses, isTrue);
      expect(provider.silenceExceptions, isFalse);
      await provider.dispose();
      await provider.dispose();
      expect(inner.closeCount, 1);
    },
  );
}
