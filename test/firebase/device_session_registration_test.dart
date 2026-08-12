import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/firebase/device_session_registration.dart';

DeviceRegistrationScope _scope({
  String sessionId = 'session-a',
  String accessToken = 'jwt-a',
  int userId = 7,
  String subject = 'a@example.test',
  String environment = 'prod',
  String apiHost = 'prod.example.test',
}) {
  return DeviceRegistrationScope(
    sessionId: sessionId,
    accessToken: accessToken,
    userId: userId,
    subject: subject,
    environment: environment,
    apiHost: apiHost,
  );
}

class _Harness {
  _Harness() {
    coordinator = DeviceTokenSessionCoordinator(
      captureScope: () async {
        captureCalls += 1;
        return currentScope;
      },
      isScopeCurrent: (DeviceRegistrationScope scope) async {
        currentChecks += 1;
        return scopeCurrent &&
            currentScope?.sessionId == scope.sessionId &&
            currentScope?.accessToken == scope.accessToken &&
            currentScope?.userId == scope.userId &&
            currentScope?.subject == scope.subject &&
            currentScope?.environment == scope.environment &&
            currentScope?.apiHost == scope.apiHost;
      },
      readBinding: () async {
        bindingReads += 1;
        if (bindingReadError != null) throw bindingReadError!;
        return encodedBinding;
      },
      getCurrentToken: () async {
        tokenReads += 1;
        if (tokenReadError != null) throw tokenReadError!;
        return currentToken;
      },
      loadMetadata: () async {
        metadataCalls += 1;
        if (metadataGate != null) await metadataGate!.future;
        return DeviceRegistrationMetadata(
          platform: 'test-platform',
          model: 'test-model',
        );
      },
      registerRemote: (
        DeviceRegistrationScope scope,
        String token,
        DeviceRegistrationMetadata metadata,
      ) async {
        registerCalls += 1;
        registeredScope = scope;
        registeredToken = token;
        registeredMetadata = metadata;
        if (registerAction != null) {
          return registerAction!(scope, token, metadata);
        }
        return registerStatus;
      },
      updateRemote: (
        DeviceRegistrationScope scope,
        String oldToken,
        String newToken,
      ) async {
        updateCalls += 1;
        updatedScope = scope;
        updatedOldToken = oldToken;
        updatedNewToken = newToken;
        if (updateAction != null) {
          return updateAction!(scope, oldToken, newToken);
        }
        return updateStatus;
      },
      persistBinding: (DeviceTokenBinding binding) async {
        persistenceCalls += 1;
        if (persistenceAction != null) {
          await persistenceAction!(binding);
          return;
        }
        encodedBinding = binding.encode();
      },
      clearBindingIfCurrent: (DeviceTokenBinding binding) async {
        clearCalls += 1;
        if (clearError != null) throw clearError!;
        final DeviceTokenBinding? current =
            DeviceTokenBinding.decode(encodedBinding);
        if (current?.encode() == binding.encode()) {
          encodedBinding = null;
        }
      },
    );
  }

  late final DeviceTokenSessionCoordinator coordinator;
  DeviceRegistrationScope? currentScope = _scope();
  bool scopeCurrent = true;
  String? currentToken = 'token-a';
  String? encodedBinding;
  Object? bindingReadError;
  Object? tokenReadError;
  Completer<void>? metadataGate;
  int registerStatus = 200;
  int updateStatus = 200;
  Future<int?> Function(
    DeviceRegistrationScope,
    String,
    DeviceRegistrationMetadata,
  )? registerAction;
  Future<int?> Function(DeviceRegistrationScope, String, String)? updateAction;
  Future<void> Function(DeviceTokenBinding)? persistenceAction;
  Object? clearError;

  int captureCalls = 0;
  int currentChecks = 0;
  int bindingReads = 0;
  int tokenReads = 0;
  int metadataCalls = 0;
  int registerCalls = 0;
  int updateCalls = 0;
  int persistenceCalls = 0;
  int clearCalls = 0;
  DeviceRegistrationScope? registeredScope;
  DeviceRegistrationScope? updatedScope;
  String? registeredToken;
  String? updatedOldToken;
  String? updatedNewToken;
  DeviceRegistrationMetadata? registeredMetadata;

