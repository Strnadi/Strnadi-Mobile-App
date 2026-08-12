import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/firebase/foreground_notification_delivery.dart';

void main() {
  group('deliverForegroundNotification (injected fakes only)', () {
    test('awaits presentation and then persists the same delivery', () async {
      final List<String> calls = <String>[];
      final Completer<void> display = Completer<void>();
      final Completer<void> persist = Completer<void>();

      final Future<ForegroundNotificationDeliveryResult> delivery =
          deliverForegroundNotification(
        display: () async {
          calls.add('display:start');
          await display.future;
          calls.add('display:end');
        },
        persist: () async {
          calls.add('persist:start');
          await persist.future;
          calls.add('persist:end');
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['display:start']);

      display.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        calls,
        <String>['display:start', 'display:end', 'persist:start'],
      );

      persist.complete();
      final ForegroundNotificationDeliveryResult result = await delivery;
      expect(result.fullyDelivered, isTrue);
      expect(
        calls,
        <String>[
          'display:start',
          'display:end',
          'persist:start',
          'persist:end',
        ],
      );
    });

    test('a display failure cannot suppress persistence', () async {
      int persistenceCalls = 0;

      final ForegroundNotificationDeliveryResult result =
          await deliverForegroundNotification(
        display: () async => throw StateError('mock display failure'),
        persist: () async {
          persistenceCalls += 1;
        },
      );

      expect(persistenceCalls, 1);
      expect(result.displayed, isFalse);
      expect(result.persisted, isTrue);
      expect(result.displayError, isA<StateError>());
      expect(result.persistenceError, isNull);
    });

    test('a persistence failure is returned after successful display',
        () async {
      int displayCalls = 0;

      final ForegroundNotificationDeliveryResult result =
          await deliverForegroundNotification(
        display: () async {
          displayCalls += 1;
        },
        persist: () async => throw StateError('mock persistence failure'),
      );

      expect(displayCalls, 1);
      expect(result.displayed, isTrue);
      expect(result.persisted, isFalse);
      expect(result.persistenceError, isA<StateError>());
    });

    test('contains two independent failures without throwing', () async {
      final ForegroundNotificationDeliveryResult result =
          await deliverForegroundNotification(
        display: () async => throw ArgumentError('mock display'),
        persist: () async => throw StateError('mock persistence'),
      );

      expect(result.fullyDelivered, isFalse);
      expect(result.displayError, isA<ArgumentError>());
      expect(result.persistenceError, isA<StateError>());
    });

    test('supports a data-only no-op display while still persisting', () async {
      final List<String> calls = <String>[];

      final ForegroundNotificationDeliveryResult result =
          await deliverForegroundNotification(
        display: () async {
          calls.add('no-op-display');
        },
        persist: () async {
          calls.add('persist');
        },
      );

      expect(calls, <String>['no-op-display', 'persist']);
      expect(result.fullyDelivered, isTrue);
    });
  });
}
