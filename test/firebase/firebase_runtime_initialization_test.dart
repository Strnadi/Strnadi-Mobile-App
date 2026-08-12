import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/firebase/firebase_runtime_initialization.dart';

void main() {
  group('Firebase runtime initialization (injected fakes only)', () {
    test('core registration waits for Firebase app initialization', () async {
      final List<String> calls = <String>[];
      final Completer<void> initialized = Completer<void>();

      final Future<void> result = initializeFirebaseCoreRuntime(
        initializeApp: () async {
          calls.add('firebase:start');
          await initialized.future;
          calls.add('firebase:end');
        },
        registerBackgroundHandler: () {
          calls.add('handler');
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['firebase:start']);
      initialized.complete();
      await result;
      expect(calls, <String>['firebase:start', 'firebase:end', 'handler']);
    });

    test('core failure never registers a handler against partial state',
        () async {
      int registrations = 0;

      await expectLater(
        initializeFirebaseCoreRuntime(
          initializeApp: () async {
            throw StateError('mock Firebase core failure');
          },
          registerBackgroundHandler: () {
            registrations += 1;
          },
        ),
        throwsStateError,
      );

      expect(registrations, 0);
    });

    test('notification layers run in deterministic local-then-messaging order',
        () async {
      final List<String> calls = <String>[];

      final NotificationRuntimeInitializationResult result =
          await initializeNotificationRuntime(
        initializeLocalNotifications: () async {
          calls.add('local');
        },
        initializeMessaging: () async {
          calls.add('messaging');
        },
      );

      expect(calls, <String>['local', 'messaging']);
      expect(result.fullyInitialized, isTrue);
    });

    test('messaging waits until local initialization settles', () async {
      final List<String> calls = <String>[];
      final Completer<void> local = Completer<void>();

      final Future<NotificationRuntimeInitializationResult> initialization =
          initializeNotificationRuntime(
        initializeLocalNotifications: () async {
          calls.add('local:start');
          await local.future;
          calls.add('local:end');
        },
        initializeMessaging: () async {
          calls.add('messaging');
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['local:start']);
      local.complete();
      expect((await initialization).fullyInitialized, isTrue);
      expect(calls, <String>['local:start', 'local:end', 'messaging']);
    });

    test('local plugin failure is observed but messaging is still attempted',
        () async {
      int messagingCalls = 0;

      final NotificationRuntimeInitializationResult result =
          await initializeNotificationRuntime(
        initializeLocalNotifications: () async {
          throw StateError('mock local plugin failure');
        },
        initializeMessaging: () async {
          messagingCalls += 1;
        },
      );

      expect(messagingCalls, 1);
      expect(result.localNotificationsInitialized, isFalse);
      expect(result.messagingInitialized, isTrue);
      expect(result.localNotificationsError, isA<StateError>());
    });

    test('captures messaging failure after successful local initialization',
        () async {
      final NotificationRuntimeInitializationResult result =
          await initializeNotificationRuntime(
        initializeLocalNotifications: () async {},
        initializeMessaging: () async {
          throw StateError('mock messaging failure');
        },
      );

      expect(result.localNotificationsInitialized, isTrue);
      expect(result.messagingInitialized, isFalse);
      expect(result.messagingError, isA<StateError>());
    });

    test('captures both failures without creating unobserved futures',
        () async {
      final NotificationRuntimeInitializationResult result =
          await initializeNotificationRuntime(
        initializeLocalNotifications: () async {
          throw ArgumentError('mock local');
        },
        initializeMessaging: () async {
          throw StateError('mock messaging');
        },
      );

      expect(result.fullyInitialized, isFalse);
      expect(result.localNotificationsError, isA<ArgumentError>());
      expect(result.messagingError, isA<StateError>());
    });
  });
}
