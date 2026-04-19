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

class DetectedDialectSnapshot {
  const DetectedDialectSnapshot({
    this.confirmed,
    this.predicted,
    this.guessed,
  });

  final String? confirmed;
  final String? predicted;
  final String? guessed;
}

class RecordingDialectSummary {
  const RecordingDialectSummary({
    required this.dialects,
    required this.selectedTier,
  });

  final List<String> dialects;
  final SelectedDialectTier selectedTier;

  bool get hasAnySelectedDialect => dialects.isNotEmpty;
}

RecordingDialectSummary summarizeRecordingDialects({
  required Iterable<DetectedDialectSnapshot> rows,
  required DialectSummaryMode mode,
  required String Function(String? value) canonicalize,
}) {
  final List<String> confirmed = <String>[];
  final List<String> predicted = <String>[];
  final List<String> guessed = <String>[];
  final Set<String> confirmedSeen = <String>{};
  final Set<String> predictedSeen = <String>{};
  final Set<String> guessedSeen = <String>{};

  void addValue(
    String? value,
    List<String> output,
    Set<String> seen,
  ) {
    final String canonical = canonicalize(value);
    if (canonical.isEmpty || !seen.add(canonical)) {
      return;
    }
    output.add(canonical);
  }

  for (final row in rows) {
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
      break;
  }

  return const RecordingDialectSummary(
    dialects: <String>[],
    selectedTier: SelectedDialectTier.none,
  );
}
