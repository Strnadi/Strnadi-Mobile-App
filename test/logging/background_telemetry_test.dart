import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/background_telemetry.dart';
import 'package:strnadi/logging/telemetry_consent.dart';

class _RecordingSink implements AppLogSink {
  final List<AppLogRecord> records = [];
  Completer<void>? pending;
  @override
  Future<void> add(AppLogRecord record) async {
    records.add(record);
    await pending?.future;
  }
}

TelemetryConsent _consent(bool authorized) => TelemetryConsent(
  isIos: false,
  readStoredStatus: () async => authorized ? 'authorized' : 'denied',
);

void main() {
  tearDown(AppLogger.configure);

  test(
    'callback borrows no foreground state and drains before closing its sink',
    () async {
      final global = _RecordingSink();
      final worker = _RecordingSink();
      AppLogger.configure(telemetrySink: global);
      var closed = false;
      final result = await runWithBackgroundTelemetry(
        operation: 'upload',
        consent: _consent(true),
        createSession: () async => BackgroundTelemetrySession(
          sink: worker,
          close: () async => closed = true,
        ),
        action: () async {
          AppLogger().i('Worker completed.');
          return 7;
        },
      );
      expect(result, 7);
      expect(closed, isTrue);
      expect(worker.records, hasLength(1));
      expect(global.records, isEmpty);
      AppLogger().i('Foreground remains active.');
      await AppLogger.flush();
      expect(global.records, hasLength(1));
    },
  );

  test(
    'denied consent disables inherited global telemetry without blocking work',
    () async {
      final global = _RecordingSink();
      AppLogger.configure(telemetrySink: global);
      var initialized = false;
      final result = await runWithBackgroundTelemetry(
        operation: 'upload',
        consent: _consent(false),
        createSession: () async {
          initialized = true;
          return BackgroundTelemetrySession(sink: global, close: () async {});
        },
        action: () async {
          AppLogger().i('Expected task result.');
          return false;
        },
      );
      expect(result, isFalse);
      expect(initialized, isFalse);
      expect(global.records, isEmpty);
    },
  );

  test(
    'original task failure survives sink timeout and shutdown error',
    () async {
      final worker = _RecordingSink()..pending = Completer<void>();
      final error = StateError('callback failed');
      var closed = false;
      await expectLater(
        runWithBackgroundTelemetry<void>(
          operation: 'upload',
          consent: _consent(true),
          drainTimeout: const Duration(milliseconds: 5),
          createSession: () async => BackgroundTelemetrySession(
            sink: worker,
            close: () async {
              closed = true;
              throw StateError('shutdown failed');
            },
          ),
          action: () async => throw error,
        ),
        throwsA(same(error)),
      );
      expect(worker.records.single.reason, isNotEmpty);
      expect(worker.records.single.stackTrace, isNotNull);
      expect(closed, isTrue);
      worker.pending!.complete();
    },
  );

  test('telemetry initialization error does not change retry result', () async {
    final result = await runWithBackgroundTelemetry(
      operation: 'upload',
      consent: _consent(true),
      createSession: () async => throw StateError('telemetry failed'),
      action: () async => false,
    );
    expect(result, isFalse);
  });

  test(
    'stalled platform release lookup cannot block the background action',
    () async {
      final metadata = Completer<PackageInfo>();
      var ran = false;
      final result = await runWithBackgroundTelemetry(
        operation: 'upload',
        consent: _consent(true),
        readPackageInfo: () => metadata.future,
        metadataTimeout: const Duration(milliseconds: 5),
        action: () async {
          ran = true;
          return false;
        },
      );
      expect(ran, isTrue);
      expect(result, isFalse);
      metadata.complete(
        PackageInfo(
          appName: 'test',
          packageName: 'test',
          version: '1',
          buildNumber: '1',
        ),
      );
    },
  );
}
