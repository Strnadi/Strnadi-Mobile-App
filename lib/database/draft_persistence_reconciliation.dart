/// Immutable account/environment identity used while recording-related local
/// state is read or written.
///
/// A guest snapshot is explicit: both [accessToken] and [userId] are null.
/// An authenticated snapshot contains the complete token, user id, and account
/// email. Partial auth state is rejected by [resolveRecordingOwnerSnapshot].
class RecordingOwnerSnapshot {
  const RecordingOwnerSnapshot._({
    required this.environment,
    required this.backendHost,
    this.accessToken,
    this.userId,
    this.accountEmail,
    this.logicalSessionId,
  });

  const RecordingOwnerSnapshot.guest({
    required String environment,
    required String backendHost,
  }) : this._(
          environment: environment,
          backendHost: backendHost,
        );

  const RecordingOwnerSnapshot.authenticated({
    required String accessToken,
    required String userId,
    required String accountEmail,
    required String logicalSessionId,
    required String environment,
    required String backendHost,
  }) : this._(
          accessToken: accessToken,
          userId: userId,
          accountEmail: accountEmail,
          logicalSessionId: logicalSessionId,
          environment: environment,
          backendHost: backendHost,
        );

  final String? accessToken;
  final String? userId;
  final String? accountEmail;
  final String? logicalSessionId;
  final String environment;
  final String backendHost;

  bool get isGuest => accessToken == null;
}

/// Resolves a complete authenticated identity or an explicit guest identity.
///
/// Secure-storage keys are read independently, so treating a lone token or a
/// lone user id as a guest can silently bind a recording to the wrong account.
/// Such mixed snapshots fail closed.
RecordingOwnerSnapshot resolveRecordingOwnerSnapshot({
  required String? accessToken,
  required String? userId,
  required String? accountEmail,
  required String? logicalSessionId,
  required String environment,
  required String backendHost,
}) {
  final String token = accessToken ?? '';
  final String ownerId = userId?.trim() ?? '';
  final String email = accountEmail?.trim() ?? '';
  final String sessionId = logicalSessionId?.trim() ?? '';
  final String capturedEnvironment = environment.trim();
  final String capturedHost = backendHost.trim();
  if (capturedEnvironment.isEmpty || capturedHost.isEmpty) {
    throw StateError('A recording owner snapshot has no backend scope.');
  }

  final bool hasToken = token.trim().isNotEmpty;
  final bool hasUserId = ownerId.isNotEmpty;
  if (!hasToken && !hasUserId && email.isEmpty && sessionId.isEmpty) {
    return RecordingOwnerSnapshot.guest(
      environment: capturedEnvironment,
      backendHost: capturedHost,
    );
  }

  final int? numericUserId = int.tryParse(ownerId);
  if (!hasToken ||
      !hasUserId ||
      numericUserId == null ||
      numericUserId <= 0 ||
      email.isEmpty ||
      sessionId.isEmpty) {
    throw StateError('Recording authentication changed while being captured.');
  }
  return RecordingOwnerSnapshot.authenticated(
    accessToken: token,
    userId: ownerId,
    accountEmail: email,
    logicalSessionId: sessionId,
    environment: capturedEnvironment,
    backendHost: capturedHost,
  );
}

/// Compares a previously captured owner/backend scope with a later secure
/// storage/config read. This is pure so delayed-dialog account and environment
/// changes can be tested without real secure storage.
bool recordingOwnerSnapshotIsCurrent({
  required RecordingOwnerSnapshot snapshot,
  required String? accessToken,
  required String? userId,
  required String? accountEmail,
  required String? logicalSessionId,
  required String environment,
  required String backendHost,
}) {
  final bool sameAuthentication = snapshot.isGuest
      ? (accessToken?.trim().isEmpty ?? true) &&
          (userId?.trim().isEmpty ?? true) &&
          (accountEmail?.trim().isEmpty ?? true) &&
          (logicalSessionId?.trim().isEmpty ?? true)
      : accessToken == snapshot.accessToken &&
          userId?.trim() == snapshot.userId &&
          accountEmail?.trim().toLowerCase() ==
              snapshot.accountEmail?.trim().toLowerCase() &&
          logicalSessionId?.trim() == snapshot.logicalSessionId;
  return sameAuthentication &&
      environment == snapshot.environment &&
      backendHost == snapshot.backendHost;
}

/// Validates the durable owner columns of a recording against a captured
/// logical session. Authenticated rows require the exact user id and email;
/// guest rows require both owner columns to remain explicitly unowned.
bool recordingOwnerBindingMatchesSnapshot({
  required RecordingOwnerSnapshot snapshot,
  required Object? persistedUserId,
  required String? persistedEmail,
  required String persistedEnvironment,
}) {
  if (persistedEnvironment.trim() != snapshot.environment) return false;
  final String email = persistedEmail?.trim() ?? '';
  if (snapshot.isGuest) {
    return persistedUserId == null && email.isEmpty;
  }

  final int? userId = _integralId(persistedUserId);
  return userId == int.parse(snapshot.userId!) &&
      email.toLowerCase() == snapshot.accountEmail!.trim().toLowerCase();
}

enum RecordingDraftCommitState {
  definitelyAbsent,
  mayHaveCommitted,
}

/// Reports whether a failed draft insert was proved absent or may already be
/// durable. Callers must retain source media for the ambiguous state.
class RecordingDraftPersistenceException implements Exception {
  const RecordingDraftPersistenceException(
    this.cause, {
    required this.commitState,
  });

  final Object cause;
  final RecordingDraftCommitState commitState;

  bool get mayHaveCommitted =>
      commitState == RecordingDraftCommitState.mayHaveCommitted;

