import 'package:strnadi/database/recording_upload_service.dart';

/// The exact activated owner and backend environment allowed to inspect or
/// mutate downloaded recording cache entries.
///
/// The underlying [session] is retained so persistence adapters can re-check
/// the same logical login immediately before committing a mutation.
class RecordingCacheOwner {
  const RecordingCacheOwner._({
    required this.session,
    required this.userId,
    required this.email,
    required this.normalizedEmail,
    required this.environment,
  });

  factory RecordingCacheOwner.fromSession(RecordingUploadSession session) {
    validateRecordingUploadSession(session);
    final int? userId = int.tryParse(session.userId.trim());
    final String email = session.accountEmail?.trim() ?? '';
    final String environment = session.environment.trim();
    if (userId == null || userId <= 0 || email.isEmpty || environment.isEmpty) {
      throw const RecordingUploadSessionChangedException();
    }
    return RecordingCacheOwner._(
      session: session,
      userId: userId,
      email: email,
      normalizedEmail: email.toLowerCase(),
      environment: environment,
    );
  }

  final RecordingUploadSession session;
  final int userId;
  final String email;
  final String normalizedEmail;
  final String environment;
}

typedef RecordingCacheLoader<T> = Future<List<T>> Function(
  RecordingCacheOwner owner,
);
typedef RecordingCacheSessionGuard = Future<void> Function();
typedef RecordingCacheDeleter = Future<void> Function(
  int recordingId,
  RecordingCacheOwner owner,
  RecordingCacheSessionGuard requireSessionCurrent,
);

/// Lists cache entries only for one pinned, verified logical login.
///
/// A guest or unverified state has no activated upload session and therefore
/// sees an empty cache list without touching persistence. The final currentness
/// check prevents rows loaded for a session that changed mid-query from being
/// returned to the UI.
Future<List<T>> listDownloadedRecordingCacheForActivatedOwner<T>({
  required RecordingUploadSessionProvider sessions,
  required RecordingCacheLoader<T> loadOwnedEntries,
}) async {
  final RecordingUploadSession? session = await sessions.capture();
  if (session == null) return <T>[];

  final RecordingCacheOwner owner = RecordingCacheOwner.fromSession(session);
  await _requireSessionCurrent(sessions, session);
  final List<T> entries = await loadOwnedEntries(owner);
  await _requireSessionCurrent(sessions, session);
  return List<T>.unmodifiable(entries);
}

/// Deletes one cache entry only for one pinned, verified logical login.
///
/// The persistence adapter must call [RecordingCacheSessionGuard] inside its
/// transaction immediately before destructive writes and again before commit.
/// This keeps the owner scope and logical-login lease pinned together.
Future<void> deleteDownloadedRecordingCacheForActivatedOwner({
  required int recordingId,
  required RecordingUploadSessionProvider sessions,
  required RecordingCacheDeleter deleteOwnedEntry,
}) async {
  if (recordingId <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot delete a cache entry without a valid local recording id.',
    );
  }

  final RecordingUploadSession? session = await sessions.capture();
  if (session == null) {
    throw const RecordingUploadSessionChangedException();
  }
  final RecordingCacheOwner owner = RecordingCacheOwner.fromSession(session);

  Future<void> requireCurrent() => _requireSessionCurrent(sessions, session);

  await requireCurrent();
  await deleteOwnedEntry(recordingId, owner, requireCurrent);
}

bool recordingCacheEntryMatchesOwner({
  required String? entryEnvironment,
  required int? entryUserId,
  required String? entryEmail,
  required RecordingCacheOwner owner,
}) {
  return entryEnvironment == owner.environment &&
      entryUserId == owner.userId &&
      entryEmail?.trim().toLowerCase() == owner.normalizedEmail;
}

Future<void> _requireSessionCurrent(
  RecordingUploadSessionProvider sessions,
  RecordingUploadSession session,
) async {
  if (!await sessions.isCurrent(session)) {
    throw const RecordingUploadSessionChangedException();
  }
}
