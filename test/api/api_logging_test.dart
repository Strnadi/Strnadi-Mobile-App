import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/api_logging.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/logging/app_logger.dart';

void main() {
  late _Records records;
  late AppLogger logger;
  late Dio dio;

  setUp(() {
    records = _Records();
    logger = AppLogger(consoleSink: records);
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    installApiLogging(dio, logger);
  });
  tearDown(() => dio.close(force: true));

  Future<Response<dynamic>> request(int status, {bool reject = false}) {
    dio.httpClientAdapter = _Adapter(status: status);
    return dio.get<dynamic>(
      'https://example.test/recordings?token=private&lat=50',
      options: Options(
        validateStatus: reject
            ? (status) => status != null && status < 500
            : (_) => true,
      ),
    );
  }

  test('logs success status and timing without retaining payload', () async {
    final response = await request(200);
    expect(response.statusCode, 200);
    final record = records.values.single;
    expect(record.level, AppLogLevel.info);
    expect(record.context['statusCode'], 200);
    expect(record.context['durationMs'], isA<int>());
    expect(record.context['endpoint'], 'https://example.test/recordings');
    expect(record.context.toString(), isNot(contains('private-payload')));
    expect(record.failure, isNull);
  });

  for (final status in [200, 422, 500]) {
    test('map cluster HTTP $status logs sanitized query parameters', () async {
      dio.httpClientAdapter = _Adapter(status: status);
      await dio.get<dynamic>(
        'https://example.test/recordings/map-clusters',
        queryParameters: {
          'north': 50.25,
          'south': 49.5,
          'zoom': 12,
          'clustered': true,
          'dialects': ['A', 'B'],
          'access_token': 'private-credential',
        },
      );
      final context = records.values.single.context;
      final query = context['queryParameters'] as Map;
      expect(query['north'], ['50.25']);
      expect(query['south'], ['49.5']);
      expect(query['zoom'], ['12']);
      expect(query['clustered'], ['true']);
      expect(query.toString(), contains('A'));
      expect(query.toString(), contains('B'));
      expect(query['access_token'], '***');
      expect(context.toString(), isNot(contains('private-credential')));
      expect(context['statusCode'], status);
    });
  }

  for (final status in [400, 401, 422, 500]) {
    test(
      'classifies accepted HTTP $status and preserves domain occurrence',
      () async {
        final response = await request(status);
        final failure = apiFailureForResponse(response);
        expect(failure, same(records.values.single.failure));
        expect(failure.api!.statusCode, status);
        expect(failure.reason, 'validation_failed');
        expect(failure.expected, status < 500);
        final error = UploadException(
          'Upload failed',
          status,
          logFailure: failure,
        );
        logger.e(
          'Could not upload recording.',
          error: error,
          stackTrace: StackTrace.current,
        );
        expect(records.values.last.failure, same(failure));
        expect(records.values.last.context['statusCode'], status);
      },
    );
  }

  test(
    'rejected HTTP 503 retains response reason and the same occurrence',
    () async {
      try {
        await request(503, reject: true);
        fail('Expected DioException');
      } on DioException catch (error, stackTrace) {
        final failure = apiFailureForDioError(error, stackTrace: stackTrace);
        expect(failure, same(records.values.single.failure));
        expect(failure, same(apiFailureForResponse(error.response!)));
        expect(failure.api!.statusCode, 503);
        expect(failure.reason, 'validation_failed');
        expect(failure.expected, isFalse);
      }
    },
  );

  test(
    'transport failures retain caught stack without inventing a status',
    () async {
      final stack = StackTrace.fromString('original transport stack');
      dio.httpClientAdapter = _Adapter(
        errorType: DioExceptionType.connectionError,
        stack: stack,
      );
      try {
        await dio.get('https://example.test/recordings');
        fail('Expected DioException');
      } on DioException catch (error) {
        final failure = apiFailureForDioError(error);
        expect(failure.api!.statusCode, isNull);
        expect(failure.api!.transportType, 'connectionError');
        expect(failure.expected, isTrue);
        expect(failure.stackTrace.toString(), 'original transport stack');
      }
    },
  );

  test(
    'cancellation is expected but certificate and transform failures are not',
    () {
      for (final type in [
        DioExceptionType.cancel,
        DioExceptionType.badCertificate,
        DioExceptionType.transformTimeout,
      ]) {
        final error = DioException(
          requestOptions: RequestOptions(path: 'https://example.test'),
          type: type,
        );
        final failure = apiFailureForDioError(error);
        expect(failure.expected, type == DioExceptionType.cancel);
        expect(failure.api!.statusCode, isNull);
      }
    },
  );

  test('separate failed requests remain separate occurrences', () async {
    final first = apiFailureForResponse(await request(500));
    final second = apiFailureForResponse(await request(500));
    expect(first, isNot(same(second)));
  });

  test('malformed success is a new unexpected protocol failure', () async {
    final response = await request(200);
    final failure = apiFailureForResponse(
      response,
      reason: 'Invalid backend identifier',
    );
    expect(failure.expected, isFalse);
    expect(failure.api!.statusCode, 200);
    expect(failure.reason, 'Invalid backend identifier');
  });

  for (final status in [400, 500, 200]) {
    test(
      'malformed JSON HTTP $status retains failure classification',
      () async {
        dio.httpClientAdapter = _Adapter(status: status, body: '{malformed');
        try {
          await dio.get<dynamic>('https://example.test/recordings');
          fail('Expected original Dio decoding failure');
        } on DioException catch (error, stackTrace) {
          expect(error.type, DioExceptionType.unknown);
          expect(error.error, isA<FormatException>());
          expect(error.response, isNull);
          final failure = apiFailureForDioError(error, stackTrace: stackTrace);
          expect(failure, same(records.values.single.failure));
          expect(failure.expected, status == 400);
          expect(failure.api!.statusCode, status >= 400 ? status : isNull);
          expect(failure.reason, switch (status) {
            400 => 'Bad request',
            500 => 'Internal server error',
            _ => 'API response could not be decoded',
          });
        }
      },
    );
  }

  test(
    'duplicate correlation headers cannot replace the HTTP failure',
    () async {
      dio.httpClientAdapter = _Adapter(
        status: 422,
        headers: {
          'x-request-id': ['request-first', 'request-second'],
          'x-correlation-id': ['correlation-first', 'correlation-second'],
        },
      );
      final response = await dio.get<dynamic>(
        'https://example.test/recordings',
      );
      final failure = apiFailureForResponse(response);
      expect(failure.api!.statusCode, 422);
      expect(failure.api!.traceId, 'request-first');
      expect(failure.reason, 'validation_failed');
      expect(failure, same(records.values.single.failure));
    },
  );

  test(
    'generic translated exceptions retain disposition and caught stack',
    () async {
      for (final status in [401, 500]) {
        final response = await request(status);
        final original = apiFailureForResponse(response);
        final error = Exception('Request failed with status $status');
        final originalStack = StackTrace.fromString(
          '#0 translate (package:strnadi/api/service.dart:12:3)',
        );
        AppFailureRegistry.attach(error, original);
        try {
          Error.throwWithStackTrace(error, originalStack);
        } catch (caught, stackTrace) {
          logger.e('Request failed.', error: caught, stackTrace: stackTrace);
          expect(caught, same(error));
          expect(records.values.last.failure, same(original));
          expect(records.values.last.stackTrace, same(stackTrace));
          expect(stackTrace.toString(), originalStack.toString());
          expect(records.values.last.failure!.expected, status == 401);
        }
      }
    },
  );

  test('throwing log sink cannot hide an HTTP outcome', () async {
    dio.interceptors.clear();
    dio.interceptors.add(
      apiLoggingInterceptor(AppLogger(consoleSink: _ThrowingSink())),
    );
    expect((await request(201)).statusCode, 201);
  });
}

class _Records implements AppLogSink {
  final values = <AppLogRecord>[];
  @override
  void add(AppLogRecord record) => values.add(record);
}

class _ThrowingSink implements AppLogSink {
  @override
  void add(AppLogRecord record) => throw StateError('Sink unavailable');
}

class _Adapter implements HttpClientAdapter {
  _Adapter({
    this.status = 200,
    this.errorType,
    this.stack,
    this.body,
    this.headers = const {},
  });
  final int status;
  final DioExceptionType? errorType;
  final StackTrace? stack;
  final String? body;
  final Map<String, List<String>> headers;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (errorType != null) {
      throw DioException(
        requestOptions: options,
        type: errorType!,
        stackTrace: stack,
      );
    }
    return ResponseBody.fromString(
      body ??
          jsonEncode({
            'reason': 'validation_failed',
            'private': 'private-payload',
          }),
      status,
      headers: {
        'content-type': ['application/json'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
