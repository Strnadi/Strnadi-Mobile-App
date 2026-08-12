import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';

void main() {
  group('JWT verification (mocked verifier; no real API)', () {
    for (final ({
      int? status,
      JwtVerificationDisposition expected,
    }) scenario in <({
      int? status,
      JwtVerificationDisposition expected,
    })>[
      (
        status: 200,
        expected: JwtVerificationDisposition.verified,
      ),
      (
        status: 403,
        expected: JwtVerificationDisposition.notVerified,
      ),
      (
        status: null,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 0,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 201,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 302,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 401,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 404,
        expected: JwtVerificationDisposition.rejected,
      ),
      (
        status: 500,
        expected: JwtVerificationDisposition.rejected,
      ),
    ]) {
      test('status ${scenario.status} becomes ${scenario.expected.name}',
          () async {
        final _FakeJwtVerifierApi verifier =
            _FakeJwtVerifierApi(scenario.status);

        final JwtVerificationDisposition disposition =
            classifyJwtVerificationStatus(await verifier.verify());

        expect(disposition, scenario.expected);
        expect(verifier.calls, 1);
      });
    }
  });

  group('offline activated-session evaluation (pure; no storage or API)', () {
    const ActivatedAuthSessionSnapshot snapshot = ActivatedAuthSessionSnapshot(
      accessToken: 'token:bird@example.test',
      userId: '7',
      subject: 'bird@example.test',
      sessionId: 'opaque-session-1',
      verified: true,
    );
    const ActivatedAuthSessionSnapshot unverifiedSnapshot =
        ActivatedAuthSessionSnapshot(
      accessToken: 'token:bird@example.test',
      userId: '7',
      subject: 'bird@example.test',
      sessionId: 'opaque-session-2',
      verified: false,
    );
    final DateTime now = DateTime.utc(2026, 7, 18, 12);

    test('restores only an exact unexpired activated identity', () {
      expect(
        evaluateOfflineActivatedSession(
          snapshot: snapshot,
          storedAccessToken: snapshot.accessToken,
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        OfflineActivatedSessionStatus.loggedIn,
      );
    });

    test('keeps an exact unverified identity out of the recorder', () {
      expect(
        evaluateOfflineActivatedSession(
          snapshot: unverifiedSnapshot,
          storedAccessToken: unverifiedSnapshot.accessToken,
          expiresAt: now.add(const Duration(hours: 1)),
          now: now,
        ),
        OfflineActivatedSessionStatus.notVerified,
      );
    });

    for (final ({
      String label,
      ActivatedAuthSessionSnapshot? snapshot,
      String? token,
      DateTime? expiresAt,
    }) scenario in <({
      String label,
      ActivatedAuthSessionSnapshot? snapshot,
      String? token,
      DateTime? expiresAt,
    })>[
      (
        label: 'legacy login without marker',
        snapshot: null,
        token: 'token:bird@example.test',
        expiresAt: now.add(const Duration(hours: 1)),
      ),
      (
        label: 'different stored token',
        snapshot: snapshot,
        token: 'token:other@example.test',
        expiresAt: now.add(const Duration(hours: 1)),
      ),
      (
        label: 'malformed token without expiration',
        snapshot: snapshot,
        token: snapshot.accessToken,
        expiresAt: null,
      ),
      (
        label: 'expired token',
        snapshot: snapshot,
        token: snapshot.accessToken,
        expiresAt: now,
      ),
    ]) {
      test('fails closed for ${scenario.label}', () {
        expect(
          evaluateOfflineActivatedSession(
            snapshot: scenario.snapshot,
            storedAccessToken: scenario.token,
            expiresAt: scenario.expiresAt,
            now: now,
          ),
          OfflineActivatedSessionStatus.loggedOut,
        );
      });
    }
  });

  group('ActivatedAuthSessionManager (fake key-value store only)', () {
    late _FakeStore store;
    late ActivatedAuthSessionManager sessions;
    late int transitionSequence;

    setUp(() {
      store = _FakeStore();
      transitionSequence = 0;
      sessions = ActivatedAuthSessionManager(
        store: store,
        subjectDecoder: _subjectOf,
        sessionIdFactory: (generation) => 'opaque-session-$generation',
        transitionIdFactory: () => 'transition-${++transitionSequence}',
      );
    });

    test('invalidates marker and stale user id before storing a new token',
        () async {
      store.values.addAll(<String, String>{
        ActivatedAuthSessionManager.tokenKey: 'token:old@example.test',
        ActivatedAuthSessionManager.userIdKey: '11',
        ActivatedAuthSessionManager.verifiedKey: 'true',
        ActivatedAuthSessionManager.activatedMarkerKey: 'old-marker',
        ActivatedAuthSessionManager.pendingTransitionKey: 'old-transition',
      });

      final AuthSessionTransition transition =
          await sessions.beginTokenTransition('token:new@example.test');

      expect(transition.accessToken, 'token:new@example.test');
      expect(transition.subject, 'new@example.test');
      expect(
        store.operations,
        <String>[
          'delete:${ActivatedAuthSessionManager.activatedMarkerKey}',
          'delete:${ActivatedAuthSessionManager.userIdKey}',
          'delete:${ActivatedAuthSessionManager.verifiedKey}',
          'delete:${ActivatedAuthSessionManager.pendingTransitionKey}',
          'write:${ActivatedAuthSessionManager.tokenKey}'
              '=token:new@example.test',
          'write:${ActivatedAuthSessionManager.pendingTransitionKey}'
              '=transition-1',
        ],
      );
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
      expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      expect(store.values[ActivatedAuthSessionManager.verifiedKey], isNull);
      expect(await sessions.capture(), isNull);
    });

    test('a failed owner fetch leaves the new token unactivated', () async {
      await _activate(sessions, 'token:old@example.test', 11);
      final _FakeOwnerApi ownerApi = _FakeOwnerApi()
        ..failure = StateError('mocked owner lookup failure');

      await expectLater(
        _activateWithMockedOwnerApi(
          sessions,
          ownerApi,
          'token:new@example.test',
        ),
        throwsA(isA<StateError>()),
      );

      expect(ownerApi.calls, 1);
      expect(await sessions.capture(), isNull);
      expect(
        store.values[ActivatedAuthSessionManager.tokenKey],
        'token:new@example.test',
      );
      expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
    });

    test('a non-positive mocked owner response remains unactivated', () async {
      for (final int? invalidUserId in <int?>[null, 0, -7]) {
        final _FakeOwnerApi ownerApi = _FakeOwnerApi()
          ..resolvedUserId = invalidUserId;

        final ActivatedAuthSessionSnapshot? result =
            await _activateWithMockedOwnerApi(
          sessions,
          ownerApi,
          'token:bird$invalidUserId@example.test',
        );

        expect(result, isNull);
        expect(ownerApi.calls, 1);
        expect(await sessions.capture(), isNull);
        expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      }
    });

    test('a positive mocked owner response activates the exact credential',
        () async {
      final _FakeOwnerApi ownerApi = _FakeOwnerApi()..resolvedUserId = 42;

      final ActivatedAuthSessionSnapshot? result =
          await _activateWithMockedOwnerApi(
        sessions,
        ownerApi,
        'token:bird@example.test',
      );

      expect(result?.userId, '42');
      expect(result?.subject, 'bird@example.test');
      expect(ownerApi.calls, 1);
      expect(await sessions.isCurrent(result!), isTrue);
    });

    test('commits the activated marker after generation and user id', () async {
      final AuthSessionTransition transition =
          await sessions.beginTokenTransition('token:bird@example.test');
      store.operations.clear();

      final ActivatedAuthSessionSnapshot snapshot =
          await sessions.activate(transition, 42, verified: true);

      expect(snapshot.accessToken, 'token:bird@example.test');
      expect(snapshot.userId, '42');
      expect(snapshot.subject, 'bird@example.test');
      expect(snapshot.sessionId, 'opaque-session-1');
      expect(
        store.operations,
        <String>[
          'read:${ActivatedAuthSessionManager.tokenKey}',
          'read:${ActivatedAuthSessionManager.pendingTransitionKey}',
          'read:${ActivatedAuthSessionManager.monotonicGenerationKey}',
          'write:${ActivatedAuthSessionManager.monotonicGenerationKey}=1',
          'write:${ActivatedAuthSessionManager.userIdKey}=42',
          'write:${ActivatedAuthSessionManager.verifiedKey}=true',
          'delete:${ActivatedAuthSessionManager.pendingTransitionKey}',
          'write:${ActivatedAuthSessionManager.activatedMarkerKey}=<marker>',
        ],
      );

      final Map<String, dynamic> marker = jsonDecode(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey]!,
      ) as Map<String, dynamic>;
      expect(marker, <String, dynamic>{
        'version': 1,
        'generation': 1,
        'sessionId': 'opaque-session-1',
        'accessToken': 'token:bird@example.test',
        'userId': '42',
        'subject': 'bird@example.test',
        'verified': true,
      });
      expect(await sessions.isCurrent(snapshot), isTrue);
    });

    test('rejects zero and negative fetched user ids', () async {
      for (final int invalidUserId in <int>[0, -1]) {
        final AuthSessionTransition transition =
            await sessions.beginTokenTransition(
          'token:bird$invalidUserId@example.test',
        );
        await expectLater(
          sessions.activate(transition, invalidUserId, verified: true),
          throwsA(isA<ActivatedAuthSessionException>()),
        );
        expect(await sessions.capture(), isNull);
        expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      }
    });

    test('a torn marker commit never produces a capturable session', () async {
      final AuthSessionTransition transition =
          await sessions.beginTokenTransition('token:bird@example.test');
      store.failNextWriteOf = ActivatedAuthSessionManager.activatedMarkerKey;

      await expectLater(
        sessions.activate(transition, 42, verified: true),
        throwsA(isA<StateError>()),
      );

      expect(
        store.values[ActivatedAuthSessionManager.monotonicGenerationKey],
        '1',
      );
      expect(store.values[ActivatedAuthSessionManager.userIdKey], '42');
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
      expect(await sessions.capture(), isNull);
    });

    test('a torn verification write cannot inherit the prior account state',
        () async {
      await _activate(
        sessions,
        'token:verified@example.test',
        11,
        verified: true,
      );

      final AuthSessionTransition transition =
          await sessions.beginTokenTransition('token:pending@example.test');
      expect(store.values[ActivatedAuthSessionManager.verifiedKey], isNull);
      expect(await sessions.capture(), isNull);

      store.failNextWriteOf = ActivatedAuthSessionManager.verifiedKey;
      await expectLater(
        sessions.activate(transition, 12, verified: false),
        throwsA(isA<StateError>()),
      );

      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
      expect(store.values[ActivatedAuthSessionManager.verifiedKey], isNull);
      expect(await sessions.capture(), isNull);
      expect(
        evaluateOfflineActivatedSession(
          snapshot: await sessions.capture(),
          storedAccessToken: store.values[ActivatedAuthSessionManager.tokenKey],
          expiresAt: DateTime.utc(2026, 7, 18, 13),
          now: DateTime.utc(2026, 7, 18, 12),
        ),
        OfflineActivatedSessionStatus.loggedOut,
      );
    });

    test('unverified state is committed inside the activated marker', () async {
      final ActivatedAuthSessionSnapshot snapshot = await _activate(
        sessions,
        'token:pending@example.test',
        12,
        verified: false,
      );

      expect(snapshot.verified, isFalse);
      expect(
        store.values[ActivatedAuthSessionManager.verifiedKey],
        'false',
      );
      expect((await sessions.capture())?.verified, isFalse);
      expect(
        evaluateOfflineActivatedSession(
          snapshot: await sessions.capture(),
          storedAccessToken: snapshot.accessToken,
          expiresAt: DateTime.utc(2026, 7, 18, 13),
          now: DateTime.utc(2026, 7, 18, 12),
        ),
        OfflineActivatedSessionStatus.notVerified,
      );
    });

    test('a pending-transition cleanup failure cannot expose a session',
        () async {
      final AuthSessionTransition transition =
          await sessions.beginTokenTransition('token:bird@example.test');
      store.failNextDeleteOf = ActivatedAuthSessionManager.pendingTransitionKey;

      await expectLater(
        sessions.activate(transition, 42, verified: true),
        throwsA(isA<StateError>()),
      );

      expect(store.values[ActivatedAuthSessionManager.userIdKey], '42');
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
      expect(await sessions.capture(), isNull);
    });

    test('a token write failure cannot retain the old activated identity',
        () async {
      await _activate(sessions, 'token:old@example.test', 11);
      store.failNextWriteOf = ActivatedAuthSessionManager.tokenKey;

      await expectLater(
        sessions.beginTokenTransition('token:new@example.test'),
        throwsA(isA<StateError>()),
      );

      expect(await sessions.capture(), isNull);
      expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
    });

    test('a newer account transition makes the older transition stale',
        () async {
      final AuthSessionTransition oldTransition =
          await sessions.beginTokenTransition('token:first@example.test');
      final AuthSessionTransition newTransition =
          await sessions.beginTokenTransition('token:second@example.test');

      await expectLater(
        sessions.activate(oldTransition, 1, verified: true),
        throwsA(isA<ActivatedAuthSessionException>()),
      );
      final ActivatedAuthSessionSnapshot current =
          await sessions.activate(newTransition, 2, verified: true);

      expect(current.subject, 'second@example.test');
      expect(current.userId, '2');
      expect(await sessions.isCurrent(current), isTrue);
    });

    test('account switch invalidates the captured upload session', () async {
      final ActivatedAuthSessionSnapshot first =
          await _activate(sessions, 'token:first@example.test', 1);

      final AuthSessionTransition secondTransition =
          await sessions.beginTokenTransition('token:second@example.test');
      expect(await sessions.isCurrent(first), isFalse);

      final ActivatedAuthSessionSnapshot second =
          await sessions.activate(secondTransition, 2, verified: true);
      expect(await sessions.isCurrent(first), isFalse);
      expect(await sessions.isCurrent(second), isTrue);
      expect(second.sessionId, isNot(first.sessionId));
    });

    test('token refresh rotates a monotonically generated logical session',
        () async {
      final ActivatedAuthSessionSnapshot first =
          await _activate(sessions, 'token:bird@example.test', 7);
      final ActivatedAuthSessionSnapshot refreshed =
          await _activate(sessions, 'refreshed:bird@example.test', 7);

      expect(first.sessionId, 'opaque-session-1');
      expect(refreshed.sessionId, 'opaque-session-2');
      expect(
        store.values[ActivatedAuthSessionManager.monotonicGenerationKey],
        '2',
      );
      expect(await sessions.isCurrent(first), isFalse);
      expect(await sessions.isCurrent(refreshed), isTrue);
    });

    test('legacy token activates only with the freshly fetched positive id',
        () async {
      store.values.addAll(<String, String>{
        ActivatedAuthSessionManager.tokenKey: 'legacy:bird@example.test',
        ActivatedAuthSessionManager.userIdKey: '999',
      });

      final ActivatedAuthSessionSnapshot migrated =
          await sessions.activateCurrentToken(7, verified: true);

      expect(migrated.userId, '7');
      expect(migrated.subject, 'bird@example.test');
      expect(migrated.sessionId, 'opaque-session-1');
      expect(await sessions.capture(), isNotNull);
      expect(store.values[ActivatedAuthSessionManager.userIdKey], '7');
    });

    test('activating an already current token is idempotent', () async {
      final ActivatedAuthSessionSnapshot first =
          await _activate(sessions, 'token:bird@example.test', 7);
      final ActivatedAuthSessionSnapshot second =
          await sessions.activateCurrentToken(7, verified: true);

      expect(second.sessionId, first.sessionId);
      expect(
        store.values[ActivatedAuthSessionManager.monotonicGenerationKey],
        '1',
      );
    });

    test('legacy activation fails closed for an invalid token', () async {
      store.values.addAll(<String, String>{
        ActivatedAuthSessionManager.tokenKey: 'malformed',
        ActivatedAuthSessionManager.userIdKey: '999',
        ActivatedAuthSessionManager.activatedMarkerKey: 'stale-marker',
      });

      await expectLater(
        sessions.activateCurrentToken(7, verified: true),
        throwsA(isA<ActivatedAuthSessionException>()),
      );

      expect(await sessions.capture(), isNull);
      expect(store.values[ActivatedAuthSessionManager.userIdKey], isNull);
      expect(
        store.values[ActivatedAuthSessionManager.activatedMarkerKey],
        isNull,
      );
    });

    test('capture rejects each independently tampered binding', () async {
      final ActivatedAuthSessionSnapshot original =
          await _activate(sessions, 'token:bird@example.test', 7);
      final String originalMarker =
          store.values[ActivatedAuthSessionManager.activatedMarkerKey]!;

      store.values[ActivatedAuthSessionManager.tokenKey] =
          'token:other@example.test';
      expect(await sessions.capture(), isNull);
      store.values[ActivatedAuthSessionManager.tokenKey] = original.accessToken;

      store.values[ActivatedAuthSessionManager.userIdKey] = '8';
      expect(await sessions.capture(), isNull);
      store.values[ActivatedAuthSessionManager.userIdKey] = original.userId;

      final Map<String, dynamic> marker =
          jsonDecode(originalMarker) as Map<String, dynamic>;
      marker['subject'] = 'other@example.test';
      store.values[ActivatedAuthSessionManager.activatedMarkerKey] =
          jsonEncode(marker);
      expect(await sessions.capture(), isNull);

      marker['subject'] = original.subject;
      marker['sessionId'] = '';
      store.values[ActivatedAuthSessionManager.activatedMarkerKey] =
          jsonEncode(marker);
      expect(await sessions.capture(), isNull);
    });

    test('capture rejects a pending transition or mismatched generation',
        () async {
      await _activate(sessions, 'token:bird@example.test', 7);

      store.values[ActivatedAuthSessionManager.pendingTransitionKey] =
          'unexpected-pending-transition';
      expect(await sessions.capture(), isNull);

      store.values.remove(ActivatedAuthSessionManager.pendingTransitionKey);
      store.values[ActivatedAuthSessionManager.monotonicGenerationKey] = '2';
      expect(await sessions.capture(), isNull);
    });

    test('capture rejects malformed and partial marker payloads', () async {
      store.values.addAll(<String, String>{
        ActivatedAuthSessionManager.tokenKey: 'token:bird@example.test',
        ActivatedAuthSessionManager.userIdKey: '7',
      });

      for (final String marker in <String>[
        'not-json',
        '[]',
        jsonEncode(<String, Object>{'version': 1}),
        jsonEncode(<String, Object>{
          'version': 2,
          'generation': 1,
          'sessionId': 'session',
          'accessToken': 'token:bird@example.test',
          'userId': '7',
          'subject': 'bird@example.test',
        }),
      ]) {
        store.values[ActivatedAuthSessionManager.activatedMarkerKey] = marker;
        expect(await sessions.capture(), isNull);
      }
    });

    test('logout invalidates first and preserves the monotonic generation',
        () async {
      final ActivatedAuthSessionSnapshot first =
          await _activate(sessions, 'token:first@example.test', 1);
      final List<bool> markerPresentDuringClear = <bool>[];

      await sessions.clearAllPreservingGeneration(() async {
        markerPresentDuringClear.add(
          store.values
              .containsKey(ActivatedAuthSessionManager.activatedMarkerKey),
        );
        store.values.clear();
      });

      expect(markerPresentDuringClear, <bool>[false]);
      expect(await sessions.isCurrent(first), isFalse);
      expect(
        store.values[ActivatedAuthSessionManager.monotonicGenerationKey],
        '1',
      );
      final ActivatedAuthSessionSnapshot second =
          await _activate(sessions, 'token:second@example.test', 2);
      expect(second.sessionId, 'opaque-session-2');
    });

    test('explicit invalidation removes marker and user before token',
        () async {
      await _activate(sessions, 'token:bird@example.test', 7);
      store.operations.clear();

      await sessions.invalidate();

      expect(
        store.operations,
        <String>[
          'delete:${ActivatedAuthSessionManager.activatedMarkerKey}',
          'delete:${ActivatedAuthSessionManager.userIdKey}',
          'delete:${ActivatedAuthSessionManager.verifiedKey}',
          'delete:${ActivatedAuthSessionManager.pendingTransitionKey}',
          'delete:${ActivatedAuthSessionManager.tokenKey}',
        ],
      );
      expect(await sessions.capture(), isNull);
    });
  });
}

