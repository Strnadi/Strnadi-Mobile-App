import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localRecordings/recording_send_coordinator.dart';

void main() {
  group('recording send coordinator (all boundaries mocked)', () {
    test('rapid sends share one lookup and one scheduler operation', () async {
      final RecordingSendCoordinator coordinator = RecordingSendCoordinator();
      final Completer<bool> lookupResult = Completer<bool>();
      int lookupCalls = 0;
      int incompleteHandlerCalls = 0;
      int schedulerCalls = 0;
      int duplicateBoundaryCalls = 0;

      final Future<void> first = coordinator.send(
        hasIncompleteUpload: () {
          lookupCalls++;
          return lookupResult.future;
        },
        handleIncompleteUpload: () async {
          incompleteHandlerCalls++;
        },
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );
      final Future<void> second = coordinator.send(
        hasIncompleteUpload: () async {
          duplicateBoundaryCalls++;
          return false;
        },
        handleIncompleteUpload: () async {
          duplicateBoundaryCalls++;
        },
        scheduleUpload: () async {
          duplicateBoundaryCalls++;
        },
      );

      expect(second, same(first));
      expect(coordinator.isRunning, isTrue);
      expect(lookupCalls, 1);

      lookupResult.complete(false);
      await Future.wait(<Future<void>>[first, second]);

      expect(lookupCalls, 1);
      expect(incompleteHandlerCalls, 0);
      expect(schedulerCalls, 1);
      expect(duplicateBoundaryCalls, 0);
      expect(coordinator.isRunning, isFalse);
    });

    test('an incomplete upload is handled without scheduling a duplicate',
        () async {
      final RecordingSendCoordinator coordinator = RecordingSendCoordinator();
      int incompleteHandlerCalls = 0;
      int schedulerCalls = 0;

      await coordinator.send(
        hasIncompleteUpload: () async => true,
        handleIncompleteUpload: () async {
          incompleteHandlerCalls++;
        },
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );

      expect(incompleteHandlerCalls, 1);
      expect(schedulerCalls, 0);
      expect(coordinator.isRunning, isFalse);
    });

    test('lookup failure reaches every caller and unlocks a later retry',
        () async {
      final RecordingSendCoordinator coordinator = RecordingSendCoordinator();
      final StateError failure = StateError('mock DB lookup failed');
      final Completer<bool> lookup = Completer<bool>();
      int schedulerCalls = 0;

      final Future<void> first = coordinator.send(
        hasIncompleteUpload: () => lookup.future,
        handleIncompleteUpload: () async {},
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );
      final Future<void> second = coordinator.send(
        hasIncompleteUpload: () async => false,
        handleIncompleteUpload: () async {},
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );
      lookup.completeError(failure);

      await expectLater(first, throwsA(same(failure)));
      await expectLater(second, throwsA(same(failure)));
      expect(coordinator.isRunning, isFalse);
      expect(schedulerCalls, 0);

      await coordinator.send(
        hasIncompleteUpload: () async => false,
        handleIncompleteUpload: () async {},
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );
      expect(schedulerCalls, 1);
    });

    test('scheduler failure unlocks a later retry', () async {
      final RecordingSendCoordinator coordinator = RecordingSendCoordinator();
      final StateError failure = StateError('mock scheduler failed');
      int schedulerCalls = 0;

      await expectLater(
        coordinator.send(
          hasIncompleteUpload: () async => false,
          handleIncompleteUpload: () async {},
          scheduleUpload: () async {
            schedulerCalls++;
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      expect(coordinator.isRunning, isFalse);

      await coordinator.send(
        hasIncompleteUpload: () async => false,
        handleIncompleteUpload: () async {},
        scheduleUpload: () async {
          schedulerCalls++;
        },
      );
      expect(schedulerCalls, 2);
    });
  });
}
