class MapLoadingTracker {
  int _nextToken = 0;
  final Set<int> _activeTokens = <int>{};

  int begin() {
    final int token = ++_nextToken;
    _activeTokens.add(token);
    return token;
  }

  /// Starts a replacement for [previousToken] without briefly becoming idle.
  ///
  /// A late completion for the replaced token is harmless because [finish]
  /// removes only tokens that are still active.
  int replace(int? previousToken) {
    if (previousToken != null) {
      _activeTokens.remove(previousToken);
    }
    return begin();
  }

  bool finish(int token) => _activeTokens.remove(token);

  bool get isLoading => _activeTokens.isNotEmpty;

  int get activeCount => _activeTokens.length;
}

bool isMapDialectRequestCurrent({
  required int dialectRequestId,
  required int activeDialectRequestId,
  required int recordingsRequestId,
  required int activeRecordingsRequestId,
  required int dataGeneration,
  required int activeDataGeneration,
}) {
  return dialectRequestId == activeDialectRequestId &&
      recordingsRequestId == activeRecordingsRequestId &&
      dataGeneration == activeDataGeneration;
}