String? _subjectOf(String token) {
  final int separator = token.indexOf(':');
  if (separator <= 0 || separator == token.length - 1) return null;
  return token.substring(separator + 1);
}

Future<ActivatedAuthSessionSnapshot> _activate(
  ActivatedAuthSessionManager sessions,
  String token,
  int userId, {
  bool verified = true,
}) async {
  final AuthSessionTransition transition =
      await sessions.beginTokenTransition(token);
  return sessions.activate(transition, userId, verified: verified);
}

Future<ActivatedAuthSessionSnapshot?> _activateWithMockedOwnerApi(
  ActivatedAuthSessionManager sessions,
  _FakeOwnerApi ownerApi,
  String token,
) async {
  final AuthSessionTransition transition =
      await sessions.beginTokenTransition(token);
  final int? userId = await ownerApi.fetchUserId();
  if (userId == null || userId <= 0) return null;
  return sessions.activate(transition, userId, verified: true);
}

class _FakeOwnerApi {
  int calls = 0;
  int? resolvedUserId;
  Object? failure;

  Future<int?> fetchUserId() async {
    calls++;
    final Object? error = failure;
    if (error != null) throw error;
    return resolvedUserId;
  }
}

class _FakeJwtVerifierApi {
  _FakeJwtVerifierApi(this.statusCode);

  final int? statusCode;
  int calls = 0;

  Future<int?> verify() async {
    calls++;
    return statusCode;
  }
}

class _FakeStore implements AuthSessionKeyValueStore {
  final Map<String, String> values = <String, String>{};
  final List<String> operations = <String>[];
  String? failNextDeleteOf;
  String? failNextWriteOf;

  @override
  Future<void> delete(String key) async {
    operations.add('delete:$key');
    if (failNextDeleteOf == key) {
      failNextDeleteOf = null;
      throw StateError('mocked delete failure for $key');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    operations.add('read:$key');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    operations.add(
      key == ActivatedAuthSessionManager.activatedMarkerKey
          ? 'write:$key=<marker>'
          : 'write:$key=$value',
    );
    if (failNextWriteOf == key) {
      failNextWriteOf = null;
      throw StateError('mocked write failure for $key');
    }
    values[key] = value;
  }
}
