class DialectTimeSegment {
  const DialectTimeSegment({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;
}

final DateTime _unixEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

Duration resolveDialectOffset({
  required DateTime timestamp,
  required DateTime recordingCreatedAt,
  Iterable<DialectTimeSegment> parts = const <DialectTimeSegment>[],
  double? totalSeconds,
}) {
  final Duration rawOffset = _looksLikeRelativeOffset(timestamp)
      ? timestamp.toUtc().difference(_unixEpoch)
      : _absoluteOffsetWithinConcatenated(
          timestamp: timestamp,
          recordingCreatedAt: recordingCreatedAt,
          parts: parts,
        );

  return clampDialectOffset(
    rawOffset,
    totalSeconds: totalSeconds,
  );
}

Duration clampDialectOffset(
  Duration value, {
  double? totalSeconds,
}) {
  if (value.isNegative) {
    return Duration.zero;
  }
  if (totalSeconds == null || totalSeconds <= 0) {
    return value;
  }

  final Duration maxDuration =
      Duration(milliseconds: (totalSeconds * 1000).round());
  if (value > maxDuration) {
    return maxDuration;
  }
  return value;
}

bool _looksLikeRelativeOffset(DateTime timestamp) {
  final DateTime utc = timestamp.toUtc();
  if (utc.isBefore(_unixEpoch)) {
    return false;
  }

  // The filtered-parts API sometimes serializes offsets as epoch-based
  // datetimes like 1970-01-01T00:01:30Z instead of wall-clock timestamps.
  return utc.difference(_unixEpoch) < const Duration(days: 7);
}

Duration _absoluteOffsetWithinConcatenated({
  required DateTime timestamp,
  required DateTime recordingCreatedAt,
  required Iterable<DialectTimeSegment> parts,
}) {
  final List<DialectTimeSegment> validParts = parts
      .where((part) => !part.end.toUtc().isBefore(part.start.toUtc()))
      .toList()
    ..sort((a, b) => a.start.toUtc().compareTo(b.start.toUtc()));

  if (validParts.isEmpty) {
    return timestamp.toUtc().difference(recordingCreatedAt.toUtc());
  }

  Duration cumulative = Duration.zero;
  final DateTime ts = timestamp.toUtc();

  for (final part in validParts) {
    final DateTime start = part.start.toUtc();
    final DateTime end = part.end.toUtc();
    final Duration partDuration = end.difference(start);

    if (ts.isBefore(start)) {
      return cumulative;
    }

    if (!ts.isAfter(end)) {
      return cumulative + ts.difference(start);
    }

    cumulative += partDuration;
  }

  return cumulative;
}