  DeviceTokenBinding get binding => DeviceTokenBinding.decode(encodedBinding)!;
}

void main() {
  group('DeviceTokenBinding', () {
    test(
        'round-trips all account, session, environment, token, and host fields',
        () {
      final DeviceTokenBinding original =
          DeviceTokenBinding.forScope(_scope(), ' fcm-token ');

      final DeviceTokenBinding? decoded =
          DeviceTokenBinding.decode(original.encode());

      expect(decoded, isNotNull);
      expect(decoded!.token, 'fcm-token');
      expect(decoded.userId, 7);
      expect(decoded.subject, 'a@example.test');
      expect(decoded.sessionId, 'session-a');
      expect(decoded.environment, 'prod');
      expect(decoded.apiHost, 'prod.example.test');
      expect(decoded.belongsTo(_scope()), isTrue);
    });

    test('rejects malformed, incomplete, and unknown-version markers', () {
      expect(DeviceTokenBinding.decode(null), isNull);
      expect(DeviceTokenBinding.decode(''), isNull);
      expect(DeviceTokenBinding.decode('not-json'), isNull);
      expect(DeviceTokenBinding.decode('[]'), isNull);
      expect(
        DeviceTokenBinding.decode(
          '{"version":2,"token":"t","userId":1,'
          '"subject":"s","sessionId":"x","environment":"prod",'
          '"apiHost":"host"}',
        ),
        isNull,
      );
      expect(
        DeviceTokenBinding.decode(
          '{"version":1,"token":"t","userId":1,'
          '"subject":"s","sessionId":"x","environment":"prod"}',
        ),
        isNull,
      );
    });

    test('a new logical login does not own the prior login binding', () {
      final DeviceTokenBinding binding =
          DeviceTokenBinding.forScope(_scope(), 'token');

      expect(
        binding.belongsTo(_scope(sessionId: 'session-b')),
        isFalse,
      );
      expect(
        binding.belongsToLogicalSession(_scope(sessionId: 'session-b')),
        isFalse,
      );
    });

    test('cleanup can recognize the logical session after an env switch', () {
      final DeviceTokenBinding binding =
          DeviceTokenBinding.forScope(_scope(), 'token');
      final DeviceRegistrationScope switched = _scope(
        environment: 'dev',
        apiHost: 'dev.example.test',
      );

      expect(binding.belongsTo(switched), isFalse);
      expect(binding.belongsToLogicalSession(switched), isTrue);
    });
  });

  group('DeviceTokenSessionCoordinator synchronization (all boundaries fake)',
      () {
    test('does nothing without a captured verified session', () async {
      final _Harness harness = _Harness()..currentScope = null;

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.noVerifiedSession);
      expect(harness.tokenReads, 0);
      expect(harness.registerCalls, 0);
      expect(harness.updateCalls, 0);
      expect(harness.persistenceCalls, 0);
    });

    for (final String? missingToken in <String?>[null, '', ' \n ']) {
      test('does nothing for missing current token ${missingToken ?? "null"}',
          () async {
        final _Harness harness = _Harness()..currentToken = missingToken;

        final DeviceTokenSyncResult result =
            await harness.coordinator.synchronize();

        expect(result.status, DeviceTokenSyncStatus.noCurrentToken);
        expect(harness.registerCalls, 0);
        expect(harness.persistenceCalls, 0);
      });
    }

    test('registers using only the captured immutable scope', () async {
      final _Harness harness = _Harness();

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.registered);
      expect(result.statusCode, 200);
      expect(harness.registerCalls, 1);
      expect(harness.updateCalls, 0);
      expect(harness.registeredScope!.sessionId, 'session-a');
      expect(harness.registeredScope!.accessToken, 'jwt-a');
      expect(harness.registeredScope!.apiHost, 'prod.example.test');
      expect(harness.registeredToken, 'token-a');
      expect(harness.registeredMetadata!.platform, 'test-platform');
      expect(harness.binding.belongsTo(harness.currentScope!), isTrue);
      expect(harness.binding.token, 'token-a');
    });

    test('revalidates after slow metadata and before registration', () async {
      final _Harness harness = _Harness();
      harness.metadataGate = Completer<void>();

      final Future<DeviceTokenSyncResult> sync =
          harness.coordinator.synchronize();
      await Future<void>.delayed(Duration.zero);
      harness.currentScope = _scope(
        sessionId: 'session-b',
        accessToken: 'jwt-b',
      );
      harness.metadataGate!.complete();

      expect(
        (await sync).status,
        DeviceTokenSyncStatus.sessionChangedBeforeRemote,
      );
      expect(harness.registerCalls, 0);
      expect(harness.persistenceCalls, 0);
    });

    test('account switch during registration never persists stale ownership',
        () async {
      final _Harness harness = _Harness();
      harness.registerAction = (scope, token, metadata) async {
        harness.currentScope = _scope(
          sessionId: 'session-b',
          accessToken: 'jwt-b',
          userId: 8,
          subject: 'b@example.test',
        );
        return 200;
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.sessionChangedAfterRemote);
      expect(harness.registerCalls, 1);
      expect(harness.persistenceCalls, 0);
      expect(harness.encodedBinding, isNull);
    });

    test('environment switch during registration fails closed', () async {
      final _Harness harness = _Harness();
      harness.registerAction = (scope, token, metadata) async {
        harness.currentScope = _scope(
          environment: 'dev',
          apiHost: 'dev.example.test',
        );
        return 201;
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.sessionChangedAfterRemote);
      expect(harness.persistenceCalls, 0);
    });

    for (final int rejectedStatus in <int>[199, 300, 302, 400, 500]) {
      test('status $rejectedStatus cannot commit a registration', () async {
        final _Harness harness = _Harness()..registerStatus = rejectedStatus;

        final DeviceTokenSyncResult result =
            await harness.coordinator.synchronize();

        expect(result.status, DeviceTokenSyncStatus.remoteRejected);
        expect(result.statusCode, rejectedStatus);
        expect(harness.persistenceCalls, 0);
      });
    }

    test('remote exception cannot commit a registration', () async {
      final _Harness harness = _Harness();
      harness.registerAction = (scope, token, metadata) async {
        throw StateError('mock remote failure');
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.remoteFailed);
      expect(result.error, isA<StateError>());
      expect(harness.persistenceCalls, 0);
    });

    test('binding persistence failure is observable', () async {
      final _Harness harness = _Harness();
      harness.persistenceAction = (_) async {
        throw StateError('mock storage failure');
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.persistenceFailed);
      expect(result.error, isA<StateError>());
    });

    test('switch during persistence clears only the just-written binding',
        () async {
      final _Harness harness = _Harness();
      harness.persistenceAction = (DeviceTokenBinding binding) async {
        harness.encodedBinding = binding.encode();
        harness.currentScope = _scope(
          sessionId: 'session-b',
          accessToken: 'jwt-b',
        );
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.sessionChangedAfterRemote);
      expect(harness.clearCalls, 1);
      expect(harness.encodedBinding, isNull);
    });

    test('matching binding and token perform no remote or persistence work',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.unchanged);
      expect(harness.metadataCalls, 0);
      expect(harness.registerCalls, 0);
      expect(harness.updateCalls, 0);
      expect(harness.persistenceCalls, 0);
    });

    test('updates only a token bound to the same exact logical session',
        () async {
      final _Harness harness = _Harness()..currentToken = 'token-b';
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.updated);
      expect(harness.registerCalls, 0);
      expect(harness.updateCalls, 1);
      expect(harness.updatedScope!.accessToken, 'jwt-a');
      expect(harness.updatedOldToken, 'token-a');
      expect(harness.updatedNewToken, 'token-b');
      expect(harness.binding.token, 'token-b');
    });

    test('an account-owned token is registered, never updated, by another user',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding = DeviceTokenBinding.forScope(
        _scope(
          sessionId: 'session-old',
          accessToken: 'jwt-old',
          userId: 99,
          subject: 'other@example.test',
        ),
        'old-token',
      ).encode();

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.registered);
      expect(harness.registerCalls, 1);
      expect(harness.updateCalls, 0);
      expect(harness.registeredToken, 'token-a');
    });

    test('a relogin of the same user registers instead of mutating old session',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding = DeviceTokenBinding.forScope(
        _scope(sessionId: 'old-session'),
        'old-token',
      ).encode();

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.registered);
      expect(harness.updateCalls, 0);
    });

    test('corrupt or unreadable binding registers from fresh scope', () async {
      final _Harness corrupt = _Harness()..encodedBinding = '{bad';
      final _Harness unreadable = _Harness()
        ..bindingReadError = StateError('mock secure storage read');

      expect(
        (await corrupt.coordinator.synchronize()).status,
        DeviceTokenSyncStatus.registered,
      );
      expect(
        (await unreadable.coordinator.synchronize()).status,
        DeviceTokenSyncStatus.registered,
      );
      expect(corrupt.updateCalls + unreadable.updateCalls, 0);
    });

    test('update response after account switch cannot replace binding',
        () async {
      final _Harness harness = _Harness()..currentToken = 'token-b';
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();
      harness.updateAction = (scope, oldToken, newToken) async {
        harness.currentScope = _scope(
          sessionId: 'session-b',
          accessToken: 'jwt-b',
          userId: 8,
          subject: 'b@example.test',
        );
        return 204;
      };

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.sessionChangedAfterRemote);
      expect(harness.binding.token, 'token-a');
      expect(harness.persistenceCalls, 0);
    });

    test('token read failure is contained before any remote call', () async {
      final _Harness harness = _Harness()
        ..tokenReadError = StateError('mock Firebase token read');

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize();

      expect(result.status, DeviceTokenSyncStatus.noCurrentToken);
      expect(result.error, isA<StateError>());
      expect(harness.registerCalls, 0);
    });

    test('concurrent refreshes serialize their remote boundaries', () async {
      final _Harness harness = _Harness();
      final Completer<int?> firstRemote = Completer<int?>();
      harness.registerAction = (scope, token, metadata) {
        return firstRemote.future;
      };

      final Future<DeviceTokenSyncResult> first =
          harness.coordinator.synchronize(currentTokenOverride: 'token-a');
      await Future<void>.delayed(Duration.zero);
      final Future<DeviceTokenSyncResult> second =
          harness.coordinator.synchronize(currentTokenOverride: 'token-b');
      await Future<void>.delayed(Duration.zero);

      expect(harness.registerCalls, 1);
      expect(harness.updateCalls, 0);
      firstRemote.complete(200);
      expect((await first).status, DeviceTokenSyncStatus.registered);
      expect((await second).status, DeviceTokenSyncStatus.updated);
      expect(harness.registerCalls, 1);
      expect(harness.updateCalls, 1);
      expect(harness.binding.token, 'token-b');
    });
  });

  group('DeviceTokenSessionCoordinator cleanup races (all boundaries fake)',
      () {
    test(
        'logout waits for an in-flight refresh, removes it, then suppresses it',
        () async {
      final _Harness harness = _Harness();
      final Completer<int?> firstRemote = Completer<int?>();
      harness.registerAction = (scope, token, metadata) => firstRemote.future;
      final List<String> cleanupCalls = <String>[];

      final Future<DeviceTokenSyncResult> inFlight =
          harness.coordinator.synchronize();
      await Future<void>.delayed(Duration.zero);
      final Future<DeviceSessionCleanupResult> cleanup =
          harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (scope, binding) async {
          cleanupCalls.add('remote:${binding.token}@${binding.apiHost}');
          return 204;
        },
        invalidateFirebaseToken: () async {
          cleanupCalls.add('firebase');
        },
        clearUnboundLocalToken: () async {
          cleanupCalls.add('unbound');
          harness.encodedBinding = null;
        },
      );
      final Future<DeviceTokenSyncResult> refreshAfterLogout =
          harness.coordinator.synchronize(currentTokenOverride: 'token-b');

      firstRemote.complete(200);

      expect((await inFlight).status, DeviceTokenSyncStatus.registered);
      final DeviceSessionCleanupResult cleanupResult = await cleanup;
      expect(cleanupResult.fullyCleaned, isTrue);
      expect(
        (await refreshAfterLogout).status,
        DeviceTokenSyncStatus.suppressedAfterCleanup,
      );
      expect(
        cleanupCalls,
        <String>['remote:token-a@prod.example.test', 'firebase'],
      );
      expect(harness.encodedBinding, isNull);
      expect(harness.registerCalls, 1);
      expect(harness.updateCalls, 0);
    });

    test('refresh starting after cleanup cannot recreate the registration',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();

      await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 200,
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {
          harness.encodedBinding = null;
        },
      );
      final DeviceTokenSyncResult refresh =
          await harness.coordinator.synchronize(
        currentTokenOverride: 'token-b',
      );

      expect(refresh.status, DeviceTokenSyncStatus.suppressedAfterCleanup);
      expect(harness.registerCalls, 0);
      expect(harness.updateCalls, 0);
    });

    test('a newly activated logical session is allowed after prior logout',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();
      await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 200,
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {
          harness.encodedBinding = null;
        },
      );
      harness.currentScope = _scope(
        sessionId: 'session-b',
        accessToken: 'jwt-b',
      );

      final DeviceTokenSyncResult result =
          await harness.coordinator.synchronize(
        currentTokenOverride: 'token-b',
      );

      expect(result.status, DeviceTokenSyncStatus.registered);
      expect(harness.binding.sessionId, 'session-b');
    });

    test('environment switch deletes against the binding original host',
        () async {
      final _Harness harness = _Harness();
      final DeviceRegistrationScope oldScope = harness.currentScope!;
      harness.encodedBinding =
          DeviceTokenBinding.forScope(oldScope, 'token-a').encode();
      harness.currentScope = _scope(
        environment: 'dev',
        apiHost: 'dev.example.test',
      );
      String? deletedHost;
      String? authToken;

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (scope, binding) async {
          deletedHost = binding.apiHost;
          authToken = scope.accessToken;
          return 200;
        },
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {
          harness.encodedBinding = null;
        },
      );

      expect(result.remoteAttempted, isTrue);
      expect(deletedHost, 'prod.example.test');
      expect(authToken, 'jwt-a');
      expect(harness.encodedBinding, isNull);
    });

    test('binding from another session is cleared locally but never deleted',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding = DeviceTokenBinding.forScope(
        _scope(sessionId: 'old-session'),
        'old-token',
      ).encode();
      int remoteCalls = 0;

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async {
          remoteCalls += 1;
          return 200;
        },
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {
          harness.encodedBinding = null;
        },
      );

      expect(remoteCalls, 0);
      expect(result.remoteAttempted, isFalse);
      expect(result.bindingCleared, isTrue);
      expect(harness.encodedBinding, isNull);
    });

    test('no marker skips remote but clears legacy local state', () async {
      final _Harness harness = _Harness();
      int unboundClears = 0;

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 200,
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {
          unboundClears += 1;
        },
      );

      expect(result.remoteAttempted, isFalse);
      expect(unboundClears, 1);
      expect(result.bindingCleared, isTrue);
    });

    test('remote rejection cannot suppress Firebase and local cleanup',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();
      int invalidations = 0;

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 500,
        invalidateFirebaseToken: () async {
          invalidations += 1;
        },
        clearUnboundLocalToken: () async {},
      );

      expect(result.remoteDeleted, isFalse);
      expect(invalidations, 1);
      expect(result.bindingCleared, isTrue);
      expect(harness.encodedBinding, isNull);
      expect(result.fullyCleaned, isFalse);
    });

    test('Firebase invalidation failure cannot suppress exact binding cleanup',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 404,
        invalidateFirebaseToken: () async {
          throw StateError('mock Firebase invalidation');
        },
        clearUnboundLocalToken: () async {},
      );

      expect(result.remoteDeleted, isTrue);
      expect(result.firebaseTokenInvalidated, isFalse);
      expect(result.bindingCleared, isTrue);
      expect(harness.encodedBinding, isNull);
    });

    test('exact binding cleanup failure is reported and remains scoped',
        () async {
      final _Harness harness = _Harness();
      harness.encodedBinding =
          DeviceTokenBinding.forScope(harness.currentScope!, 'token-a')
              .encode();
      harness.clearError = StateError('mock storage delete');

      final DeviceSessionCleanupResult result =
          await harness.coordinator.cleanUpCurrentSession(
        deleteRemote: (_, __) async => 200,
        invalidateFirebaseToken: () async {},
        clearUnboundLocalToken: () async {},
      );

      expect(result.bindingCleared, isFalse);
      expect(result.fullyCleaned, isFalse);
      expect(harness.binding.sessionId, 'session-a');
    });
  });
}