  @override
  String toString() =>
      'RecordingDraftPersistenceException($commitState): $cause';
}

/// Temporary source files are disposable only when no local id exists and a
/// failed transaction has been conclusively reconciled as absent.
bool canDeleteUnpersistedDraftFiles({
  required bool hasPersistedId,
  required bool persistenceMayHaveCommitted,
}) {
  return !hasPersistedId && !persistenceMayHaveCommitted;
}

class PersistedDraftIdentity {
  const PersistedDraftIdentity({
    required this.recordingId,
    required this.partIdsByUploadKey,
    required this.dialectIdsByUploadKey,
  });

  final int recordingId;
  final Map<String, int> partIdsByUploadKey;
  final Map<String, int> dialectIdsByUploadKey;
}

/// Reconciles the identity of an atomic draft insert after an ambiguous
/// database acknowledgment.
///
/// The function is deliberately independent of SQLite so its fail-closed
/// behavior can be verified with plain maps. A present parent is accepted only
/// when every expected child key exists exactly once under that same parent and
/// no unexpected child rows are present.
PersistedDraftIdentity? reconcilePersistedDraftIdentity({
  required RecordingOwnerSnapshot ownerSnapshot,
  required String recordingUploadKey,
  required Iterable<String> expectedPartUploadKeys,
  required Iterable<String> expectedDialectUploadKeys,
  required List<Map<String, Object?>> recordingRows,
  required List<Map<String, Object?>> partRows,
  required List<Map<String, Object?>> dialectRows,
}) {
  final String recordingKey = recordingUploadKey.trim();
  if (recordingKey.isEmpty) {
    throw ArgumentError.value(
      recordingUploadKey,
      'recordingUploadKey',
      'must not be empty',
    );
  }
  if (recordingRows.isEmpty) return null;
  if (recordingRows.length != 1) {
    throw StateError('A draft upload key resolved to multiple recordings.');
  }

  final Map<String, Object?> recordingRow = recordingRows.single;
  final int recordingId = _positiveId(recordingRow['id'], 'recording');
  if ((recordingRow['uploadKey'] as String? ?? '').trim() != recordingKey) {
    throw StateError('The reconciled recording upload key changed.');
  }
  _validatePersistedDraftOwner(recordingRow, ownerSnapshot);

  final Set<String> expectedPartKeys =
      _expectedKeys(expectedPartUploadKeys, 'recording part');
  final Set<String> expectedDialectKeys =
      _expectedKeys(expectedDialectUploadKeys, 'dialect');
  final Map<String, int> partIds = _childIdentities(
    partRows,
    expectedPartKeys,
    recordingId,
    entity: 'recording part',
  );
  final Map<String, int> dialectIds = _childIdentities(
    dialectRows,
    expectedDialectKeys,
    recordingId,
    entity: 'dialect',
  );

  return PersistedDraftIdentity(
    recordingId: recordingId,
    partIdsByUploadKey: Map<String, int>.unmodifiable(partIds),
    dialectIdsByUploadKey: Map<String, int>.unmodifiable(dialectIds),
  );
}

void _validatePersistedDraftOwner(
  Map<String, Object?> recordingRow,
  RecordingOwnerSnapshot ownerSnapshot,
) {
  if (!recordingOwnerBindingMatchesSnapshot(
    snapshot: ownerSnapshot,
    persistedUserId: recordingRow['userId'],
    persistedEmail: recordingRow['mail'] as String?,
    persistedEnvironment: recordingRow['env'] as String? ?? '',
  )) {
    throw StateError('The reconciled recording belongs to another account.');
  }
}

int? _integralId(Object? raw) {
  if (raw is int) return raw > 0 ? raw : null;
  if (raw is num && raw.isFinite && raw == raw.truncate() && raw > 0) {
    return raw.toInt();
  }
  final int? parsed = int.tryParse(raw?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

Set<String> _expectedKeys(Iterable<String> rawKeys, String entity) {
  final List<String> keys =
      rawKeys.map((key) => key.trim()).toList(growable: false);
  if (keys.any((key) => key.isEmpty)) {
    throw StateError('An expected $entity upload key is empty.');
  }
  final Set<String> unique = keys.toSet();
  if (unique.length != keys.length) {
    throw StateError('Expected $entity upload keys are not unique.');
  }
  return unique;
}

Map<String, int> _childIdentities(
  List<Map<String, Object?>> rows,
  Set<String> expectedKeys,
  int recordingId, {
  required String entity,
}) {
  if (rows.length != expectedKeys.length) {
    throw StateError(
      'The reconciled $entity set is incomplete or contains extra rows.',
    );
  }

  final Map<String, int> identities = <String, int>{};
  for (final Map<String, Object?> row in rows) {
    if (row['recordingId'] != recordingId) {
      throw StateError('A reconciled $entity belongs to another recording.');
    }
    final String key = (row['uploadKey'] as String? ?? '').trim();
    if (!expectedKeys.contains(key)) {
      throw StateError('The reconciled $entity upload key is unexpected.');
    }
    final int id = _positiveId(row['id'], entity);
    if (identities.putIfAbsent(key, () => id) != id) {
      throw StateError('A reconciled $entity upload key is duplicated.');
    }
  }
  if (identities.length != expectedKeys.length) {
    throw StateError('A reconciled $entity upload key is duplicated.');
  }
  return identities;
}

int _positiveId(Object? raw, String entity) {
  final int? id = raw is int
      ? raw
      : raw is num && raw.isFinite && raw == raw.truncate()
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '');
  if (id == null || id <= 0) {
    throw StateError('The reconciled $entity has an invalid local id.');
  }
  return id;
}
