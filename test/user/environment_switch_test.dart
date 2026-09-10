import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/config/host_environment.dart';
import 'package:strnadi/user/logout_safety.dart';

void main() {
  for (final source in HostEnvironment.values) {
    for (final target
        in HostEnvironment.values.where((value) => value != source)) {
      test('$source -> $target keeps cleanup on old host and clears auth first',
          () async {
        var active = source;
        String? token = 'old-token';
        final events = <String>[];
        final releaseCleanup = Completer<void>();
        final cleanupStarted = Completer<void>();
        final cleanup = runOrderedLogoutCleanup(
          captureLogoutEvent: () async => events.add('capture'),
          resetAnalyticsIdentity: () async => events.add('reset'),
          deleteDeviceToken: () async {
            expect(active, source);
            expect(token, 'old-token');
            cleanupStarted.complete();
            await releaseCleanup.future;
            events.add('delete-device');
          },
          clearAuthSession: () async {
            expect(active, source);
            token = null;
            events.add('clear-auth');
          },
          signOutIdentityProvider: () async => events.add('provider'),
          afterCleanup: () async {
            expect(token, isNull);
            active = target;
            events.add('switch');
          },
        );
        await cleanupStarted.future;
        expect(active, source);
        releaseCleanup.complete();
        await cleanup;
        events.add('navigate');
        expect(active, target);
        expect(events, [
          'capture',
          'reset',
          'delete-device',
          'clear-auth',
          'provider',
          'switch',
          'navigate'
        ]);
      });
    }
  }

  for (final failure in ['capture', 'reset', 'device', 'auth', 'provider']) {
    test('$failure failure cannot switch with old credentials', () async {
      var switched = false;
      Future<void> step(String stage) async {
        if (stage == failure) throw StateError('mock failure');
      }

      await expectLater(
          runOrderedLogoutCleanup(
            captureLogoutEvent: () => step('capture'),
            resetAnalyticsIdentity: () => step('reset'),
            deleteDeviceToken: () => step('device'),
            clearAuthSession: () => step('auth'),
            signOutIdentityProvider: () => step('provider'),
            afterCleanup: () async => switched = true,
          ),
          throwsStateError);
      expect(switched, isFalse);
    });
  }
}
