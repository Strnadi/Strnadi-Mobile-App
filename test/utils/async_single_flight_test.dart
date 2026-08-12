import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/utils/async_single_flight.dart';

void main() {
  group('AsyncSingleFlight', () {
    test('coalesces rapid calls into the exact same operation', () async {
      final AsyncSingleFlight gate = AsyncSingleFlight();
      final Completer<void> release = Completer<void>();
      int calls = 0;

      final Future<void> first = gate.run(() async {
        calls++;
        await release.future;
      });
      final Future<void> second = gate.run(() async {
        calls++;
      });

      expect(second, same(first));
      expect(gate.isRunning, isTrue);
      expect(calls, 1);

      release.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(gate.isRunning, isFalse);
      expect(calls, 1);
    });

    test('blocks synchronous re-entry before operation first awaits', () async {
      final AsyncSingleFlight gate = AsyncSingleFlight();
      Future<void>? nested;
      int calls = 0;

      final Future<void> outer = gate.run(() async {
        calls++;
        nested = gate.run(() async {
          calls++;
        });
      });

      await outer;
      expect(nested, same(outer));
      expect(calls, 1);
      expect(gate.isRunning, isFalse);
    });

    test('unlocks after failure and preserves the original error', () async {
      final AsyncSingleFlight gate = AsyncSingleFlight();
      final StateError failure = StateError('mock upload failed');
      int calls = 0;

      final Future<void> first = gate.run(() async {
        calls++;
        throw failure;
      });
      final Future<void> second = gate.run(() async {
        calls++;
      });

      await expectLater(first, throwsA(same(failure)));
      await expectLater(second, throwsA(same(failure)));
      expect(gate.isRunning, isFalse);

      await gate.run(() async {
        calls++;
      });
      expect(calls, 2);
    });

    test('sequential calls still execute independently', () async {
      final AsyncSingleFlight gate = AsyncSingleFlight();
      int calls = 0;

      await gate.run(() async {
        calls++;
      });
      await gate.run(() async {
        calls++;
      });

      expect(calls, 2);
    });
  });
}
