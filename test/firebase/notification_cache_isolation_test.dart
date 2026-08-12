import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/firebase/notification_cache_isolation.dart';

const ActivatedAuthSessionSnapshot _verifiedAccountA =
    ActivatedAuthSessionSnapshot(
  accessToken: 'mock-token-a',
  userId: '41',
  subject: 'mock-subject-a',
  sessionId: 'mock-session-a',
  verified: true,
);
const ActivatedAuthSessionSnapshot _verifiedAccountB =
    ActivatedAuthSessionSnapshot(
  accessToken: 'mock-token-b',
  userId: '52',
  subject: 'mock-subject-b',
  sessionId: 'mock-session-b',
  verified: true,
);
const ActivatedAuthSessionSnapshot _unverifiedAccount =
    ActivatedAuthSessionSnapshot(
  accessToken: 'mock-token-unverified',
  userId: '41',
  subject: 'mock-subject-a',
  sessionId: 'mock-session-unverified',
  verified: false,
);

void main() {
  group('NotificationCacheIsolation persistence (fakes only)', () {
    test('captures exactly one verified owner and environment', () async {
      final _Harness harness = _Harness();
      NotificationCacheScope? insertedScope;
      int cleanupCalls = 0;

      final bool persisted = await harness.isolation.persist(
        insert: (NotificationCacheScope scope) async {
          insertedScope = scope;
          return 7;
        },
        removeInserted: (NotificationCacheScope scope, int id) async {
          cleanupCalls++;
        },
      );

      expect(persisted, isTrue);
      expect(harness.captureCalls, 1);
      expect(harness.currentChecks, 2);
      expect(insertedScope?.ownerUserId, '41');
      expect(insertedScope?.environment, 'prod');
      expect(insertedScope?.activatedSession, same(_verifiedAccountA));
      expect(cleanupCalls, 0);
    });

    test('ignores a notification when no activated login exists', () async {
      final _Harness harness = _Harness()..capturedSession = null;
      int inserts = 0;

      final bool persisted = await harness.isolation.persist(
        insert: (NotificationCacheScope scope) async {
          inserts++;
          return 1;
        },
        removeInserted: (NotificationCacheScope scope, int id) async {},
      );

      expect(persisted, isFalse);
      expect(inserts, 0);
      expect(harness.currentChecks, 0);
    });

    test('ignores a notification for an unverified login', () async {
      final _Harness harness = _Harness()..capturedSession = _unverifiedAccount;
      int inserts = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            inserts++;
            return 1;
          },
          removeInserted: (NotificationCacheScope scope, int id) async {},
        ),
        isFalse,
      );
      expect(inserts, 0);
      expect(harness.currentChecks, 0);
    });

    test('rejects invalid backend owner ids before persistence', () async {
      for (final String invalidUserId in <String>[
        '',
        ' ',
        '0',
        '-4',
        'guest',
      ]) {
        final _Harness harness = _Harness()
          ..capturedSession = _session(userId: invalidUserId);
        int inserts = 0;

        expect(
          await harness.isolation.persist(
            insert: (NotificationCacheScope scope) async {
              inserts++;
              return 1;
            },
            removeInserted: (NotificationCacheScope scope, int id) async {},
          ),
          isFalse,
        );
        expect(inserts, 0, reason: 'invalid user id: "$invalidUserId"');
      }
    });

    test('rejects an unknown environment before persistence', () async {
      final _Harness harness = _Harness()..environment = ' ';
      int inserts = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            inserts++;
            return 1;
          },
          removeInserted: (NotificationCacheScope scope, int id) async {},
        ),
        isFalse,
      );
      expect(inserts, 0);
    });

    test('auth capture failures fail closed without opening persistence',
        () async {
      final _Harness harness = _Harness()
        ..captureError = StateError('mock secure storage unavailable');
      int inserts = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            inserts++;
            return 1;
          },
          removeInserted: (NotificationCacheScope scope, int id) async {},
        ),
        isFalse,
      );
      expect(inserts, 0);
    });

    test('a stale logical login cannot insert', () async {
      final _Harness harness = _Harness()..currentResults.add(false);
      int inserts = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            inserts++;
            return 1;
          },
          removeInserted: (NotificationCacheScope scope, int id) async {},
        ),
        isFalse,
      );
      expect(inserts, 0);
    });

    test('an environment switch before insertion cannot insert', () async {
      final _Harness harness = _Harness()
        ..environmentResults.addAll(<String>['prod', 'dev']);
      int inserts = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            inserts++;
            return 1;
          },
          removeInserted: (NotificationCacheScope scope, int id) async {},
        ),
        isFalse,
      );
      expect(inserts, 0);
      expect(harness.currentChecks, 0);
    });

    test('an account switch after insert removes only the inserted row',
        () async {
      final _Harness harness = _Harness()
        ..currentResults.addAll(<bool>[true, false]);
      final List<int> removedIds = <int>[];
      NotificationCacheScope? cleanupScope;

      final bool persisted = await harness.isolation.persist(
        insert: (NotificationCacheScope scope) async => 913,
        removeInserted: (NotificationCacheScope scope, int id) async {
          cleanupScope = scope;
          removedIds.add(id);
        },
      );

      expect(persisted, isFalse);
      expect(removedIds, <int>[913]);
      expect(cleanupScope?.ownerUserId, '41');
      expect(cleanupScope?.environment, 'prod');
    });

    test('an environment switch after insert removes the scoped row', () async {
      final _Harness harness = _Harness()
        ..environmentResults.addAll(<String>['prod', 'prod', 'dev']);
      int cleanupCalls = 0;

      expect(
        await harness.isolation.persist(
          insert: (NotificationCacheScope scope) async => 12,
          removeInserted: (NotificationCacheScope scope, int id) async {
            cleanupCalls++;
            expect(scope.environment, 'prod');
            expect(id, 12);
          },
        ),
        isFalse,
      );
      expect(cleanupCalls, 1);
    });

    test('cleanup failure leaves the stale result quarantined', () async {
      final _Harness harness = _Harness()
        ..currentResults.addAll(<bool>[true, false]);

      final bool persisted = await harness.isolation.persist(
        insert: (NotificationCacheScope scope) async => 12,
        removeInserted: (NotificationCacheScope scope, int id) async {
          throw StateError('mock cleanup failure');
        },
      );

      expect(persisted, isFalse);
    });

    test('a persistence failure is not misreported as an ignored push',
        () async {
      final _Harness harness = _Harness();
      int cleanupCalls = 0;

      await expectLater(
        harness.isolation.persist(
          insert: (NotificationCacheScope scope) async {
            throw StateError('mock persistence failure');
          },
          removeInserted: (NotificationCacheScope scope, int id) async {
            cleanupCalls++;
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(cleanupCalls, 0);
    });
  });

  group('NotificationCacheIsolation reads (fakes only)', () {
    test('scoped list returns rows while the captured login is current',
        () async {
      final _Harness harness = _Harness();
      NotificationCacheScope? readScope;

      final List<String> rows = await harness.isolation.readList<String>(
        read: (NotificationCacheScope scope) async {
          readScope = scope;
          return <String>['owned'];
        },
      );

      expect(rows, <String>['owned']);
      expect(readScope?.ownerUserId, '41');
      expect(readScope?.environment, 'prod');
      expect(harness.captureCalls, 1);
      expect(harness.currentChecks, 2);
    });

    test('logged-out and unverified list reads never reach storage', () async {
      for (final ActivatedAuthSessionSnapshot? session
          in <ActivatedAuthSessionSnapshot?>[null, _unverifiedAccount]) {
        final _Harness harness = _Harness()..capturedSession = session;
        int reads = 0;

        expect(
          await harness.isolation.readList<String>(
            read: (NotificationCacheScope scope) async {
              reads++;
              return <String>['leak'];
            },
          ),
          isEmpty,
        );
        expect(reads, 0);
      }
    });

    test('stale login before a list read never reaches storage', () async {
      final _Harness harness = _Harness()..currentResults.add(false);
      int reads = 0;

      expect(
        await harness.isolation.readList<String>(
          read: (NotificationCacheScope scope) async {
            reads++;
            return <String>['leak'];
          },
        ),
        isEmpty,
      );
      expect(reads, 0);
    });

    test('account switch after list read discards the result', () async {
      final _Harness harness = _Harness()
        ..currentResults.addAll(<bool>[true, false]);

      expect(
        await harness.isolation.readList<String>(
          read: (NotificationCacheScope scope) async => <String>['old owner'],
        ),
        isEmpty,
      );
    });

    test('environment switch after list read discards the result', () async {
      final _Harness harness = _Harness()
        ..environmentResults.addAll(<String>['prod', 'prod', 'dev']);

      expect(
        await harness.isolation.readList<String>(
          read: (NotificationCacheScope scope) async => <String>['prod only'],
        ),
        isEmpty,
      );
    });

    test('current-session lookup errors discard list data', () async {
      final _Harness harness = _Harness()
        ..currentErrors.addAll(<Object?>[
          null,
          StateError('mock current-session read failure'),
        ]);

      expect(
        await harness.isolation.readList<String>(
          read: (NotificationCacheScope scope) async => <String>['private'],
        ),
        isEmpty,
      );
    });

    test('storage read failures still surface for diagnostics', () async {
      final _Harness harness = _Harness();

      await expectLater(
        harness.isolation.readList<String>(
          read: (NotificationCacheScope scope) async {
            throw StateError('mock cache read failure');
          },
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('scoped unread count is returned only for a current login', () async {
      final _Harness harness = _Harness();

      expect(
        await harness.isolation.readCount(
          read: (NotificationCacheScope scope) async {
            expect(scope.ownerUserId, '41');
            expect(scope.environment, 'prod');
            return 8;
          },
        ),
        8,
      );
    });

    test('logged-out unread count is zero without reading storage', () async {
      final _Harness harness = _Harness()..capturedSession = null;
      int reads = 0;

      expect(
        await harness.isolation.readCount(
          read: (NotificationCacheScope scope) async {
            reads++;
            return 99;
          },
        ),
        0,
      );
      expect(reads, 0);
    });

    test('account switch after count read returns zero', () async {
      final _Harness harness = _Harness()
        ..currentResults.addAll(<bool>[true, false]);

      expect(
        await harness.isolation.readCount(
          read: (NotificationCacheScope scope) async => 8,
        ),
        0,
      );
    });
  });

  group('NotificationCacheIsolation mutations (fakes only)', () {
    test('mark-read receives the exact captured account scope', () async {
      final _Harness harness = _Harness();
      final List<String> mutatedScopes = <String>[];

      final bool current = await harness.isolation.mutate(
        mutation: (NotificationCacheScope scope) async {
          mutatedScopes.add('${scope.ownerUserId}:${scope.environment}');
        },
      );

      expect(current, isTrue);
      expect(mutatedScopes, <String>['41:prod']);
      expect(harness.captureCalls, 1);
      expect(harness.currentChecks, 2);
    });

    test('logged-out and unverified mutations do nothing', () async {
      for (final ActivatedAuthSessionSnapshot? session
          in <ActivatedAuthSessionSnapshot?>[null, _unverifiedAccount]) {
        final _Harness harness = _Harness()..capturedSession = session;
        int mutations = 0;

        expect(
          await harness.isolation.mutate(
            mutation: (NotificationCacheScope scope) async {
              mutations++;
            },
          ),
          isFalse,
        );
        expect(mutations, 0);
      }
    });

    test('stale login before mutation does nothing', () async {
      final _Harness harness = _Harness()..currentResults.add(false);
      int mutations = 0;

      expect(
        await harness.isolation.mutate(
          mutation: (NotificationCacheScope scope) async {
            mutations++;
          },
        ),
        isFalse,
      );
      expect(mutations, 0);
    });

    test('account switch after mutation cannot change the mutation scope',
        () async {
      final _Harness harness = _Harness()
        ..currentResults.addAll(<bool>[true, false]);
      final List<String> mutatedOwners = <String>[];

      final bool current = await harness.isolation.mutate(
        mutation: (NotificationCacheScope scope) async {
          harness.capturedSession = _verifiedAccountB;
          mutatedOwners.add(scope.ownerUserId);
        },
      );

      expect(current, isFalse);
      expect(mutatedOwners, <String>['41']);
      expect(mutatedOwners, isNot(contains('52')));
    });

    test('environment switch after mutation reports a stale operation',
        () async {
      final _Harness harness = _Harness()
        ..environmentResults.addAll(<String>['prod', 'prod', 'dev']);
      final List<String> mutatedEnvironments = <String>[];

      expect(
        await harness.isolation.mutate(
          mutation: (NotificationCacheScope scope) async {
            mutatedEnvironments.add(scope.environment);
          },
        ),
        isFalse,
      );
      expect(mutatedEnvironments, <String>['prod']);
    });

    test('delete failures surface instead of pretending rows were removed',
        () async {
      final _Harness harness = _Harness();

      await expectLater(
        harness.isolation.mutate(
          mutation: (NotificationCacheScope scope) async {
            throw StateError('mock scoped delete failure');
          },
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('notification cache lifecycle (in-memory fake only)', () {
    test('send, list, unread, mark-read, and delete stay account/env scoped',
        () async {
      final _Harness harness = _Harness();
      final _FakeNotificationCache cache =
          _FakeNotificationCache(harness.isolation)
            ..seed(
              ownerUserId: '41',
              environment: 'prod',
              title: 'account-a-prod',
            )
            ..seed(
              ownerUserId: '52',
              environment: 'prod',
              title: 'account-b-prod',
            )
            ..seed(
              ownerUserId: '41',
              environment: 'dev',
              title: 'account-a-dev',
            )
            ..seed(
              ownerUserId: null,
              environment: null,
              title: 'legacy-unowned',
            );

      expect(await cache.listTitles(), <String>['account-a-prod']);
      expect(await cache.persist('new-account-a-prod'), isTrue);
      expect(
        await cache.listTitles(),
        <String>['account-a-prod', 'new-account-a-prod'],
      );
      expect(await cache.unreadCount(), 2);

      await cache.markAllRead();
      expect(
        cache.rows
            .where(
                (row) => row.ownerUserId == '41' && row.environment == 'prod')
            .every((row) => !row.unread),
        isTrue,
      );
      expect(
        cache.rows
            .where(
                (row) => row.ownerUserId != '41' || row.environment != 'prod')
            .every((row) => row.unread),
        isTrue,
      );

      harness.capturedSession = _verifiedAccountB;
      expect(await cache.listTitles(), <String>['account-b-prod']);
      expect(await cache.unreadCount(), 1);
      await cache.deleteAll();
      expect(
        cache.rows.any(
          (row) => row.ownerUserId == '52' && row.environment == 'prod',
        ),
        isFalse,
      );
      expect(
        cache.rows.any(
          (row) => row.ownerUserId == '41' && row.environment == 'prod',
        ),
        isTrue,
      );

      harness
        ..capturedSession = _verifiedAccountA
        ..environment = 'dev';
      expect(await cache.listTitles(), <String>['account-a-dev']);
      await cache.deleteAll();
      expect(
        cache.rows.map((row) => row.title),
        containsAll(<String>[
          'account-a-prod',
          'new-account-a-prod',
          'legacy-unowned',
        ]),
      );
      expect(
        cache.rows.map((row) => row.title),
        isNot(contains('account-a-dev')),
      );

      harness.capturedSession = null;
      expect(await cache.listTitles(), isEmpty);
      expect(await cache.unreadCount(), 0);
      await cache.markAllRead();
      expect(
        cache.rows.singleWhere((row) => row.title == 'legacy-unowned').unread,
        isTrue,
      );
    });
  });
}

ActivatedAuthSessionSnapshot _session({required String userId}) {
  return ActivatedAuthSessionSnapshot(
    accessToken: 'mock-token',
    userId: userId,
    subject: 'mock-subject',
    sessionId: 'mock-session',
    verified: true,
  );
}

class _Harness {
  ActivatedAuthSessionSnapshot? capturedSession = _verifiedAccountA;
  String environment = 'prod';
  Object? captureError;
  final List<bool> currentResults = <bool>[];
  final List<Object?> currentErrors = <Object?>[];
  final List<String> environmentResults = <String>[];
  int captureCalls = 0;
  int currentChecks = 0;

  late final NotificationCacheIsolation isolation = NotificationCacheIsolation(
    captureActivatedSession: () async {
      captureCalls++;
      final Object? error = captureError;
      if (error != null) throw error;
      return capturedSession;
    },
    isActivatedSessionCurrent: (ActivatedAuthSessionSnapshot captured) async {
      currentChecks++;
      if (currentErrors.isNotEmpty) {
        final Object? error = currentErrors.removeAt(0);
        if (error != null) throw error;
      }
      if (currentResults.isNotEmpty) return currentResults.removeAt(0);
      final ActivatedAuthSessionSnapshot? current = capturedSession;
      return current != null &&
          current.sessionId == captured.sessionId &&
          current.accessToken == captured.accessToken &&
          current.userId == captured.userId &&
          current.subject == captured.subject &&
          current.verified == captured.verified;
    },
    currentEnvironment: () {
      if (environmentResults.isNotEmpty) {
        return environmentResults.removeAt(0);
      }
      return environment;
    },
  );
}

class _FakeNotificationCache {
  _FakeNotificationCache(this.isolation);

  final NotificationCacheIsolation isolation;
  final List<_FakeNotificationRow> rows = <_FakeNotificationRow>[];
  int _nextId = 1;

  void seed({
    required String? ownerUserId,
    required String? environment,
    required String title,
  }) {
    rows.add(
      _FakeNotificationRow(
        id: _nextId++,
        ownerUserId: ownerUserId,
        environment: environment,
        title: title,
      ),
    );
  }

  Future<bool> persist(String title) {
    return isolation.persist(
      insert: (NotificationCacheScope scope) async {
        final int id = _nextId++;
        rows.add(
          _FakeNotificationRow(
            id: id,
            ownerUserId: scope.ownerUserId,
            environment: scope.environment,
            title: title,
          ),
        );
        return id;
      },
      removeInserted: (NotificationCacheScope scope, int id) async {
        rows.removeWhere(
          (row) =>
              row.id == id &&
              row.ownerUserId == scope.ownerUserId &&
              row.environment == scope.environment,
        );
      },
    );
  }

  Future<List<String>> listTitles() {
    return isolation.readList<String>(
      read: (NotificationCacheScope scope) async {
        return rows
            .where(
              (row) =>
                  row.ownerUserId == scope.ownerUserId &&
                  row.environment == scope.environment,
            )
            .map((row) => row.title)
            .toList();
      },
    );
  }

  Future<int> unreadCount() {
    return isolation.readCount(
      read: (NotificationCacheScope scope) async {
        return rows
            .where(
              (row) =>
                  row.ownerUserId == scope.ownerUserId &&
                  row.environment == scope.environment &&
                  row.unread,
            )
            .length;
      },
    );
  }

  Future<void> markAllRead() async {
    await isolation.mutate(
      mutation: (NotificationCacheScope scope) async {
        for (final _FakeNotificationRow row in rows) {
          if (row.ownerUserId == scope.ownerUserId &&
              row.environment == scope.environment) {
            row.unread = false;
          }
        }
      },
    );
  }

  Future<void> deleteAll() async {
    await isolation.mutate(
      mutation: (NotificationCacheScope scope) async {
        rows.removeWhere(
          (row) =>
              row.ownerUserId == scope.ownerUserId &&
              row.environment == scope.environment,
        );
      },
    );
  }
}

class _FakeNotificationRow {
  _FakeNotificationRow({
    required this.id,
    required this.ownerUserId,
    required this.environment,
    required this.title,
  });

  final int id;
  final String? ownerUserId;
  final String? environment;
  final String title;
  bool unread = true;
}
