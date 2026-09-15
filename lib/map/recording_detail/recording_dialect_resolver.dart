import 'package:flutter/material.dart';
import 'package:strnadi/dialects/dialect_keyword_translator.dart';
import 'package:strnadi/dialects/dialect_time_resolver.dart';
import 'package:strnadi/map/data/dialect_marker_selection.dart';
import 'recording_dialect_entry.dart';

/// Selects dialects and aligns their API timestamps with concatenated audio.
/// All inputs are supplied by the caller; this resolver performs no I/O.
class RecordingDialectResolver {
  const RecordingDialectResolver({
    required this.recordingCreatedAt,
    this.parts = const [],
    this.totalSeconds,
  });

  final DateTime recordingCreatedAt;
  final Iterable<DialectTimeSegment> parts;
  final double? totalSeconds;

  List<RecordingDialectEntry> resolve(
    List<Map<String, dynamic>> filteredParts,
  ) {
    final List<Map<String, dynamic>> sourceParts =
        selectDialectSourceParts<Map<String, dynamic>>(
          parts: filteredParts,
          isRepresentant: (Map<String, dynamic> item) =>
              _parseBool(item['representantFlag']),
          hasSubstantiveConfirmedDialect: (Map<String, dynamic> item) =>
              _hasConfirmedDialect(item['detectedDialects']),
          hasAuthoritativeNoDialect: (Map<String, dynamic> item) =>
              _hasAuthoritativeNoDialect(item['detectedDialects']),
        );

    final List<
      ({
        String code,
        String label,
        bool representant,
        Duration start,
        Duration end,
        RecordingDialectConfidence confidence,
      })
    >
    drafts = [];
    final bool hasAdminConfirmedSourcePart = sourceParts.any(
      (item) => _hasConfirmedDialect(item['detectedDialects']),
    );

    for (final map in sourceParts) {
      final bool isRepresentant = _parseBool(map['representantFlag']);
      final bool isAdminConfirmedSourcePart = _hasConfirmedDialect(
        map['detectedDialects'],
      );
      if (hasAdminConfirmedSourcePart && !isAdminConfirmedSourcePart) {
        continue;
      }

      final Object? startStr = map['startDate'];
      final Object? endStr = map['endDate'];
      if (startStr is! String || endStr is! String) continue;

      DateTime? startDate;
      DateTime? endDate;
      try {
        startDate = DateTime.parse(startStr);
        endDate = DateTime.parse(endStr);
      } catch (_) {
        continue;
      }

      final Duration startOffset = _offsetWithinConcatenated(startDate);
      final Duration endOffset = _offsetWithinConcatenated(endDate);
      final Duration safeEnd = endOffset < startOffset
          ? startOffset
          : endOffset;

      final dynamic rawDialects = map['detectedDialects'];
      if (rawDialects is List && rawDialects.isNotEmpty) {
        for (final dd in rawDialects) {
          if (dd is! Map<String, dynamic>) continue;
          final selected = _selectDialect(dd);
          final String? rawCode = selected.code;
          if (rawCode == null) continue;
          final String english =
              DialectKeywordTranslator.toEnglish(rawCode) ?? rawCode.trim();
          if (english.isEmpty) continue;
          final String label = DialectKeywordTranslator.toLocalized(english);
          drafts.add((
            code: english,
            label: label,
            representant: isRepresentant,
            start: startOffset,
            end: safeEnd,
            confidence: selected.confidence,
          ));
        }
      } else {
        final String? rawCode = map['dialectCode'] as String?;
        if (rawCode == null) continue;
        final String english =
            DialectKeywordTranslator.toEnglish(rawCode) ?? rawCode.trim();
        if (english.isEmpty || isSemanticDialectSentinel(english)) continue;
        final String label = DialectKeywordTranslator.toLocalized(english);
        drafts.add((
          code: english,
          label: label,
          representant: isRepresentant,
          start: startOffset,
          end: safeEnd,
          confidence: RecordingDialectConfidence.predicted,
        ));
      }
    }

    if (drafts.isEmpty) {
      return const [];
    }

    final entries = drafts
        .map(
          (draft) => RecordingDialectEntry(
            canonicalCode: draft.code,
            displayLabel: draft.label,
            isRepresentant: draft.representant,
            startOffset: draft.start,
            endOffset: draft.end,
            confidence: draft.confidence,
            color: Colors.grey.shade400,
          ),
        )
        .toList();

    entries.sort((a, b) {
      if (a.isRepresentant != b.isRepresentant) {
        return a.isRepresentant ? -1 : 1;
      }
      final int startCompare = a.startOffset.compareTo(b.startOffset);
      if (startCompare != 0) return startCompare;
      final int endCompare = a.endOffset.compareTo(b.endOffset);
      if (endCompare != 0) return endCompare;
      return a.displayLabel.compareTo(b.displayLabel);
    });

    return entries;
  }

