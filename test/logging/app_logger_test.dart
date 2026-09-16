import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/utils/log_redactor.dart';

class _Sink implements AppLogSink {
  final records = <AppLogRecord>[];
  @override
  void add(AppLogRecord record) => records.add(record);
}

class _FailingSink implements AppLogSink {
  _FailingSink({this.asynchronous = false});
  final bool asynchronous;
  @override
  FutureOr<void> add(AppLogRecord record) {
    if (asynchronous) return Future<void>.error(StateError('sink failed'));
    throw StateError('sink failed');
  }
}

class _Unprintable {
  @override
  String toString() => throw StateError('cannot print');
}

void main() {
  late _Sink console;
  late _Sink telemetry;
  late AppLogger logger;
  setUp(() {
    console = _Sink();
    telemetry = _Sink();
    AppLogger.configure();
    logger = AppLogger(
      scope: 'recording',
      consoleSink: console,
      telemetrySink: telemetry,
    );
  });
  tearDown(() async {
    await AppLogger.flush();
    AppLogger.configure();
  });

  test(
    'preserves original exception stack and meaningful operation reason',
    () {
      final error = StateError('File cannot be read');
      final stack = StackTrace.fromString('#0 recording.dart:12:3');
      logger.e(
        'Reading the recording failed.',
        error: error,
        stackTrace: stack,
      );
      final record = console.records.single;
      expect(record.reason, 'Reading the recording failed.');
      expect(record.exceptionType, 'StateError');
      expect(record.stackTrace, same(stack));
      expect(record.stackTraceOrigin, 'exception');
      expect(record.failure!.expected, isFalse);
      expect(telemetry.records.single, same(record));
    },
  );

  test('message-only error has a labeled logging-location stack', () {
    logger.e('Audio input is unavailable.');
    final record = console.records.single;
    expect(record.reason, isNotEmpty);
    expect(record.stackTrace.toString(), contains('app_logger_test.dart'));
    expect(record.stackTraceOrigin, 'logger');
  });

  test('warning with an unexpected error is still reportable', () {
    logger.w('Database cleanup failed.', error: StateError('missing table'));
    expect(console.records.single.failure!.expected, isFalse);
  });

  test(
    'offline errors and explicitly expected failures keep expected policy',
    () {
      logger.e('Upload deferred.', error: const SocketException('offline'));
      logger.e('Permission denied.', expected: true);
      expect(
        console.records.map((r) => r.failure!.expected),
        everyElement(isTrue),
      );
    },
  );

  test('request provenance survives an outer error log without escalation', () {
    final diagnostics = ApiDiagnostics.fromResponse(
      method: 'GET',
      uri: Uri.parse('https://api.test/recording?token=secret'),
      statusCode: 401,
      payload: {'reason': 'login_required'},
    );
    final failure = AppFailure(
      reason: diagnostics.reason,
      api: diagnostics,
      expected: true,
    );
    final error = StateError('Request failed');
    AppFailureRegistry.attach(error, failure);
    logger.api(diagnostics, failure: failure);
    logger.e(
      'Opening recording failed.',
      error: error,
      stackTrace: StackTrace.current,
    );
    expect(console.records.every((r) => identical(r.failure, failure)), isTrue);
    expect(console.records.last.context['statusCode'], 401);
    expect(console.records.last.reason, 'login_required');
    expect(console.records.last.failure!.expected, isTrue);
  });

  test('API success includes timing and status without an error stack', () {
    logger.api(
      ApiDiagnostics.fromResponse(
        method: 'POST',
        uri: Uri.parse('https://api.test/recordings'),
        statusCode: 201,
        durationMs: 25,
      ),
    );
    expect(console.records.single.context['statusCode'], 201);
    expect(console.records.single.context['durationMs'], 25);
    expect(console.records.single.stackTrace, isNull);
    expect(console.records.single.failure, isNull);
  });

  test('same caught error uses one occurrence, fresh throws stay distinct', () {
    const error = FormatException('Invalid recording');
    final stack = StackTrace.fromString('#0 parseRecording:12');
    logger.e('Parsing failed.', error: error, stackTrace: stack);
    logger.e('Opening failed.', error: error, stackTrace: stack);
    logger.e(
      'A later parse failed.',
      error: error,
      stackTrace: StackTrace.fromString('#0 parseRecording:12'),
    );
    expect(console.records[0].failure, same(console.records[1].failure));
    expect(console.records[2].failure, isNot(same(console.records[0].failure)));
  });

  test('redacts both destinations including free text and nested context', () {
    logger.e(
      'GET https://user:PASS@api.test/file?latitude=50&token=TOKEN#FRAGMENT failed',
      error: StateError('token=ERROR_SECRET'),
      context: {
        'Authorization': 'Bearer AUTH_SECRET',
        'nested': {'refresh_token': 'REFRESH_SECRET'},
        'responseBody': '{"displayName":"PRIVATE_RESPONSE"}',
        'requestPayload': {'name': 'PRIVATE_REQUEST'},
        'statusCode': 422,
        'errorCode': 'invalid_viewport',
      },
    );
    for (final record in [console.records.single, telemetry.records.single]) {
      final text =
          '${record.message} ${record.errorDescription} ${record.context}';
      for (final secret in [
        'PASS',
        'TOKEN',
        'FRAGMENT',
        'ERROR_SECRET',
        'AUTH_SECRET',
        'REFRESH_SECRET',
        'PRIVATE_RESPONSE',
        'PRIVATE_REQUEST',
        'latitude=50',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(record.context['statusCode'], 422);
      expect(record.context['errorCode'], 'invalid_viewport');
      expect(record.message, 'GET https://api.test/file failed');
    }
  });

  test('Dart StateError prefix preserves useful diagnostic text', () {
    expect(
      LogRedactor.redactText('Bad state: database unavailable'),
      'Bad state: database unavailable',
    );
    expect(
      LogRedactor.redactText('Bad state: token=SECRET'),
      isNot(contains('SECRET')),
    );
  });

  test('parser errors never include the rejected response body', () {
    const body = '{"profile": "PRIVATE_PROFILE", "token": "PRIVATE_TOKEN"}';
    const error = FormatException('Invalid response', body, 1);
    logger.e('Reading profile failed: $error', error: error);
    for (final record in [console.records.single, telemetry.records.single]) {
      final output = '${record.message} ${record.errorDescription}';
      expect(output, contains('Invalid response'));
      expect(output, isNot(contains('PRIVATE_PROFILE')));
      expect(output, isNot(contains('PRIVATE_TOKEN')));
      expect(record.failure!.api, isNull);
      expect(record.failure!.expected, isFalse);
    }
  });

  test('sanitizes stack and URI context while retaining caught identity', () {
    final stack = StackTrace.fromString(
      '#0 read (https://api.test/app.dart?sig=STACK_SECRET:12:3)\n'
      '#1 open (package:strnadi/recording.dart:20:5)\n'
      '#2 main (file:///Users/PRIVATE_USER/project/main.dart:30:6)',
    );
    final error = StateError('File unavailable');
    logger.e(
      'Reading the recording failed.',
      error: error,
      stackTrace: stack,
      context: {
        'endpoint': Uri.parse(
          'https://api.test/file?X-Amz-Signature=URI_SECRET',
        ),
      },
    );
    for (final record in [console.records.single, telemetry.records.single]) {
      expect(record.stackTrace.toString(), isNot(contains('STACK_SECRET')));
      expect(record.stackTrace.toString(), contains('app.dart:12:3)'));
      expect(record.stackTrace.toString(), contains('\n#1 open'));
      expect(
        record.stackTrace.toString(),
        contains('redacted/main.dart:30:6)'),
      );
      expect(record.stackTrace.toString(), isNot(contains('PRIVATE_USER')));
      expect(record.context['endpoint'], 'https://api.test/file');
      expect(record.failure!.stackTrace, same(stack));
    }
    logger.e('Opening recording failed.', error: error, stackTrace: stack);
    expect(console.records.last.failure, same(console.records.first.failure));
  });

  test('sink failures and unprintable errors never escape logging', () async {
    final logger = AppLogger(
      consoleSink: _FailingSink(),
      telemetrySink: _FailingSink(asynchronous: true),
    );
    expect(() => logger.e(_Unprintable()), returnsNormally);
    await AppLogger.flush();
  });

  test('bounded recursive redaction handles cyclic context', () {
    final context = <String, Object?>{};
    context['self'] = context;
    logger.i('Context snapshot', context: context);
    expect(console.records.single.context.toString(), contains('omitted'));
  });

  test(
    'task-local disabled telemetry overrides global and instance sinks',
    () async {
      AppLogger.configure(telemetrySink: telemetry);
      await AppLogger.runWithTelemetry<void>(null, () async {
        logger.e('Task failed.');
        await AppLogger.flush();
      });
      expect(console.records, hasLength(1));
      expect(telemetry.records, isEmpty);
      logger.i('Foreground continues.');
      expect(telemetry.records, hasLength(1));
    },
  );

  test(
    'log level can disable both sinks without relying on main bootstrap',
    () {
      AppLogger(
        level: AppLogLevel.off,
        consoleSink: console,
        telemetrySink: telemetry,
      ).e('Disabled');
      expect(console.records, isEmpty);
      expect(telemetry.records, isEmpty);
    },
  );
}
