import 'package:strnadi/auth/user_identity.dart';

class RecordingAuthorFilterResolution {
  const RecordingAuthorFilterResolution._({
    required this.isAvailable,
    this.userId,
  });

  const RecordingAuthorFilterResolution.all() : this._(isAvailable: true);

  const RecordingAuthorFilterResolution.currentUser(Object userId)
    : this._(isAvailable: true, userId: userId);

  const RecordingAuthorFilterResolution.unavailable()
    : this._(isAvailable: false);

  final bool isAvailable;
  final Object? userId;
}

/// Resolves the backend user filter without reading secure storage or an API.
///
/// User-relative filters require a valid current-user identity.
/// Callers must clear stale results when [isAvailable] is false.
RecordingAuthorFilterResolution resolveRecordingAuthorFilter({
  required String requestedFilter,
  required String? storedUserId,
  bool requiresUserId = false,
}) {
  if (requestedFilter != 'me' &&
      requestedFilter != 'others' &&
      !requiresUserId) {
    return const RecordingAuthorFilterResolution.all();
  }

  final Object? userId = parseUserId(storedUserId?.trim() ?? '');
  if (userId == null || parseUserId(userId) == null) {
    return const RecordingAuthorFilterResolution.unavailable();
  }
  return RecordingAuthorFilterResolution.currentUser(userId);
}

bool mapRenderGenerationIsCurrent({
  required int expected,
  required int current,
}) {
  return expected == current;
}
