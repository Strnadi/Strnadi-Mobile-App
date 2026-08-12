import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_cache_access.dart';
import 'package:strnadi/database/recording_upload_service.dart';

void main() {
  group('downloaded recording cache account isolation', () {
    test('guest list is empty without reading persistence', () async {
      final _FakeSessions sessions = _FakeSessions(session: null);
      var persistenceReads = 0;

      final List<_CacheRow> rows =
          await listDownloadedRecordingCacheForActivatedOwner<_CacheRow>(
        sessions: sessions,
        loadOwnedEntries: (_) async {
          persistenceReads++;
          return <_CacheRow>[];
        },
      );

      expect(rows, isEmpty);
      expect(persistenceReads, 0);
      expect(sessions.captureCalls, 1);
      expect(sessions.currentChecks, 0);
    });

    test('guest delete fails without invoking persistence', () async {
      final _FakeSessions sessions = _FakeSessions(session: null);
      var persistenceDeletes = 0;

      await expectLater(
        deleteDownloadedRecordingCacheForActivatedOwner(
          recordingId: 12,
          sessions: sessions,
          deleteOwnedEntry: (_, __, ___) async {
            persistenceDeletes++;
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(persistenceDeletes, 0);
      expect(sessions.currentChecks, 0);
    });

    test('list returns only exact owner and environment rows', () async {
      final RecordingUploadSession session = _session();
      final _FakeSessions sessions = _FakeSessions(session: session);
      final _FakeCacheStore store = _FakeCacheStore(<_CacheRow>[
        const _CacheRow(1, 'prod', 41, 'bird@example.test'),
        const _CacheRow(2, 'dev', 41, 'bird@example.test'),
        const _CacheRow(3, 'prod', 99, 'bird@example.test'),
        const _CacheRow(4, 'prod', 41, 'other@example.test'),
        const _CacheRow(5, 'prod', null, ''),
        const _CacheRow(6, 'prod', 41, 'BIRD@EXAMPLE.TEST'),
      ]);

      final List<_CacheRow> rows =
          await listDownloadedRecordingCacheForActivatedOwner<_CacheRow>(
        sessions: sessions,
        loadOwnedEntries: store.load,
      );

      expect(rows.map((_CacheRow row) => row.id), <int>[1, 6]);
      expect(sessions.currentChecks, 2);
      expect(
        () => rows.add(const _CacheRow(7, 'prod', 41, 'bird@example.test')),
        throwsUnsupportedError,
      );
    });

    test('list does not return rows when login changes after the read',
        () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(),
        currentResults: <bool>[true, false],
      );
      var persistenceReads = 0;

      await expectLater(
        listDownloadedRecordingCacheForActivatedOwner<int>(
          sessions: sessions,
          loadOwnedEntries: (_) async {
            persistenceReads++;
            return <int>[1];
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(persistenceReads, 1);
      expect(sessions.currentChecks, 2);
    });

    test('stale login is rejected before persistence is read', () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(),
        currentResults: <bool>[false],
      );
      var persistenceReads = 0;

      await expectLater(
        listDownloadedRecordingCacheForActivatedOwner<int>(
          sessions: sessions,
          loadOwnedEntries: (_) async {
            persistenceReads++;
            return <int>[1];
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(persistenceReads, 0);
    });

    test('invalid activated owner email fails closed', () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(accountEmail: '  '),
      );
      var persistenceReads = 0;

      await expectLater(
        listDownloadedRecordingCacheForActivatedOwner<int>(
          sessions: sessions,
          loadOwnedEntries: (_) async {
            persistenceReads++;
            return <int>[1];
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(persistenceReads, 0);
      expect(sessions.currentChecks, 0);
    });

    test('invalid activated user id fails closed', () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(userId: '0'),
      );

      await expectLater(
        listDownloadedRecordingCacheForActivatedOwner<int>(
          sessions: sessions,
          loadOwnedEntries: (_) async => <int>[1],
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );
      expect(sessions.currentChecks, 0);
    });

    test('invalid local id is rejected before session capture', () async {
      final _FakeSessions sessions = _FakeSessions(session: _session());

      await expectLater(
        deleteDownloadedRecordingCacheForActivatedOwner(
          recordingId: 0,
          sessions: sessions,
          deleteOwnedEntry: (_, __, ___) async {},
        ),
        throwsA(isA<RecordingUploadValidationException>()),
      );

      expect(sessions.captureCalls, 0);
      expect(sessions.currentChecks, 0);
    });

    test('delete removes only an exact current-owner row', () async {
      final _FakeSessions sessions = _FakeSessions(session: _session());
      final _FakeCacheStore store = _FakeCacheStore(<_CacheRow>[
        const _CacheRow(1, 'prod', 41, 'bird@example.test'),
        const _CacheRow(2, 'dev', 41, 'bird@example.test'),
        const _CacheRow(3, 'prod', 99, 'bird@example.test'),
      ]);

      await deleteDownloadedRecordingCacheForActivatedOwner(
        recordingId: 1,
        sessions: sessions,
        deleteOwnedEntry: store.delete,
      );

      expect(store.rows.map((_CacheRow row) => row.id), <int>[2, 3]);
      expect(store.deleteCalls, 1);
      expect(sessions.currentChecks, 3);
    });

    test('delete cannot remove another environment row', () async {
      final _FakeSessions sessions = _FakeSessions(session: _session());
      final _FakeCacheStore store = _FakeCacheStore(<_CacheRow>[
        const _CacheRow(2, 'dev', 41, 'bird@example.test'),
      ]);

      await expectLater(
        deleteDownloadedRecordingCacheForActivatedOwner(
          recordingId: 2,
          sessions: sessions,
          deleteOwnedEntry: store.delete,
        ),
        throwsA(isA<RecordingUploadValidationException>()),
      );

      expect(store.rows.single.id, 2);
    });

    test('delete cannot remove another account row', () async {
      final _FakeSessions sessions = _FakeSessions(session: _session());
      final _FakeCacheStore store = _FakeCacheStore(<_CacheRow>[
        const _CacheRow(3, 'prod', 99, 'bird@example.test'),
        const _CacheRow(4, 'prod', 41, 'other@example.test'),
      ]);

      for (final int id in <int>[3, 4]) {
        await expectLater(
          deleteDownloadedRecordingCacheForActivatedOwner(
            recordingId: id,
            sessions: sessions,
            deleteOwnedEntry: store.delete,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      }

      expect(store.rows.map((_CacheRow row) => row.id), <int>[3, 4]);
    });

    test('delete aborts before commit when logical login changes', () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(),
        currentResults: <bool>[true, true, false],
      );
      final _FakeCacheStore store = _FakeCacheStore(<_CacheRow>[
        const _CacheRow(1, 'prod', 41, 'bird@example.test'),
      ]);

      await expectLater(
        deleteDownloadedRecordingCacheForActivatedOwner(
          recordingId: 1,
          sessions: sessions,
          deleteOwnedEntry: store.delete,
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(store.rows.single.id, 1);
      expect(sessions.currentChecks, 3);
    });

    test('delete is rejected before persistence when session is stale',
        () async {
      final _FakeSessions sessions = _FakeSessions(
        session: _session(),
        currentResults: <bool>[false],
      );
      var persistenceDeletes = 0;

      await expectLater(
        deleteDownloadedRecordingCacheForActivatedOwner(
          recordingId: 1,
          sessions: sessions,
          deleteOwnedEntry: (_, __, ___) async {
            persistenceDeletes++;
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(persistenceDeletes, 0);
    });

    test('owner matcher normalizes email but requires exact id and env', () {
      final RecordingCacheOwner owner =
          RecordingCacheOwner.fromSession(_session());

      expect(
        recordingCacheEntryMatchesOwner(
          entryEnvironment: 'prod',
          entryUserId: 41,
          entryEmail: ' BIRD@EXAMPLE.TEST ',
          owner: owner,
        ),
        isTrue,
      );
      expect(
        recordingCacheEntryMatchesOwner(
          entryEnvironment: 'dev',
          entryUserId: 41,
          entryEmail: 'bird@example.test',
          owner: owner,
        ),
        isFalse,
      );
      expect(
        recordingCacheEntryMatchesOwner(
          entryEnvironment: 'prod',
          entryUserId: null,
          entryEmail: 'bird@example.test',
          owner: owner,
        ),
        isFalse,
      );
      expect(
        recordingCacheEntryMatchesOwner(
          entryEnvironment: 'prod',
          entryUserId: 41,
          entryEmail: null,
          owner: owner,
        ),
        isFalse,
      );
    });

    test('owner passed to persistence retains pinned logical session',
        () async {
      final RecordingUploadSession session =
          _session(logicalSessionId: 'logical-login-22');
      final _FakeSessions sessions = _FakeSessions(session: session);
      RecordingCacheOwner? observed;

      await deleteDownloadedRecordingCacheForActivatedOwner(
        recordingId: 8,
        sessions: sessions,
        deleteOwnedEntry: (_, RecordingCacheOwner owner, requireCurrent) async {
          observed = owner;
          await requireCurrent();
        },
      );

      expect(observed?.userId, 41);
      expect(observed?.email, 'bird@example.test');
      expect(observed?.environment, 'prod');
      expect(observed?.session.logicalSessionId, 'logical-login-22');
      expect(identical(observed?.session, session), isTrue);
    });
  });
}

RecordingUploadSession _session({
  String userId = '41',
  String logicalSessionId = 'logical-login-1',
  String? accountEmail = 'bird@example.test',
}) {
  return RecordingUploadSession(
    userId: userId,
    accessToken: 'opaque-access-token',
    logicalSessionId: logicalSessionId,
    environment: 'prod',
    backendHost: 'https://api.example.test',
    accountEmail: accountEmail,
  );
}

class _FakeSessions implements RecordingUploadSessionProvider {
  _FakeSessions({
    required this.session,
    List<bool> currentResults = const <bool>[true],
  }) : _currentResults = List<bool>.of(currentResults);

  final RecordingUploadSession? session;
  final List<bool> _currentResults;
  int captureCalls = 0;
  int currentChecks = 0;

  @override
  Future<RecordingUploadSession?> capture() async {
    captureCalls++;
    return session;
  }

  @override
  Future<bool> isCurrent(RecordingUploadSession checked) async {
    currentChecks++;
    expect(identical(checked, session), isTrue);
    if (_currentResults.isEmpty) return true;
    return _currentResults.removeAt(0);
  }
}

class _CacheRow {
  const _CacheRow(this.id, this.environment, this.userId, this.email);

  final int id;
  final String environment;
  final int? userId;
  final String? email;
}

class _FakeCacheStore {
  _FakeCacheStore(List<_CacheRow> rows) : rows = List<_CacheRow>.of(rows);

  final List<_CacheRow> rows;
  int deleteCalls = 0;

  Future<List<_CacheRow>> load(RecordingCacheOwner owner) async {
    return rows
        .where(
          (_CacheRow row) => recordingCacheEntryMatchesOwner(
            entryEnvironment: row.environment,
            entryUserId: row.userId,
            entryEmail: row.email,
            owner: owner,
          ),
        )
        .toList(growable: false);
  }

  Future<void> delete(
    int recordingId,
    RecordingCacheOwner owner,
    RecordingCacheSessionGuard requireSessionCurrent,
  ) async {
    deleteCalls++;
    await requireSessionCurrent();
    final int index = rows.indexWhere(
      (_CacheRow row) =>
          row.id == recordingId &&
          recordingCacheEntryMatchesOwner(
            entryEnvironment: row.environment,
            entryUserId: row.userId,
            entryEmail: row.email,
            owner: owner,
          ),
    );
    if (index < 0) {
      throw const RecordingUploadValidationException(
        'The owned cache entry does not exist.',
      );
    }
    await requireSessionCurrent();
    rows.removeAt(index);
  }
}
