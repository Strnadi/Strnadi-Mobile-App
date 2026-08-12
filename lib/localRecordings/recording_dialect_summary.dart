/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:strnadi/dialects/dialect_keyword_translator.dart';

enum RecordingDialectSummarySource {
  none,
  adminConfirmed,
  aiPredicted,
  manualGuess,
}

/// Database-independent dialect values used to build a recording list label.
///
/// Both current detected-dialect rows and legacy dialect rows are converted to
/// this shape by the caller. Keeping the selector independent from either
/// storage model makes its precedence rules deterministic and easy to test.
class RecordingDialectSummaryRow {
  const RecordingDialectSummaryRow({
    this.adminConfirmed,
    this.aiPredicted,
    this.manualGuess,
  });

  final String? adminConfirmed;
  final String? aiPredicted;
  final String? manualGuess;
}

class RecordingDialectSummarySelection {
  const RecordingDialectSummarySelection({
    required this.dialect,
    required this.source,
  });

  const RecordingDialectSummarySelection.none()
      : dialect = null,
        source = RecordingDialectSummarySource.none;

  final String? dialect;
  final RecordingDialectSummarySource source;

  bool get hasDialect => dialect != null;
  bool get isNoDialect => dialect == 'No Dialect';
}

/// Selects one concise dialect for the local-recording list.
///
/// Administrator decisions are authoritative, AI predictions are the next
/// best available source, and a manual guess is used only as a final fallback.
/// Legacy rows participate in the same ordering so a legacy administrator
/// decision cannot be hidden by a newer AI or manual value.
RecordingDialectSummarySelection selectRecordingDialectSummary({
  required Iterable<RecordingDialectSummaryRow> detectedRows,
  Iterable<RecordingDialectSummaryRow> legacyRows =
      const <RecordingDialectSummaryRow>[],
}) {
  final rows = <RecordingDialectSummaryRow>[
    ...detectedRows,
    ...legacyRows,
  ];

  final adminConfirmed = _selectValue(
    rows.map((row) => row.adminConfirmed),
  );
  if (adminConfirmed != null) {
    return RecordingDialectSummarySelection(
      dialect: adminConfirmed,
      source: RecordingDialectSummarySource.adminConfirmed,
    );
  }

  final aiPredicted = _selectValue(
    rows.map((row) => row.aiPredicted),
  );
  if (aiPredicted != null) {
    return RecordingDialectSummarySelection(
      dialect: aiPredicted,
      source: RecordingDialectSummarySource.aiPredicted,
    );
  }

  final manualGuess = _selectValue(
    rows.map((row) => row.manualGuess),
  );
  if (manualGuess != null) {
    return RecordingDialectSummarySelection(
      dialect: manualGuess,
      source: RecordingDialectSummarySource.manualGuess,
    );
  }

  return const RecordingDialectSummarySelection.none();
}

/// Formats a pure selector result without depending on global localization.
String formatRecordingDialectSummary(
  RecordingDialectSummarySelection selection, {
  required String unknownLabel,
  required String withoutDialectLabel,
  required String Function(String dialect) localizeDialect,
}) {
  final dialect = selection.dialect;
  if (dialect == null) return unknownLabel;
  if (selection.isNoDialect) return withoutDialectLabel;
  return localizeDialect(dialect);
}

String? _selectValue(Iterable<String?> values) {
  String? explicitNoDialect;

  for (final value in values) {
    final canonical = DialectKeywordTranslator.toEnglish(value)?.trim();
    if (canonical == null ||
        canonical.isEmpty ||
        _unavailableDialectValues.contains(canonical)) {
      continue;
    }

    // Prefer a concrete dialect over "No Dialect" when several segments from
    // the same confidence tier are present. The explicit no-dialect value
    // remains authoritative over values from lower-confidence tiers.
    if (canonical == 'No Dialect') {
      explicitNoDialect ??= canonical;
      continue;
    }
    return canonical;
  }

  return explicitNoDialect;
}

const Set<String> _unavailableDialectValues = <String>{
  'Unknown',
  'Unknown dialect',
  'Unfinished',
  'Unassessed',
  'Undetermined',
  'Unusable',
  "I don't know",
};