  ({String? code, RecordingDialectConfidence confidence}) _selectDialect(
    Map<String, dynamic> row,
  ) {
    final RecordingDialectSummary summary = summarizeRecordingDialects(
      rows: <DetectedDialectSnapshot>[
        DetectedDialectSnapshot(
          confirmed: _pickDialectValue(row, 'confirmedDialect'),
          predicted: _pickDialectValue(row, 'predictedDialect'),
          guessed: _pickDialectValue(row, 'userGuessDialect'),
        ),
      ],
      mode: DialectSummaryMode.all,
      canonicalize: _canonicalizeDialectValue,
    );
    if (summary.hasAnySelectedDialect) {
      final RecordingDialectConfidence confidence;
      switch (summary.selectedTier) {
        case SelectedDialectTier.confirmed:
          confidence = RecordingDialectConfidence.confirmed;
          break;
        case SelectedDialectTier.predicted:
          confidence = RecordingDialectConfidence.predicted;
          break;
        case SelectedDialectTier.guessed:
        case SelectedDialectTier.none:
          confidence = RecordingDialectConfidence.userGuess;
          break;
      }
      return (code: summary.dialects.first, confidence: confidence);
    }
    if (summary.hasAuthoritativeNoDialect) {
      return (code: null, confidence: RecordingDialectConfidence.confirmed);
    }

    final fallback = _pickDialectValue(row, 'dialectCode');
    if (fallback != null) {
      final String canonical = _canonicalizeDialectValue(fallback);
      if (canonical.isNotEmpty && !isSemanticDialectSentinel(canonical)) {
        return (
          code: canonical,
          confidence: RecordingDialectConfidence.userGuess,
        );
      }
    }

    return (code: null, confidence: RecordingDialectConfidence.userGuess);
  }

  bool _hasConfirmedDialect(dynamic rawDialects) {
    if (rawDialects is! List) return false;
    for (final row in rawDialects) {
      if (row is! Map<String, dynamic>) continue;
      final String canonical = _canonicalizeDialectValue(
        _pickDialectValue(row, 'confirmedDialect'),
      );
      if (canonical.isNotEmpty && !isSemanticDialectSentinel(canonical)) {
        return true;
      }
    }
    return false;
  }

  bool _hasAuthoritativeNoDialect(dynamic rawDialects) {
    if (rawDialects is! List) return false;
    for (final row in rawDialects) {
      if (row is! Map<String, dynamic>) continue;
      final String canonical = _canonicalizeDialectValue(
        _pickDialectValue(row, 'confirmedDialect'),
      );
      if (isAuthoritativeNoDialect(canonical)) {
        return true;
      }
    }
    return false;
  }

  String _canonicalizeDialectValue(String? value) {
    if (value == null) return '';
    return DialectKeywordTranslator.toEnglish(value) ?? value.trim();
  }

  String? _pickDialectValue(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  Duration _offsetWithinConcatenated(DateTime timestamp) {
    return resolveDialectOffset(
      timestamp: timestamp,
      recordingCreatedAt: recordingCreatedAt,
      parts: parts,
      totalSeconds: totalSeconds,
    );
  }
}
