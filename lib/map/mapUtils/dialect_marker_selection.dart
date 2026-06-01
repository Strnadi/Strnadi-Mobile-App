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
    this.adminConfirmedRepresentant = false,
  });

  final String? confirmed;
  final String? predicted;
  final String? guessed;
  final bool adminConfirmedRepresentant;
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

List<T> selectDialectSourceParts<T>({
  required Iterable<T> parts,
  required bool Function(T part) isRepresentant,
}) {
  final allParts = parts.toList(growable: false);
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
  final hasAdminConfirmedRepresentant =
      inputRows.any((row) => row.adminConfirmedRepresentant);
  final effectiveRows = hasAdminConfirmedRepresentant
      ? inputRows.where((row) => row.adminConfirmedRepresentant)
      : inputRows;

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

  for (final row in effectiveRows) {
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
