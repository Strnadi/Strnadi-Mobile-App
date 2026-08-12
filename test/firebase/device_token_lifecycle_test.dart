import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/firebase/device_token_lifecycle.dart';

void main() {
  group('resolveDeviceTokenRefreshAction', () {
    test('does nothing when neither side has a token', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: null,
          currentToken: null,
        ),
        DeviceTokenRefreshAction.none,
      );
    });

    test('does nothing for blank token values', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: ' ',
          currentToken: '\n',
        ),
        DeviceTokenRefreshAction.none,
      );
    });

    test('registers when only the current token exists', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: null,
          currentToken: 'new-token',
        ),
        DeviceTokenRefreshAction.register,
      );
    });

    test('removes when a stored token no longer has a current token', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: 'old-token',
          currentToken: null,
        ),
        DeviceTokenRefreshAction.remove,
      );
    });

    test('does nothing when normalized tokens match', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: ' token ',
          currentToken: 'token',
        ),
        DeviceTokenRefreshAction.none,
      );
    });

    test('updates when both non-empty tokens differ', () {
      expect(
        resolveDeviceTokenRefreshAction(
          storedToken: 'old-token',
          currentToken: 'new-token',
        ),
        DeviceTokenRefreshAction.update,
      );
    });
  });

  group('cleanUpDeviceToken (mock remote API and local stores)', () {
    test('deletes remote registration before invalidating local state',
        () async {
      final List<String> calls = <String>[];

      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: 'stored-token',
        deleteRemote: (String token) async {
          calls.add('remote:$token');
          return 200;
        },
        invalidateMessagingToken: () async {
          calls.add('messaging');
        },
        deleteStoredToken: () async {
          calls.add('storage');
        },
      );

      expect(calls, <String>['remote:stored-token', 'messaging', 'storage']);
      expect(result.remoteAttempted, isTrue);
      expect(result.remoteDeleted, isTrue);
      expect(result.messagingTokenInvalidated, isTrue);
      expect(result.storedTokenDeleted, isTrue);
      expect(result.fullyCleaned, isTrue);
    });

    for (final int successfulStatus in <int>[200, 202, 204, 404]) {
      test('accepts remote status $successfulStatus as cleaned', () async {
        final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
          storedToken: 'stored-token',
          deleteRemote: (_) async => successfulStatus,
          invalidateMessagingToken: () async {},
          deleteStoredToken: () async {},
        );

        expect(result.remoteDeleted, isTrue);
        expect(result.fullyCleaned, isTrue);
      });
    }

    test('still invalidates local state when the mocked API rejects deletion',
        () async {
      final List<String> calls = <String>[];

      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: 'stored-token',
        deleteRemote: (_) async {
          calls.add('remote');
          return 500;
        },
        invalidateMessagingToken: () async {
          calls.add('messaging');
        },
        deleteStoredToken: () async {
          calls.add('storage');
        },
      );

      expect(calls, <String>['remote', 'messaging', 'storage']);
      expect(result.remoteDeleted, isFalse);
      expect(result.messagingTokenInvalidated, isTrue);
      expect(result.storedTokenDeleted, isTrue);
      expect(result.fullyCleaned, isFalse);
    });

    test('still invalidates local state when the mocked API throws', () async {
      final List<String> calls = <String>[];

      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: 'stored-token',
        deleteRemote: (_) async {
          calls.add('remote');
          throw StateError('mock network failure');
        },
        invalidateMessagingToken: () async {
          calls.add('messaging');
        },
        deleteStoredToken: () async {
          calls.add('storage');
        },
      );

      expect(calls, <String>['remote', 'messaging', 'storage']);
      expect(result.remoteDeleted, isFalse);
      expect(result.messagingTokenInvalidated, isTrue);
      expect(result.storedTokenDeleted, isTrue);
    });

    test('skips the mocked API but invalidates Firebase when storage is empty',
        () async {
      int remoteCalls = 0;
      int messagingCalls = 0;
      int storageCalls = 0;

      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: null,
        deleteRemote: (_) async {
          remoteCalls += 1;
          return 200;
        },
        invalidateMessagingToken: () async {
          messagingCalls += 1;
        },
        deleteStoredToken: () async {
          storageCalls += 1;
        },
      );

      expect(remoteCalls, 0);
      expect(messagingCalls, 1);
      expect(storageCalls, 1);
      expect(result.remoteAttempted, isFalse);
      expect(result.fullyCleaned, isTrue);
    });

    test('storage deletion still runs when Firebase invalidation throws',
        () async {
      int storageCalls = 0;

      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: 'stored-token',
        deleteRemote: (_) async => 200,
        invalidateMessagingToken: () async {
          throw StateError('mock Firebase failure');
        },
        deleteStoredToken: () async {
          storageCalls += 1;
        },
      );

      expect(storageCalls, 1);
      expect(result.messagingTokenInvalidated, isFalse);
      expect(result.storedTokenDeleted, isTrue);
      expect(result.fullyCleaned, isFalse);
    });

    test('reports a mocked secure-storage deletion failure', () async {
      final DeviceTokenCleanupResult result = await cleanUpDeviceToken(
        storedToken: 'stored-token',
        deleteRemote: (_) async => 200,
        invalidateMessagingToken: () async {},
        deleteStoredToken: () async {
          throw StateError('mock storage failure');
        },
      );

      expect(result.remoteDeleted, isTrue);
      expect(result.messagingTokenInvalidated, isTrue);
      expect(result.storedTokenDeleted, isFalse);
      expect(result.fullyCleaned, isFalse);
    });
  });
}
