import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/user/connected_platforms_logic.dart';

void main() {
  const ConnectedAccountSession session = ConnectedAccountSession(
    userId: 42,
    accessToken: 'mock-token',
    sessionId: 'mock-session',
    host: 'mock.invalid',
    verified: true,
  );

  group('provider status classification', () {
    test('accepts only explicit connected and disconnected statuses', () {
      expect(
        classifyConnectedProviderStatus(200),
        ConnectedProviderState.connected,
      );
      expect(
        classifyConnectedProviderStatus(204),
        ConnectedProviderState.disconnected,
      );
      expect(
        classifyConnectedProviderStatus(404),
        ConnectedProviderState.disconnected,
      );
      for (final int? status in <int?>[null, 0, 401, 403, 422, 500]) {
        expect(
          () => classifyConnectedProviderStatus(status),
          throwsA(isA<ConnectedAccountsException>()),
        );
      }
    });
  });

  group('ConnectedPlatformsCoordinator', () {
    test('derives both mocked calls from one verified captured owner',
        () async {
      final List<String> calls = <String>[];
      final ConnectedPlatformsCoordinator coordinator =
          ConnectedPlatformsCoordinator(
        captureSession: () async => session,
        isSessionCurrent: (ConnectedAccountSession observed) async {
          calls.add('current:${observed.sessionId}');
          return true;
        },
      );

      final ConnectedPlatformsStatus result = await coordinator.load(
        checkApple: (ConnectedAccountSession observed) async {
          calls.add(
            'apple:${observed.userId}:${observed.accessToken}:${observed.host}',
          );
          return 200;
        },
        checkGoogle: (ConnectedAccountSession observed) async {
          calls.add(
            'google:${observed.userId}:${observed.accessToken}:${observed.host}',
          );
          return 404;
        },
      );

      expect(result.apple, ConnectedProviderState.connected);
      expect(result.google, ConnectedProviderState.disconnected);
      expect(
        calls,
        containsAll(<String>[
          'apple:42:mock-token:mock.invalid',
          'google:42:mock-token:mock.invalid',
          'current:mock-session',
        ]),
      );
    });

    test('rejects missing, unverified, and invalid sessions before requests',
        () async {
      for (final ConnectedAccountSession? invalid in <ConnectedAccountSession?>[
        null,
        const ConnectedAccountSession(
          userId: 42,
          accessToken: 'mock-token',
          sessionId: 'mock-session',
          host: 'mock.invalid',
          verified: false,
        ),
        const ConnectedAccountSession(
          userId: 0,
          accessToken: 'mock-token',
          sessionId: 'mock-session',
          host: 'mock.invalid',
          verified: true,
        ),
      ]) {
        int requests = 0;
        final ConnectedPlatformsCoordinator coordinator =
            ConnectedPlatformsCoordinator(
          captureSession: () async => invalid,
          isSessionCurrent: (_) async => true,
        );

        await expectLater(
          coordinator.load(
            checkApple: (_) async {
              requests++;
              return 200;
            },
            checkGoogle: (_) async {
              requests++;
              return 200;
            },
          ),
          throwsA(isA<ConnectedAccountsException>()),
        );
        expect(requests, 0);
      }
    });

    test('rejects stale results after an account switch', () async {
      final Completer<int?> release = Completer<int?>();
      final ConnectedPlatformsCoordinator coordinator =
          ConnectedPlatformsCoordinator(
        captureSession: () async => session,
        isSessionCurrent: (_) async => false,
      );

      final Future<ConnectedPlatformsStatus> future = coordinator.load(
        checkApple: (_) => release.future,
        checkGoogle: (_) async => 200,
      );
      release.complete(200);

      await expectLater(
        future,
        throwsA(isA<ConnectedAccountsException>()),
      );
    });

    test('server and authentication failures are not shown as disconnected',
        () async {
      final ConnectedPlatformsCoordinator coordinator =
          ConnectedPlatformsCoordinator(
        captureSession: () async => session,
        isSessionCurrent: (_) async => true,
      );

      for (final int failureStatus in <int>[401, 403, 500]) {
        await expectLater(
          coordinator.load(
            checkApple: (_) async => failureStatus,
            checkGoogle: (_) async => 200,
          ),
          throwsA(isA<ConnectedAccountsException>()),
        );
      }
    });

    test('provider exceptions complete with failure instead of hanging',
        () async {
      final ConnectedPlatformsCoordinator coordinator =
          ConnectedPlatformsCoordinator(
        captureSession: () async => session,
        isSessionCurrent: (_) async => true,
      );

      await expectLater(
        coordinator
            .load(
              checkApple: (_) async =>
                  throw StateError('mock provider failure'),
              checkGoogle: (_) async => 200,
            )
            .timeout(const Duration(seconds: 1)),
        throwsA(isA<StateError>()),
      );
    });

    test('link success is accepted only while captured session is current',
        () async {
      for (final bool current in <bool>[true, false]) {
        final ConnectedPlatformsCoordinator coordinator =
            ConnectedPlatformsCoordinator(
          captureSession: () async => session,
          isSessionCurrent: (_) async => current,
        );
        expect(
          await coordinator.connect(connectProvider: (_) async => 200),
          current,
        );
      }
    });

    test('cancelled or failed links do not revalidate or become connected',
        () async {
      int currentChecks = 0;
      final ConnectedPlatformsCoordinator coordinator =
          ConnectedPlatformsCoordinator(
        captureSession: () async => session,
        isSessionCurrent: (_) async {
          currentChecks++;
          return true;
        },
      );

      expect(
        await coordinator.connect(connectProvider: (_) async => 409),
        isFalse,
      );
      expect(currentChecks, 0);
    });
  });

  test('connected-platform tests cannot use a real API or database', () {
    final String source = File('test/user/connected_platforms_logic_test.dart')
        .readAsStringSync();
    expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
    expect(source, isNot(contains(<String>['open', 'Database('].join())));
    expect(source, isNot(contains(<String>['Database', 'New'].join())));
    expect(source, isNot(contains(<String>['Auth', 'Controller'].join())));
  });
}
