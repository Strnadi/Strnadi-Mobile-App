import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/sentry_log_sink.dart';

class _WireTransport extends Transport {
  final List<SentryEvent> events = [];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    events.addAll(
      envelope.items
          .map((item) => item.originalObject)
          .whereType<SentryEvent>(),
    );
    return envelope.header.eventId;
  }
}

class _QuietSink implements AppLogSink {
  @override
  void add(AppLogRecord record) {}
}

void main() {
  late _WireTransport transport;
  late SentryLogSink sink;
  late bool authorized;
  late DateTime now;

  setUp(() async {
    authorized = true;
    now = DateTime.utc(2026, 9, 15);
    transport = _WireTransport();
    sink = SentryLogSink(
      isAuthorized: () async => authorized,
      clock: () => now,
    );
    // Use the initialized SDK, including its real default event processors.
    // A bare Hub omits the SDK's throwable-hash deduplication processor.
    await Sentry.init((options) {
      sink.configureOptions(options);
      options
        ..dsn = 'https://public@example.test/1'
        ..transport = transport
        ..sendClientReports = false
        ..debug = false
        ..tracesSampleRate = 1.0
        ..release = 'strnadi@test+1'
        ..environment = 'test';
    });
    AppLogger.configure(telemetrySink: sink);
  });

  tearDown(() async {
    await AppLogger.flush();
    await Sentry.close();
    AppLogger.configure();
  });

  test(
    'transactions preserve spans, measurements and sampling while sanitized',
    () async {
      final transaction = Sentry.startTransaction(
        'Map refresh',
        'ui.load',
        description: 'https://api.example.test/tiles?token=ROOT_SECRET',
      );
      final traceId = transaction.toSentryTrace().traceId;
      transaction.setData('Authorization', 'Bearer ROOT_HEADER_SECRET');
      transaction.setMeasurement('tile_count', 3);
      final child = transaction.startChild(
        'http.client',
        description: 'https://api.example.test/tiles?token=CHILD_URL_SECRET',
      );
      child.setData('token', 'CHILD_DATA_SECRET');
      child.setData('statusCode', 200);
      child.setTag('accessToken', 'CHILD_TAG_SECRET');
      await child.finish();
      await transaction.finish();

      final captured = transport.events.single;
      expect(captured, isA<SentryTransaction>());
      final trace = captured as SentryTransaction;
      expect(trace.transaction, 'Map refresh');
      expect(trace.release, 'strnadi@test+1');
      expect(trace.environment, 'test');
      expect(trace.contexts.trace!.traceId, traceId);
      expect(trace.sampled, isTrue);
      expect(trace.startTimestamp, transaction.startTimestamp);
      expect(trace.timestamp, transaction.endTimestamp);
      expect(trace.spans, hasLength(1));
      expect(trace.spans.single.data['statusCode'], 200);
      expect(trace.measurements['tile_count']!.value, 3);
      final wire = jsonEncode(trace.toJson());
      for (final secret in [
        'ROOT_SECRET',
        'ROOT_HEADER_SECRET',
        'CHILD_URL_SECRET',
        'CHILD_DATA_SECRET',
        'CHILD_TAG_SECRET',
      ]) {
        expect(wire, isNot(contains(secret)));
      }
    },
  );

  test('transaction consent is rechecked before send', () async {
    final rejected = Sentry.startTransaction('Denied trace', 'task');
    authorized = false;
    await rejected.finish();
    expect(transport.events, isEmpty);
    authorized = true;
    final allowed = Sentry.startTransaction('Allowed trace', 'task');
    await allowed.finish();
    expect(transport.events.single, isA<SentryTransaction>());
  });

  test(
    'SDK pipeline dedupes occurrences without suppressing independent automatic throws',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink());
      const error = FormatException('reused exception');
      final first = StackTrace.fromString(
        '#0 first (package:strnadi/task.dart:12:3)',
      );
      final second = StackTrace.fromString(
        '#0 second (package:strnadi/task.dart:24:3)',
      );
      logger.e('First failure.', error: error, stackTrace: first);
      await AppLogger.flush();
      await Sentry.captureException(error, stackTrace: first);
      expect(transport.events, hasLength(1));
      await Sentry.captureException(error, stackTrace: second);
      expect(transport.events, hasLength(2));
      await Sentry.captureException(error, stackTrace: second);
      expect(transport.events, hasLength(2));
      now = now.add(const Duration(seconds: 2));
      await Sentry.captureException(error, stackTrace: second);
      expect(transport.events, hasLength(3));
      await Sentry.captureException(
        FormatException('reused exception'),
        stackTrace: second,
      );
      expect(transport.events, hasLength(4));
    },
  );

  test(
    'signed URL stack deduplicates against its sanitized explicit stack',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink());
      final error = StateError('remote source failure');
      final stack = StackTrace.fromString(
        '#0 read (https://cdn.example.test/app.dart?token=STACK_SECRET:42:7)',
      );
      logger.e('Read failed.', error: error, stackTrace: stack);
      await AppLogger.flush();
      await Sentry.captureException(error, stackTrace: stack);
      expect(transport.events, hasLength(1));
      expect(
        jsonEncode(transport.events.single.toJson()),
        isNot(contains('STACK_SECRET')),
      );
    },
  );

  test(
    'redacted filesystem stack still deduplicates its automatic original',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink());
      final error = StateError('filesystem failure');
      final stack = StackTrace.fromString(
        '#0 read (file:///Users/private-person/project/app.dart:42:7)',
      );
      logger.e('Read failed.', error: error, stackTrace: stack);
      await AppLogger.flush();
      await Sentry.captureException(error, stackTrace: stack);
      expect(transport.events, hasLength(1));
      expect(
        jsonEncode(transport.events.single.toJson()),
        isNot(contains('private-person')),
      );
      expect(
        transport
            .events
            .single
            .exceptions!
            .single
            .stackTrace!
            .frames
            .single
            .lineNo,
        42,
      );
    },
  );
}
