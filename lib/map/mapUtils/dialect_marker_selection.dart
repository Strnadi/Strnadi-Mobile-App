enum DialectSummaryMode {
  all,
  aiAdmin,
  adminOnly,
}

enum SelectedDialectTier {
  none,
  confirmed,
  predicted,
  guessed,
}

const Set<String> _semanticDialectSentinels = <String>{
  'unknown',
  'unknown dialect',
  'unfinished',
  'unassessed',
  'undetermined',
  'unusable',
  'no dialect',
  'none',
  "i don't know",
};

/// Values which describe processing/review state rather than a bird dialect.
///
/// These values describe backend processing/review metadata and must never be
/// combined with a real dialect to create a split map marker.
bool isSemanticDialectSentinel(String value) {
  return _semanticDialectSentinels.contains(value.trim().toLowerCase());
}

bool isAuthoritativeNoDialect(String value) {
  return value.trim().toLowerCase() == 'no dialect';
}

class DetectedDialectSnapshot {
  const DetectedDialectSnapshot({
    this.confirmed,
    this.predicted,
    this.guessed,
    this.substantiveConfirmedSource = false,
  });

  final String? confirmed;
  final String? predicted;
  final String? guessed;
  final bool substantiveConfirmedSource;
}

class RecordingDialectSummary {
  const RecordingDialectSummary({
    required this.dialects,
    required this.selectedTier,
    this.hasAuthoritativeNoDialect = false,
  });

  final List<String> dialects;
  final SelectedDialectTier selectedTier;
  final bool hasAuthoritativeNoDialect;

  bool get hasAnySelectedDialect => dialects.isNotEmpty;
}

bool shouldRenderDialectMarker({
  required RecordingDialectSummary summary,
  required DialectSummaryMode mode,
  required bool hasAiProcessedFallback,
}) {
  if (summary.hasAuthoritativeNoDialect) {
    return false;
  }

  if (summary.hasAnySelectedDialect) {
    return true;
  }

  // A processed AI part can legitimately have no finished dialect row yet.
  // Keep that recording visible as Unknown in modes which include AI results.
  // Admin-only mode must continue to require an administrator classification.
  return hasAiProcessedFallback && mode != DialectSummaryMode.adminOnly;
}

List<String> dialectsForMapMarker(RecordingDialectSummary summary) {
  if (summary.hasAuthoritativeNoDialect) {
    return const <String>[];
  }
  if (!summary.hasAnySelectedDialect) {
    return <String>['Unknown'];
  }
  return List<String>.from(summary.dialects);
}

bool shouldShowMapRecording({
  required bool matchesAge,
  required bool isExplicitlyHidden,
  required bool? isVisibleInSelectedMode,
}) {
  if (!matchesAge || isExplicitlyHidden) {
    return false;
  }

  // A missing dialect selection means dialect data has not excluded this
  // recording. Once a selection exists, honor its mode-specific visibility.
  return isVisibleInSelectedMode ?? true;
}

List<T> selectDialectSourceParts<T>({
  required Iterable<T> parts,
  required bool Function(T part) isRepresentant,
  bool Function(T part)? hasSubstantiveConfirmedDialect,
  bool Function(T part)? hasAuthoritativeNoDialect,
}) {
  final allParts = parts.toList(growable: false);
  if (hasSubstantiveConfirmedDialect != null) {
    final confirmedParts =
        allParts.where(hasSubstantiveConfirmedDialect).toList(growable: false);
    if (confirmedParts.isNotEmpty) {
      return confirmedParts;
    }
  }
  if (hasAuthoritativeNoDialect != null) {
    final noDialectParts =
        allParts.where(hasAuthoritativeNoDialect).toList(growable: false);
    if (noDialectParts.isNotEmpty) {
      return noDialectParts;
    }
  }
  final representants = allParts.where(isRepresentant).toList(growable: false);
  return representants.isNotEmpty ? representants : allParts;
}

List<String> limitFailsafeDialects({
  required Iterable<String> dialects,
  required bool usedFailsafe,
}) {
  final values = dialects.toList(growable: false);
  if (!usedFailsafe || values.length <= 1) return values;
  return <String>[values.first];
}

RecordingDialectSummary summarizeRecordingDialects({
  required Iterable<DetectedDialectSnapshot> rows,
  required DialectSummaryMode mode,
  required String Function(String? value) canonicalize,
}) {
  final inputRows = rows.toList(growable: false);
  final hasSubstantiveConfirmedSource =
      inputRows.any((row) => row.substantiveConfirmedSource);
  final effectiveRows = hasSubstantiveConfirmedSource
      ? inputRows.where((row) => row.substantiveConfirmedSource)
      : inputRows;

  final List<String> confirmed = <String>[];
  final List<String> predicted = <String>[];
  final List<String> guessed = <String>[];
  final Set<String> confirmedSeen = <String>{};
  final Set<String> predictedSeen = <String>{};
  final Set<String> guessedSeen = <String>{};
  bool hasAuthoritativeNoDialect = false;

  void addValue(
    String? value,
    List<String> output,
    Set<String> seen,
  ) {
    final String canonical = canonicalize(value);
    if (canonical.isEmpty ||
        isSemanticDialectSentinel(canonical) ||
        !seen.add(canonical)) {
      return;
    }
    output.add(canonical);
  }

  for (final row in effectiveRows) {
    final String canonicalConfirmed = canonicalize(row.confirmed);
    if (isAuthoritativeNoDialect(canonicalConfirmed)) {
      hasAuthoritativeNoDialect = true;
    }
    addValue(row.confirmed, confirmed, confirmedSeen);
    addValue(row.predicted, predicted, predictedSeen);
    addValue(row.guessed, guessed, guessedSeen);
  }

  switch (mode) {
    case DialectSummaryMode.all:
      if (confirmed.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: confirmed,
          selectedTier: SelectedDialectTier.confirmed,
        );
      }
      if (hasAuthoritativeNoDialect) {
        return const RecordingDialectSummary(
          dialects: <String>[],
          selectedTier: SelectedDialectTier.confirmed,
          hasAuthoritativeNoDialect: true,
        );
      }
      if (predicted.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: predicted,
          selectedTier: SelectedDialectTier.predicted,
        );
      }
      if (guessed.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: guessed,
          selectedTier: SelectedDialectTier.guessed,
        );
      }
      break;
    case DialectSummaryMode.aiAdmin:
      if (confirmed.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: confirmed,
          selectedTier: SelectedDialectTier.confirmed,
        );
      }
      if (hasAuthoritativeNoDialect) {
        return const RecordingDialectSummary(
          dialects: <String>[],
          selectedTier: SelectedDialectTier.confirmed,
          hasAuthoritativeNoDialect: true,
        );
      }
      if (predicted.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: predicted,
          selectedTier: SelectedDialectTier.predicted,
        );
      }
      break;
    case DialectSummaryMode.adminOnly:
      if (confirmed.isNotEmpty) {
        return RecordingDialectSummary(
          dialects: confirmed,
          selectedTier: SelectedDialectTier.confirmed,
        );
      }
      if (hasAuthoritativeNoDialect) {
        return const RecordingDialectSummary(
          dialects: <String>[],
          selectedTier: SelectedDialectTier.confirmed,
          hasAuthoritativeNoDialect: true,
        );
      }
      break;
  }

  return const RecordingDialectSummary(
    dialects: <String>[],
    selectedTier: SelectedDialectTier.none,
  );
}
