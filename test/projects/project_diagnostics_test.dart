import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/telemetry_session.dart';
import 'package:strnadi/projects/project_diagnostics.dart';

class _Sink implements AppLogSink {
  final records = <AppLogRecord>[];
  bool fail = false;
  @override
  void add(AppLogRecord record) {
    if (fail) throw StateError('logging unavailable');
    records.add(record);
  }
}

void main() {
  late _Sink sink;
  setUp(() {
    sink = _Sink();
    AppLogger.configure(telemetrySink: sink);
  });
  tearDown(() => AppLogger.configure());

  test(
    'nested operations have correlated starts, counts, duration and completion',
    () async {
      final result = await ProjectDiagnostics.run(
        ProjectOperation.discover,
        () => ProjectDiagnostics.run(
          ProjectOperation.discoverMemberships,
          () async {
            ProjectDiagnostics.event(ProjectEvent.discovered, count: 2);
            return ['private project name', 'private project identifier'];
          },
        ),
      );
      expect(result.length, 2);
      expect(sink.records.length, 5);
      final root = sink.records.first.context['operationId'];
      expect(sink.records[1].context['parentOperationId'], root);
      expect(sink.records[2].context['count'], 2);
      expect(sink.records.last.context['durationMs'], isNonNegative);
      expect(sink.records.last.context['operationId'], root);
      expect(sink.records.last.message, 'Project operation completed.');
    },
  );

  test(
    'unexpected failure preserves error and stack without logging arbitrary contents',
    () async {
      const secret =
          'private-project-name-private-email@example.test-secret-token';
      final error = StateError(secret);
      final stack = StackTrace.current;
      Object? observed;
      StackTrace? observedStack;
      try {
        await ProjectDiagnostics.run(
          ProjectOperation.join,
          () async => Error.throwWithStackTrace(error, stack),
        );
      } catch (caught, caughtStack) {
        observed = caught;
        observedStack = caughtStack;
      }
      expect(observed, same(error));
      expect(observedStack.toString(), stack.toString());
      final record = sink.records.last;
      expect(record.level, AppLogLevel.error);
      expect(record.context['category'], 'unexpected');
      expect(record.context['exceptionType'], 'StateError');
      expect(record.stackTrace, isNotNull);
      final serialized = jsonEncode(
        sink.records
            .map(
              (r) => {
                'message': r.message,
                'reason': r.reason,
                'error': r.errorDescription,
                'context': r.context,
                'stack': r.stackTrace.toString(),
              },
            )
            .toList(),
      );
      expect(serialized, isNot(contains(secret)));
      expect(serialized, isNot(contains('private-project-name')));
      expect(
        sink.records.where((r) => r.message.contains('completed')),
        isEmpty,
      );
    },
  );

  test(
    'denial is classified as expected and nested failures share telemetry occurrence',
    () async {
      await expectLater(
        ProjectDiagnostics.run(
          ProjectOperation.join,
          () => ProjectDiagnostics.run(
            ProjectOperation.joinMembership,
            () async =>
                throw const OAuthFailure(OAuthFailureKind.exchangeDenied),
          ),
        ),
        throwsA(isA<OAuthFailure>()),
      );
      final rejected = sink.records
          .where((r) => r.level == AppLogLevel.warning)
          .toList();
      expect(rejected.length, 2);
      expect(rejected.first.context['category'], 'exchangeDenied');
      expect(rejected.first.failure!.expected, true);
      expect(rejected.last.failure, same(rejected.first.failure));
    },
  );

  test('late results cannot log into the next telemetry session', () async {
    final pending = Completer<void>();
    final operation = ProjectDiagnostics.run(
      ProjectOperation.catalog,
      () async {
        await pending.future;
        ProjectDiagnostics.event(ProjectEvent.catalogLoaded, count: 7);
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      },
    );
    final assertion = expectLater(operation, throwsA(isA<OAuthFailure>()));
    TelemetrySession.foreground.reset();
    pending.complete();
    await assertion;
    expect(sink.records.length, 1);
    ProjectDiagnostics.activated();
    expect(sink.records.last.context, {'event': 'sessionActivated'});
  });

  test('logging failure cannot change an operation result or error', () async {
    sink.fail = true;
    expect(
      await ProjectDiagnostics.run(ProjectOperation.catalog, () async => 42),
      42,
    );
    final failure = StateError('original');
    await expectLater(
      ProjectDiagnostics.run(ProjectOperation.join, () async => throw failure),
      throwsA(same(failure)),
    );
  });
}
