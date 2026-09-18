typedef RecordingPathExists = Future<bool> Function(String path);

Future<String> selectUnusedRecordingPath({
  required String Function() nextCandidate,
  required RecordingPathExists exists,
  Set<String> excludedPaths = const <String>{},
  int maxAttempts = 100,
}) async {
  if (maxAttempts <= 0) {
    throw RangeError.value(
      maxAttempts,
      'maxAttempts',
      'Must be greater than zero.',
    );
  }

  for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
    final String candidate = nextCandidate();
    if (candidate.isEmpty || excludedPaths.contains(candidate)) {
      continue;
    }
    if (!await exists(candidate)) {
      return candidate;
    }
  }

  throw StateError(
    'Could not allocate a distinct recording path after $maxAttempts attempts.',
  );
}
