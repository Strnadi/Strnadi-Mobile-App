class RecordingAuthorFilterResolution {
  const RecordingAuthorFilterResolution._({
    required this.isAvailable,
    this.userId,
  });

  const RecordingAuthorFilterResolution.all() : this._(isAvailable: true);

  const RecordingAuthorFilterResolution.currentUser(int userId)
      : this._(isAvailable: true, userId: userId);

  const RecordingAuthorFilterResolution.unavailable()
      : this._(isAvailable: false);

  final bool isAvailable;
  final int? userId;
}

/// Resolves the backend user filter without reading secure storage or an API.
///
/// A current-user filter is available only for a positive numeric user id.
/// Callers must clear stale results when [isAvailable] is false.
RecordingAuthorFilterResolution resolveRecordingAuthorFilter({
  required String requestedFilter,
  required String? storedUserId,
}) {
  if (requestedFilter != 'me') {
    return const RecordingAuthorFilterResolution.all();
  }

  final int? userId = int.tryParse(storedUserId?.trim() ?? '');
  if (userId == null || userId <= 0) {
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
