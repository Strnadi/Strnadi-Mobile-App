import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/user/logout_safety.dart';

void main() {
  test('waits for delayed logout capture before resetting identity', () async {
    final Completer<void> captureRelease = Completer<void>();
    final Completer<void> resetRelease = Completer<void>();
    final List<String> events = <String>[];

    final Future<void> cleanup = runOrderedLogoutCleanup(
      captureLogoutEvent: () async {
        events.add('capture:start');
        await captureRelease.future;
        events.add('capture:end');
      },
      resetAnalyticsIdentity: () async {
        events.add('reset:start');
        await resetRelease.future;
        events.add('reset:end');
      },
      deleteDeviceToken: () async => events.add('device-token'),
      clearAuthSession: () async => events.add('clear-auth'),
      signOutIdentityProvider: () async => events.add('provider-sign-out'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['capture:start']);

    captureRelease.complete();
    await Future<void>.delayed(Duration.zero);
    expect(
      events,
      <String>['capture:start', 'capture:end', 'reset:start'],
    );
    expect(events, isNot(contains('clear-auth')));

    resetRelease.complete();
    await cleanup;
    expect(events, <String>[
      'capture:start',
      'capture:end',
      'reset:start',
      'reset:end',
      'device-token',
      'clear-auth',
      'provider-sign-out',
    ]);
  });

  test('cleanup does not overlap or reorder asynchronous stages', () async {
    int activeStages = 0;
    int maxActiveStages = 0;
    final List<int> completed = <int>[];

    Future<void> stage(int value) async {
      activeStages++;
      if (activeStages > maxActiveStages) maxActiveStages = activeStages;
      await Future<void>.delayed(Duration.zero);
      completed.add(value);
      activeStages--;
    }

    await runOrderedLogoutCleanup(
      captureLogoutEvent: () => stage(1),
      resetAnalyticsIdentity: () => stage(2),
      deleteDeviceToken: () => stage(3),
      clearAuthSession: () => stage(4),
      signOutIdentityProvider: () => stage(5),
    );

    expect(completed, <int>[1, 2, 3, 4, 5]);
    expect(maxActiveStages, 1);
  });

  test('logout ordering tests cannot use a real API or database', () {
    final String source =
        File('test/user/logout_safety_test.dart').readAsStringSync();
    expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
    expect(source, isNot(contains(<String>['open', 'Database('].join())));
    expect(source, isNot(contains(<String>['Database', 'New'].join())));
  });
}
