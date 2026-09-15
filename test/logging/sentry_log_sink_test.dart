import 'dart:convert';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/sentry_log_sink.dart';
import 'package:strnadi/logging/telemetry_consent.dart';

class _MemoryTransport extends Transport {
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
  final List<AppLogRecord> records = [];

  @override
  void add(AppLogRecord record) => records.add(record);
}

void main() {
  late _MemoryTransport transport;
  late Hub hub;
  late SentryLogSink sink;
  late SentryOptions options;
  late bool authorized;

  setUp(() {
    authorized = true;
    transport = _MemoryTransport();
    options = SentryOptions()
      ..dsn = 'https://public@example.test/1'
      ..transport = transport
      ..sendClientReports = false;
    hub = Hub(options);
    sink = SentryLogSink(hub: hub, isAuthorized: () async => authorized);
    options.beforeSend = sink.beforeSend;
    options.beforeBreadcrumb = sink.beforeBreadcrumb;
  });
  tearDown(() async {
    await hub.close();
    AppLogger.configure();
  });

  test(
    'unexpected local error retains type and original stack without secrets',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      logger.e(
        'Playback failed.',
        error: StateError('Authorization: Bearer TOP_SECRET'),
        stackTrace: StackTrace.fromString(
          '#0 play (package:strnadi/audio.dart:42:7)',
        ),
      );
      await AppLogger.flush();
      expect(transport.events, hasLength(1));
      final event = transport.events.single;
      expect(event.throwable, isNull);
      expect(event.exceptions!.single.type, 'StateError');
      expect(event.exceptions!.single.stackTrace!.frames.single.lineNo, 42);
      expect(jsonEncode(event.toJson()), isNot(contains('TOP_SECRET')));
    },
  );

  test(
    'expected failures are breadcrumbs and successful responses remain diagnostic',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      logger.w(
        'API request rejected.',
        error: StateError('invalid input'),
        expected: true,
        context: {'statusCode': 400, 'errorCode': 'validation_failed'},
      );
      logger.i(
        'GET /recordings completed.',
        context: {'statusCode': 200, 'elapsedMs': 23},
      );
      await AppLogger.flush();
      expect(transport.events, isEmpty);
      logger.e('Unexpected decoder error.', error: StateError('bad format'));
      await AppLogger.flush();
      final crumbs = transport.events.single.breadcrumbs!;
      expect(crumbs, hasLength(2));
      expect(crumbs.first.data!['statusCode'], 400);
      expect(crumbs.first.data!['errorCode'], 'validation_failed');
      expect(crumbs.last.data!['elapsedMs'], 23);
    },
  );

  test(
    'wrapper plus automatic uncaught capture reports the occurrence once',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      final error = StateError('unexpected');
      final stack = StackTrace.fromString(
        '#0 fail (package:strnadi/task.dart:12:3)',
      );
      logger.e('Operation failed.', error: error, stackTrace: stack);
      await AppLogger.flush();
      await hub.captureEvent(
        SentryEvent(
          throwable: ThrowableMechanism(
            Mechanism(type: 'FlutterError', handled: false),
            error,
          ),
        ),
        stackTrace: stack,
      );
      expect(transport.events, hasLength(1));
      logger.e(
        'Independent failure.',
        error: StateError('unexpected'),
        stackTrace: stack,
      );
      await AppLogger.flush();
      expect(transport.events, hasLength(2));
    },
  );

  test(
    'automatic throw of a reused const error at a new site is a new occurrence',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      const error = FormatException('reused exception');
      final first = StackTrace.fromString(
        '#0 first (package:strnadi/task.dart:12:3)',
      );
      final second = StackTrace.fromString(
        '#0 second (package:strnadi/task.dart:24:3)',
      );
      logger.e('First failure.', error: error, stackTrace: first);
      await AppLogger.flush();
      await hub.captureException(error, stackTrace: first);
      expect(transport.events, hasLength(1));
      await hub.captureException(error, stackTrace: second);
      expect(transport.events, hasLength(2));
      expect(
        transport
            .events
            .last
            .exceptions!
            .single
            .stackTrace!
            .frames
            .single
            .lineNo,
        24,
      );
    },
  );

  test(
    'automatic capture winning the race retains API reason and correlation',
    () async {
      final error = StateError('upstream failed');
      final stack = StackTrace.fromString(
        '#0 get (package:strnadi/api.dart:7:2)',
      );
      final diagnostics = ApiDiagnostics.fromResponse(
        method: 'GET',
        uri: Uri.parse('https://api.example.test/recordings'),
        statusCode: 503,
        payload: {
          'reason': 'Storage unavailable',
          'error': 'storage_unavailable',
        },
        requestId: 'request-7',
      );
      final failure = AppFailure(
        reason: diagnostics.reason,
        api: diagnostics,
        error: error,
        stackTrace: stack,
      );
      AppFailureRegistry.attach(error, failure);
      await hub.captureException(error, stackTrace: stack);
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      logger.e(
        'Request failed.',
        error: error,
        stackTrace: stack,
        failure: failure,
      );
      await AppLogger.flush();
      expect(transport.events, hasLength(1));
      final details = transport.events.single.contexts['app_log'] as Map;
      expect(details['statusCode'], 503);
      expect(details['requestId'], 'request-7');
      expect(details['reason'], 'Storage unavailable');
    },
  );

  test(
    'trace/debug bursts stay in console without consent reads or pending delivery',
    () async {
      var storageReads = 0;
      var attReads = 0;
      final consent = TelemetryConsent(
        isIos: true,
        readStoredStatus: () async {
          storageReads++;
          return authorized ? 'authorized' : 'denied';
        },
        readTrackingStatus: () async {
          attReads++;
          return TrackingStatus.authorized;
        },
      );
      sink = SentryLogSink(hub: hub, isAuthorized: consent.isAuthorized);
      sink.configureOptions(options);
      final console = _QuietSink();
      final logger = AppLogger(consoleSink: console, telemetrySink: sink);
      for (var i = 0; i < 1000; i++) {
        logger.t('Building dialect marker.');
        logger.d('Resolving marker colors.');
      }
      expect(console.records, hasLength(2000));
      expect(storageReads, 0);
      expect(attReads, 0);
      expect(sink.add(console.records.first), isNull);
      await AppLogger.flush();
      expect(storageReads, 0);
      expect(attReads, 0);

      logger.api(
        ApiDiagnostics.fromResponse(
          method: 'GET',
          uri: Uri.parse('https://api.example.test/recordings'),
          statusCode: 200,
          durationMs: 15,
        ),
      );
      await AppLogger.flush();
      logger.e('Unexpected error.', error: StateError('failure'));
      await AppLogger.flush();
      // One check for the API record, then one for the error and one before send.
      expect(storageReads, 3);
      expect(attReads, 3);
      final crumbs = transport.events.single.breadcrumbs!;
      expect(crumbs, hasLength(1));
      expect(crumbs.single.data!['statusCode'], 200);

      authorized = false;
      logger.e('Error after revocation.', error: StateError('revoked'));
      await AppLogger.flush();
      expect(storageReads, 4);
      expect(attReads, 3);
      expect(transport.events, hasLength(1));
    },
  );

  test('failure breadcrumbs survive trace/debug filtering', () async {
    final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
    logger.d('Preparing request failed.', error: StateError('bad input'));
    logger.t(
      'Request was cancelled.',
      error: StateError('cancelled'),
      expected: true,
    );
    await AppLogger.flush();
    logger.e('Unexpected error.', error: StateError('failure'));
    await AppLogger.flush();
    expect(transport.events.single.breadcrumbs!.map((crumb) => crumb.message), [
      'Preparing request failed.',
      'Request was cancelled.',
    ]);
  });

  test(
    'automatic events sanitize request and exceptions before transport',
    () async {
      await hub.captureEvent(
        SentryEvent(
          throwable: StateError('token=EXCEPTION_SECRET'),
          request: SentryRequest(
            url: 'https://api.example.test/path?token=URL_SECRET',
            data: {'recording': 'PRIVATE_AUDIO'},
            cookies: 'session=COOKIE_SECRET',
            headers: {'Authorization': 'Bearer HEADER_SECRET'},
          ),
        ),
        stackTrace: StackTrace.fromString(
          '#0 fail (package:strnadi/api.dart:81:9)',
        ),
      );
      final encoded = jsonEncode(transport.events.single.toJson());
      for (final secret in [
        'EXCEPTION_SECRET',
        'URL_SECRET',
        'PRIVATE_AUDIO',
        'COOKIE_SECRET',
        'HEADER_SECRET',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
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
        81,
      );
    },
  );

  test('consent hook failure explicitly drops an automatic event', () async {
    final failing = SentryLogSink(
      hub: hub,
      isAuthorized: () async => throw StateError('consent unavailable'),
    );
    expect(
      await failing.beforeSend(
        SentryEvent(throwable: StateError('token=DO_NOT_TRANSMIT')),
        Hint(),
      ),
      isNull,
    );
  });

  test(
    'denied and revoked consent blocks logger and automatic events',
    () async {
      final logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
      authorized = false;
      logger.e('Local error.', error: StateError('failure'));
      await AppLogger.flush();
      await hub.captureException(StateError('automatic'));
      expect(transport.events, isEmpty);
    },
  );
}
