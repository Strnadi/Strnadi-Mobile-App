import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/bootstrap/database_bootstrap.dart';
import 'package:strnadi/bootstrap/database_bootstrap_error_page.dart';

void main() {
  group('database bootstrap phase runner (all dependencies are fakes)', () {
    test('runs every phase in the required order', () async {
      final calls = <String>[];

      await runDatabaseBootstrap(
        openDatabase: () async => calls.add('open'),
        runPostMigrationBackfills: () async => calls.add('backfill'),
        enforceRecordingLimit: () async => calls.add('limit'),
        reconcileInterruptedUploads: () async => calls.add('reconcile'),
      );

      expect(calls, <String>['open', 'backfill', 'limit', 'reconcile']);
    });

    for (final failurePhase in DatabaseBootstrapPhase.values) {
      test('fails closed during ${failurePhase.name} and skips later phases',
          () async {
        final calls = <DatabaseBootstrapPhase>[];
        final failure = StateError('mock ${failurePhase.name} failure');

        Future<void> run(DatabaseBootstrapPhase phase) async {
          calls.add(phase);
          if (phase == failurePhase) throw failure;
        }

        final expectation = expectLater(
          runDatabaseBootstrap(
            openDatabase: () => run(DatabaseBootstrapPhase.openDatabase),
            runPostMigrationBackfills: () =>
                run(DatabaseBootstrapPhase.runPostMigrationBackfills),
            enforceRecordingLimit: () =>
                run(DatabaseBootstrapPhase.enforceRecordingLimit),
            reconcileInterruptedUploads: () =>
                run(DatabaseBootstrapPhase.reconcileInterruptedUploads),
          ),
          throwsA(
            isA<DatabaseBootstrapFailure>()
                .having((error) => error.phase, 'phase', failurePhase)
                .having((error) => error.cause, 'cause', same(failure))
                .having(
                  (error) => error.stackTrace.toString(),
                  'captured stack',
                  contains('database_bootstrap_test.dart'),
                ),
          ),
        );

        await expectation;
        expect(
          calls,
          DatabaseBootstrapPhase.values.take(failurePhase.index + 1).toList(),
        );
      });
    }

    test('a later retry starts from a clean first phase', () async {
      var attempts = 0;
      final calls = <String>[];

      Future<void> runAttempt() {
        attempts += 1;
        return runDatabaseBootstrap(
          openDatabase: () async => calls.add('$attempts:open'),
          runPostMigrationBackfills: () async {
            calls.add('$attempts:backfill');
            if (attempts == 1) throw StateError('mock migration failure');
          },
          enforceRecordingLimit: () async => calls.add('$attempts:limit'),
          reconcileInterruptedUploads: () async =>
              calls.add('$attempts:reconcile'),
        );
      }

      await expectLater(runAttempt(), throwsA(isA<DatabaseBootstrapFailure>()));
      await runAttempt();

      expect(calls, <String>[
        '1:open',
        '1:backfill',
        '2:open',
        '2:backfill',
        '2:limit',
        '2:reconcile',
      ]);
    });
  });

  group('database bootstrap recovery UI (callback is a fake)', () {
    testWidgets('shows a storage error and retries once while in flight',
        (tester) async {
      final retryCompleter = Completer<void>();
      var retryCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseBootstrapErrorPage(
            title: 'Storage unavailable',
            message: 'Recording data could not be prepared.',
            retryLabel: 'Try again',
            onRetry: () {
              retryCalls += 1;
              return retryCompleter.future;
            },
          ),
        ),
      );

      expect(find.text('Storage unavailable'), findsOneWidget);
      expect(
        find.text('Recording data could not be prepared.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(retryCalls, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);

      retryCompleter.complete();
      await tester.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('a failed retry is reported and can be attempted again',
        (tester) async {
      var retryCalls = 0;
      final failures = <Object>[];

      await tester.pumpWidget(
        MaterialApp(
          home: DatabaseBootstrapErrorPage(
            title: 'Storage unavailable',
            message: 'Please retry.',
            retryLabel: 'Retry',
            onRetry: () async {
              retryCalls += 1;
              throw StateError('mock database failure $retryCalls');
            },
            onRetryFailure: (error, _) => failures.add(error),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retryCalls, 1);
      expect(failures, hasLength(1));
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retryCalls, 2);
      expect(failures, hasLength(2));
    });
  });
}
