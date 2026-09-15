import 'package:flutter/material.dart';

enum RecordingDialectConfidence { confirmed, predicted, userGuess }

class RecordingDialectEntry {
  const RecordingDialectEntry({
    required this.canonicalCode,
    required this.displayLabel,
    required this.isRepresentant,
    required this.startOffset,
    required this.endOffset,
    required this.confidence,
    required this.color,
  });

  RecordingDialectEntry withColor(Color value) => RecordingDialectEntry(
    canonicalCode: canonicalCode,
    displayLabel: displayLabel,
    isRepresentant: isRepresentant,
    startOffset: startOffset,
    endOffset: endOffset,
    confidence: confidence,
    color: value,
  );

  final String canonicalCode;
  final String displayLabel;
  final bool isRepresentant;
  final Duration startOffset;
  final Duration endOffset;
  final RecordingDialectConfidence confidence;
  final Color color;
}
