import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/api/api_logging.dart';
import 'package:strnadi/api/controllers/filtered_recordings_controller.dart';
import 'package:strnadi/dialects/ModelHandler.dart' as model;
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/sentry_log_sink.dart';

const _recordingId = 918273645;
const _dialectId = 837261549;
const _startDate = '2042-11-23T12:34:56.789Z';
const _endDate = '2042-11-23T12:35:26.789Z';
const _guess = 'PRIVATE_DIALECT_GUESS';
const _confirmed = 'PRIVATE_DIALECT_RESULT';
const _rawPayload = 'PRIVATE_BACKEND_PAYLOAD';

Map<String, Object?> _recording() => {
  'recordingId': _recordingId,
  'startDate': _startDate,
  'endDate': _endDate,
  'detectedDialects': [
    {
      'id': _dialectId,
      'userGuessDialect': _guess,
      'confirmedDialect': _confirmed,
    },
  ],
  'unrecognizedPayload': _rawPayload,
};

void main() {
  late _Console console;
  late _Transport transport;
  late Hub hub;
  late AppLogger logger;
  late Dio dio;
  late _Controller controller;

  setUp(() {
    console = _Console();
    transport = _Transport();
    final options = SentryOptions()
      ..dsn = 'https://public@example.test/1'
      ..transport = transport
      ..sendClientReports = false;
    hub = Hub(options);
    final sink = SentryLogSink(hub: hub, isAuthorized: () async => true);
    sink.configureOptions(options);
    logger = AppLogger(
      scope: 'dialects.ModelHandler',
      consoleSink: console,
      telemetrySink: sink,
    );
    dio = Dio(BaseOptions(validateStatus: (_) => true));
    installApiLogging(dio, logger);
    controller = _Controller(dio);
  });

  tearDown(() async {
    dio.close(force: true);
    await hub.close();
    AppLogger.configure();
  });

  void expectNoPayload() {
    final output = jsonEncode({
      'console': console.records
          .map(
            (record) => {
              'message': record.message,
              'reason': record.reason,
              'error': record.errorDescription,
              'context': record.context,
              'stackTrace': record.stackTrace?.toString(),
            },
          )
          .toList(),
      'sentry': transport.events.map((event) => event.toJson()).toList(),
    });
    for (final value in [
      '$_recordingId',
      '$_dialectId',
      _startDate,
      _endDate,
      _guess,
      _confirmed,
      _rawPayload,
    ]) {
      expect(output, isNot(contains(value)), reason: 'Payload value leaked');
    }
  }

  Future<void> captureBreadcrumbs() async {
    logger.e('Independent test failure.', error: StateError('test failure'));
    await AppLogger.flush();
  }

  test('successful parser logs only structural counts to both sinks', () async {
    final result = model.dialectsFromBEJson(
      [_recording()],
      recordingId: _recordingId,
      diagnosticsLogger: logger,
    );

    expect(result, hasLength(1));
    expect(result.single.BEID, _dialectId);
    expect(result.single.recordingId, _recordingId);
    expect(result.single.recordingBEID, _recordingId);
    expect(result.single.userGuessDialect, _guess);
    expect(result.single.adminDialect, _confirmed);
    expect(result.single.startDate, DateTime.parse(_startDate));
    expect(result.single.endDate, DateTime.parse(_endDate));
    expect(console.records.map((record) => record.context), [
      {'recordCount': 1},
      {'recordCount': 1, 'dialectCount': 1},
    ]);
    await AppLogger.flush();
    expect(transport.events, isEmpty);
    await captureBreadcrumbs();
    final crumbs = transport.events.single.breadcrumbs!;
    expect(crumbs, hasLength(2));
    expect(crumbs.last.data!['recordCount'], 1);
    expect(crumbs.last.data!['dialectCount'], 1);
    expectNoPayload();
  });

  test(
    'successful HTTP fetch keeps status while omitting recording values',
    () async {
      dio.httpClientAdapter = _Adapter(200, [_recording()]);
      final result = await model.fetchRecordingDialects(
        _recordingId,
        controller: controller,
        diagnosticsLogger: logger,
      );

      expect(result, hasLength(1));
      expect(result.single.recordingBEID, _recordingId);
      expect(controller.requestedRecordingId, _recordingId);
      expect(controller.requestedVerified, isFalse);
      expect(
        console.records.any((record) => record.context['statusCode'] == 200),
        isTrue,
      );
      await AppLogger.flush();
      expect(transport.events, isEmpty);
      await captureBreadcrumbs();
      expect(
        transport.events.single.breadcrumbs!.any(
          (crumb) => crumb.data?['statusCode'] == 200,
        ),
        isTrue,
      );
      expectNoPayload();
    },
  );

  for (final status in [400, 503]) {
    test(
      'HTTP $status preserves source occurrence and excludes raw body',
      () async {
        dio.httpClientAdapter = _Adapter(status, {
          ..._recording(),
          'reason': 'dialect_request_failed',
        });
        final result = await model.fetchRecordingDialects(
          _recordingId,
          controller: controller,
          diagnosticsLogger: logger,
        );
        await AppLogger.flush();

        expect(result, isEmpty);
        final failure = apiFailureForResponse(controller.response!);
        final reported = console.records
            .where((record) => record.failure != null)
            .toList();
        expect(reported, hasLength(2));
        expect(
          reported.every((record) => identical(record.failure, failure)),
          isTrue,
        );
        expect(
          reported.every((record) => record.context['statusCode'] == status),
          isTrue,
        );
        expect(
          reported.every((record) => record.reason == 'dialect_request_failed'),
          isTrue,
        );
        expect(failure.expected, status == 400);

        if (status == 400) {
          expect(transport.events, isEmpty);
          await captureBreadcrumbs();
          final failures = transport.events.single.breadcrumbs!.where(
            (crumb) => crumb.data?['statusCode'] == status,
          );
          expect(failures, hasLength(2));
          expect(
            failures.every(
              (crumb) => crumb.data?['reason'] == 'dialect_request_failed',
            ),
            isTrue,
          );
        } else {
          expect(transport.events, hasLength(1));
          final context = transport.events.single.contexts['app_log'] as Map;
          expect(context['statusCode'], status);
          expect(context['reason'], 'dialect_request_failed');
        }
        expectNoPayload();
      },
    );
  }
}

class _Console implements AppLogSink {
  final records = <AppLogRecord>[];

  @override
  void add(AppLogRecord record) => records.add(record);
}

class _Transport extends Transport {
  final events = <SentryEvent>[];

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

class _Controller extends FilteredRecordingsController {
  _Controller(this.dio);

  final Dio dio;
  Response<dynamic>? response;
  int? requestedRecordingId;
  bool? requestedVerified;

  @override
  Future<Response<dynamic>> fetchFilteredParts({
    int? recordingId,
    bool? verified,
    String? accessToken,
    String? host,
  }) async {
    requestedRecordingId = recordingId;
    requestedVerified = verified;
    return response = await dio.get<dynamic>(
      'https://example.test/recordings/filtered',
      queryParameters: {'recordingId': recordingId, 'verified': verified},
    );
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.payload);

  final int status;
  final Object payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}
