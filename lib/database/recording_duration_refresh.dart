import 'dart:convert';

class RecordingDurationTarget {
  const RecordingDurationTarget({
    required this.localId,
    required this.backendId,
    required this.currentDuration,
  });

  final int localId;
  final int backendId;
  final double? currentDuration;
}

class RecordingDurationFetchResponse {
  const RecordingDurationFetchResponse({
    required this.statusCode,
    required this.data,
  });

  final int statusCode;
  final Object? data;
}

class RecordingDurationRefreshResult {
  const RecordingDurationRefreshResult({
    required this.attempted,
    required this.updated,
    required this.failed,
    required this.sessionChanged,
  });

  final int attempted;
  final int updated;
  final int failed;
  final bool sessionChanged;
}

typedef RecordingDurationSessionCheck = Future<bool> Function();
typedef RecordingDurationTargetLoader = Future<List<RecordingDurationTarget>>
    Function();
typedef RecordingDurationFetcher = Future<RecordingDurationFetchResponse>
    Function(int backendId);
typedef RecordingDurationSaver = Future<void> Function(
  RecordingDurationTarget target,
  double duration,
);

/// Refreshes missing durations while an account-bound session remains current.
///
/// All I/O is injected so the orchestration can be exhaustively tested without
/// touching secure storage, SQLite, or the backend. A session change aborts the
/// batch and, critically, prevents a response from the previous login from
/// being committed after an account switch.
Future<RecordingDurationRefreshResult> refreshRecordingDurations({
  required RecordingDurationSessionCheck isSessionCurrent,
  required RecordingDurationTargetLoader loadTargets,
  required RecordingDurationFetcher fetchDuration,
  required RecordingDurationSaver saveDuration,
}) async {
  if (!await _sessionIsCurrent(isSessionCurrent)) {
    return const RecordingDurationRefreshResult(
      attempted: 0,
      updated: 0,
      failed: 0,
      sessionChanged: true,
    );
  }

  final List<RecordingDurationTarget> targets = await loadTargets();
  if (!await _sessionIsCurrent(isSessionCurrent)) {
    return const RecordingDurationRefreshResult(
      attempted: 0,
      updated: 0,
      failed: 0,
      sessionChanged: true,
    );
  }

  int attempted = 0;
  int updated = 0;
  int failed = 0;

  for (final RecordingDurationTarget target in targets) {
    final double? existing = target.currentDuration;
    if (target.localId <= 0 ||
        target.backendId <= 0 ||
        (existing != null && existing.isFinite && existing > 0)) {
      continue;
    }

    if (!await _sessionIsCurrent(isSessionCurrent)) {
      return RecordingDurationRefreshResult(
        attempted: attempted,
        updated: updated,
        failed: failed,
        sessionChanged: true,
      );
    }

    attempted++;
    try {
      final RecordingDurationFetchResponse response =
          await fetchDuration(target.backendId);

      // Never apply data returned for a login that stopped being current while
      // the request was in flight.
      if (!await _sessionIsCurrent(isSessionCurrent)) {
        return RecordingDurationRefreshResult(
          attempted: attempted,
          updated: updated,
          failed: failed,
          sessionChanged: true,
        );
      }

      final double? duration = response.statusCode == 200
          ? parseRecordingDuration(response.data)
          : null;
      if (duration == null) {
        failed++;
        continue;
      }

      await saveDuration(target, duration);
      updated++;

      if (!await _sessionIsCurrent(isSessionCurrent)) {
        return RecordingDurationRefreshResult(
          attempted: attempted,
          updated: updated,
          failed: failed,
          sessionChanged: true,
        );
      }
    } catch (_) {
      failed++;
    }
  }

  return RecordingDurationRefreshResult(
    attempted: attempted,
    updated: updated,
    failed: failed,
    sessionChanged: false,
  );
}

Future<bool> _sessionIsCurrent(
  RecordingDurationSessionCheck isSessionCurrent,
) async {
  try {
    return await isSessionCurrent();
  } catch (_) {
    return false;
  }
}

double? parseRecordingDuration(Object? payload) {
  Object? decoded = payload;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;

  final Object? rawDuration = decoded['totalSeconds'];
  final double? duration = switch (rawDuration) {
    num value => value.toDouble(),
    String value => double.tryParse(value.trim()),
    _ => null,
  };
  if (duration == null || !duration.isFinite || duration <= 0) return null;
  return duration;
}
