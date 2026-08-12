import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';

const RecordingOwnerSnapshot _authenticatedOwner =
    RecordingOwnerSnapshot.authenticated(
  accessToken: 'token-a',
  userId: '42',
  accountEmail: 'bird@example.test',
  logicalSessionId: 'session-a',
  environment: 'development',
  backendHost: 'dev.example.test',
);

const RecordingOwnerSnapshot _guestOwner = RecordingOwnerSnapshot.guest(
  environment: 'development',
  backendHost: 'dev.example.test',
);

Map<String, Object?> _recordingRow({
  int id = 42,
  String uploadKey = 'recording-key',
  Object? userId = 42,
  String? mail = 'bird@example.test',
  String env = 'development',
}) {
  return <String, Object?>{
    'id': id,
    'uploadKey': uploadKey,
    'userId': userId,
    'mail': mail,
    'env': env,
  };
}

Map<String, Object?> _childRow({
  required int id,
  required String uploadKey,
  int recordingId = 42,
}) {
  return <String, Object?>{
    'id': id,
    'recordingId': recordingId,
    'uploadKey': uploadKey,
  };
}

void main() {
  group('recording owner snapshots (pure values, no API or DB)', () {
    test('captures an explicit guest with a fixed backend scope', () {
      final RecordingOwnerSnapshot snapshot = resolveRecordingOwnerSnapshot(
        accessToken: null,
        userId: null,
        accountEmail: null,
        logicalSessionId: null,
        environment: ' development ',
        backendHost: ' dev.example.test ',
      );

      expect(snapshot.isGuest, isTrue);
      expect(snapshot.accessToken, isNull);
      expect(snapshot.userId, isNull);
      expect(snapshot.accountEmail, isNull);
      expect(snapshot.environment, 'development');
      expect(snapshot.backendHost, 'dev.example.test');
    });

    test('captures one complete authenticated identity', () {
      final RecordingOwnerSnapshot snapshot = resolveRecordingOwnerSnapshot(
        accessToken: 'signed-token',
        userId: ' 42 ',
        accountEmail: ' bird@example.test ',
        logicalSessionId: ' session-a ',
        environment: 'production',
        backendHost: 'api.example.test',
      );

      expect(snapshot.isGuest, isFalse);
      expect(snapshot.accessToken, 'signed-token');
      expect(snapshot.userId, '42');
      expect(snapshot.accountEmail, 'bird@example.test');
      expect(snapshot.logicalSessionId, 'session-a');
    });

    for (final (
          String description,
          String? token,
          String? userId,
          String? email,
        ) in <(String, String?, String?, String?)>[
      ('token without user id', 'token', null, 'bird@example.test'),
      ('user id without token', null, '42', 'bird@example.test'),
      ('authenticated state without email', 'token', '42', null),
      ('non-numeric user id', 'token', 'not-an-id', 'bird@example.test'),
      ('non-positive user id', 'token', '0', 'bird@example.test'),
    ]) {
      test('rejects $description', () {
        expect(
          () => resolveRecordingOwnerSnapshot(
            accessToken: token,
            userId: userId,
            accountEmail: email,
            logicalSessionId: token == null ? null : 'session-a',
            environment: 'development',
            backendHost: 'dev.example.test',
          ),
          throwsStateError,
        );
      });
    }

    test('rejects a snapshot without a stable environment or host', () {
      expect(
        () => resolveRecordingOwnerSnapshot(
          accessToken: null,
          userId: null,
          accountEmail: null,
          logicalSessionId: null,
          environment: '',
          backendHost: 'dev.example.test',
        ),
        throwsStateError,
      );
      expect(
        () => resolveRecordingOwnerSnapshot(
          accessToken: null,
          userId: null,
          accountEmail: null,
          logicalSessionId: null,
          environment: 'development',
          backendHost: ' ',
        ),
        throwsStateError,
      );
    });

    test('rejects authenticated credentials without a logical session id', () {
      expect(
        () => resolveRecordingOwnerSnapshot(
          accessToken: 'token-a',
          userId: '42',
          accountEmail: 'bird@example.test',
          logicalSessionId: null,
          environment: 'development',
          backendHost: 'dev.example.test',
        ),
        throwsStateError,
      );
    });

    test('accepts only the same delayed authenticated dialog identity', () {
      expect(
        recordingOwnerSnapshotIsCurrent(
          snapshot: _authenticatedOwner,
          accessToken: 'token-a',
          userId: '42',
          accountEmail: 'bird@example.test',
          logicalSessionId: 'session-a',
          environment: 'development',
          backendHost: 'dev.example.test',
        ),
        isTrue,
      );

      for (final (
            String? token,
            String? userId,
            String environment,
            String host,
          ) in <(String?, String?, String, String)>[
        ('token-b', '42', 'development', 'dev.example.test'),
        ('token-a', '84', 'development', 'dev.example.test'),
        ('token-a', '42', 'production', 'dev.example.test'),
        ('token-a', '42', 'development', 'api.example.test'),
        (null, null, 'development', 'dev.example.test'),
      ]) {
        expect(
          recordingOwnerSnapshotIsCurrent(
            snapshot: _authenticatedOwner,
            accessToken: token,
            userId: userId,
            accountEmail: 'bird@example.test',
            logicalSessionId: 'session-a',
            environment: environment,
            backendHost: host,
          ),
          isFalse,
        );
      }
    });

    test('same credentials from a new logical login make a snapshot stale', () {
      expect(
        recordingOwnerSnapshotIsCurrent(
          snapshot: _authenticatedOwner,
          accessToken: 'token-a',
          userId: '42',
          accountEmail: 'bird@example.test',
          logicalSessionId: 'session-b',
          environment: 'development',
          backendHost: 'dev.example.test',
        ),
        isFalse,
      );
    });

    test('guest dialog identity becomes stale on login or environment change',
        () {
      expect(
        recordingOwnerSnapshotIsCurrent(
          snapshot: _guestOwner,
          accessToken: null,
          userId: null,
          accountEmail: null,
          logicalSessionId: null,
          environment: 'development',
          backendHost: 'dev.example.test',
        ),
        isTrue,
      );
      expect(
        recordingOwnerSnapshotIsCurrent(
          snapshot: _guestOwner,
          accessToken: 'token-a',
          userId: '42',
          accountEmail: 'bird@example.test',
          logicalSessionId: 'session-a',
          environment: 'development',
          backendHost: 'dev.example.test',
        ),
        isFalse,
      );
      expect(
        recordingOwnerSnapshotIsCurrent(
          snapshot: _guestOwner,
          accessToken: null,
          userId: null,
          accountEmail: null,
          logicalSessionId: null,
          environment: 'production',
          backendHost: 'api.example.test',
        ),
        isFalse,
      );
    });

    test('authenticated draft binding requires exact owner and environment',
        () {
      expect(
        recordingOwnerBindingMatchesSnapshot(
          snapshot: _authenticatedOwner,
          persistedUserId: 42,
          persistedEmail: 'BIRD@example.test',
          persistedEnvironment: 'development',
        ),
        isTrue,
      );

      for (final (
            Object? userId,
            String? email,
            String environment,
          ) in <(Object?, String?, String)>[
        (null, 'bird@example.test', 'development'),
        (84, 'bird@example.test', 'development'),
        (42.5, 'bird@example.test', 'development'),
        (42, 'other@example.test', 'development'),
        (42, 'bird@example.test', 'production'),
      ]) {
        expect(
          recordingOwnerBindingMatchesSnapshot(
            snapshot: _authenticatedOwner,
            persistedUserId: userId,
            persistedEmail: email,
            persistedEnvironment: environment,
          ),
          isFalse,
        );
      }
    });

    test('guest draft binding rejects every account-owned row', () {
      expect(
        recordingOwnerBindingMatchesSnapshot(
          snapshot: _guestOwner,
          persistedUserId: null,
          persistedEmail: ' ',
          persistedEnvironment: 'development',
        ),
        isTrue,
      );
      expect(
        recordingOwnerBindingMatchesSnapshot(
          snapshot: _guestOwner,
          persistedUserId: 42,
          persistedEmail: '',
          persistedEnvironment: 'development',
        ),
        isFalse,
      );
      expect(
        recordingOwnerBindingMatchesSnapshot(
          snapshot: _guestOwner,
          persistedUserId: null,
          persistedEmail: 'bird@example.test',
          persistedEnvironment: 'development',
        ),
        isFalse,
      );
      expect(
        recordingOwnerBindingMatchesSnapshot(
          snapshot: _guestOwner,
          persistedUserId: null,
          persistedEmail: '',
          persistedEnvironment: 'production',
        ),
        isFalse,
      );
    });
  });

  group('failed draft file ownership (pure values, no API or DB)', () {
    test('allows deletion only after absence is proven and no id exists', () {
      expect(
        canDeleteUnpersistedDraftFiles(
          hasPersistedId: false,
          persistenceMayHaveCommitted: false,
        ),
        isTrue,
      );
    });

    test('retains files when an insert may have committed but ids are absent',
        () {
      expect(
        canDeleteUnpersistedDraftFiles(
          hasPersistedId: false,
          persistenceMayHaveCommitted: true,
        ),
        isFalse,
      );
    });

    test('retains files whenever a persisted id exists', () {
      expect(
        canDeleteUnpersistedDraftFiles(
          hasPersistedId: true,
          persistenceMayHaveCommitted: false,
        ),
        isFalse,
      );
      expect(
        canDeleteUnpersistedDraftFiles(
          hasPersistedId: true,
          persistenceMayHaveCommitted: true,
        ),
        isFalse,
      );
    });

    test('persistence exception exposes its fail-closed commit state', () {
      const RecordingDraftPersistenceException absent =
          RecordingDraftPersistenceException(
        'rolled back',
        commitState: RecordingDraftCommitState.definitelyAbsent,
      );
      const RecordingDraftPersistenceException ambiguous =
          RecordingDraftPersistenceException(
        'database acknowledgment lost',
        commitState: RecordingDraftCommitState.mayHaveCommitted,
      );

      expect(absent.mayHaveCommitted, isFalse);
      expect(ambiguous.mayHaveCommitted, isTrue);
    });
  });

  group('ambiguous draft commit reconciliation (pure maps, no DB)', () {
    test('returns null when the parent commit is absent', () {
      final PersistedDraftIdentity? result = reconcilePersistedDraftIdentity(
        ownerSnapshot: _authenticatedOwner,
        recordingUploadKey: 'recording-key',
        expectedPartUploadKeys: const <String>['part-a'],
        expectedDialectUploadKeys: const <String>[],
        recordingRows: const <Map<String, Object?>>[],
        partRows: const <Map<String, Object?>>[],
        dialectRows: const <Map<String, Object?>>[],
      );

      expect(result, isNull);
    });

    test('recovers every local id from durable upload keys', () {
      final PersistedDraftIdentity result = reconcilePersistedDraftIdentity(
        ownerSnapshot: _authenticatedOwner,
        recordingUploadKey: 'recording-key',
        expectedPartUploadKeys: const <String>['part-a', 'part-b'],
        expectedDialectUploadKeys: const <String>['dialect-a'],
        recordingRows: <Map<String, Object?>>[_recordingRow()],
        partRows: <Map<String, Object?>>[
          _childRow(id: 101, uploadKey: 'part-b'),
          _childRow(id: 100, uploadKey: 'part-a'),
        ],
        dialectRows: <Map<String, Object?>>[
          _childRow(id: 200, uploadKey: 'dialect-a'),
        ],
      )!;

      expect(result.recordingId, 42);
      expect(
        result.partIdsByUploadKey,
        <String, int>{'part-a': 100, 'part-b': 101},
      );
      expect(result.dialectIdsByUploadKey, <String, int>{'dialect-a': 200});
    });

    test('accepts an explicitly unowned guest draft only for that environment',
        () {
      final PersistedDraftIdentity? result = reconcilePersistedDraftIdentity(
        ownerSnapshot: _guestOwner,
        recordingUploadKey: 'recording-key',
        expectedPartUploadKeys: const <String>[],
        expectedDialectUploadKeys: const <String>[],
        recordingRows: <Map<String, Object?>>[
          _recordingRow(userId: null, mail: ''),
        ],
        partRows: const <Map<String, Object?>>[],
        dialectRows: const <Map<String, Object?>>[],
      );

      expect(result?.recordingId, 42);
    });

    test('never adopts an account draft during guest reconciliation', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _guestOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>[],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: const <Map<String, Object?>>[],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('account-switch retry never adopts the first account commit', () {
      const RecordingOwnerSnapshot secondAccount =
          RecordingOwnerSnapshot.authenticated(
        accessToken: 'token-b',
        userId: '84',
        accountEmail: 'other@example.test',
        logicalSessionId: 'session-b',
        environment: 'development',
        backendHost: 'dev.example.test',
      );

      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: secondAccount,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>[],
          expectedDialectUploadKeys: const <String>[],
          // This row represents an earlier ambiguous commit by account A.
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: const <Map<String, Object?>>[],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
      expect(
        canDeleteUnpersistedDraftFiles(
          hasPersistedId: false,
          persistenceMayHaveCommitted: true,
        ),
        isFalse,
      );
    });

    for (final (
          String description,
          Map<String, Object?> row,
        ) in <(String, Map<String, Object?>)>[
      (
        'different user id',
        _recordingRow(userId: 84),
      ),
      (
        'different account email',
        _recordingRow(mail: 'other@example.test'),
      ),
      (
        'different environment',
        _recordingRow(env: 'production'),
      ),
    ]) {
      test('fails closed for a persisted draft with $description', () {
        expect(
          () => reconcilePersistedDraftIdentity(
            ownerSnapshot: _authenticatedOwner,
            recordingUploadKey: 'recording-key',
            expectedPartUploadKeys: const <String>[],
            expectedDialectUploadKeys: const <String>[],
            recordingRows: <Map<String, Object?>>[row],
            partRows: const <Map<String, Object?>>[],
            dialectRows: const <Map<String, Object?>>[],
          ),
          throwsStateError,
        );
      });
    }

    test('fails closed when a persisted part is missing', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>['part-a', 'part-b'],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: <Map<String, Object?>>[
            _childRow(id: 100, uploadKey: 'part-a'),
          ],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('fails closed when an unexpected child row is present', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>['part-a'],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: <Map<String, Object?>>[
            _childRow(id: 100, uploadKey: 'part-a'),
            _childRow(id: 101, uploadKey: 'part-extra'),
          ],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('fails closed when a child belongs to another parent', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>['part-a'],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: <Map<String, Object?>>[
            _childRow(id: 100, uploadKey: 'part-a', recordingId: 99),
          ],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('fails closed when expected upload keys are duplicated', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>['part-a', 'part-a'],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[_recordingRow()],
          partRows: <Map<String, Object?>>[
            _childRow(id: 100, uploadKey: 'part-a'),
          ],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('fails closed when the recording upload key changes', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>[],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: <Map<String, Object?>>[
            _recordingRow(uploadKey: 'other-recording-key'),
          ],
          partRows: const <Map<String, Object?>>[],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });

    test('fails closed when a persisted local id is non-integral', () {
      expect(
        () => reconcilePersistedDraftIdentity(
          ownerSnapshot: _authenticatedOwner,
          recordingUploadKey: 'recording-key',
          expectedPartUploadKeys: const <String>[],
          expectedDialectUploadKeys: const <String>[],
          recordingRows: const <Map<String, Object?>>[
            <String, Object?>{
              'id': 42.5,
              'uploadKey': 'recording-key',
            },
          ],
          partRows: const <Map<String, Object?>>[],
          dialectRows: const <Map<String, Object?>>[],
        ),
        throwsStateError,
      );
    });
  });
}
