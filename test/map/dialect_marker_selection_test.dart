import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/mapUtils/dialect_marker_selection.dart';

void main() {
  String canonicalize(String? value) => (value ?? '').trim();

  group('summarizeRecordingDialects', () {
    test('prefers confirmed dialects over predicted ones in aiAdmin mode', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            confirmed: 'BC',
            predicted: 'BE',
            guessed: 'XB',
          ),
        ],
        mode: DialectSummaryMode.aiAdmin,
        canonicalize: canonicalize,
      );

      expect(summary.dialects, <String>['BC']);
      expect(summary.selectedTier, SelectedDialectTier.confirmed);
    });

    test('falls back to predicted dialects before guesses in all mode', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            predicted: 'BE',
            guessed: 'XB',
          ),
        ],
        mode: DialectSummaryMode.all,
        canonicalize: canonicalize,
      );

      expect(summary.dialects, <String>['BE']);
      expect(summary.selectedTier, SelectedDialectTier.predicted);
    });

    test('uses guessed dialects when they are the only available source', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(guessed: 'BlBh'),
          DetectedDialectSnapshot(guessed: 'XB'),
        ],
        mode: DialectSummaryMode.all,
        canonicalize: canonicalize,
      );

      expect(summary.dialects, <String>['BlBh', 'XB']);
      expect(summary.selectedTier, SelectedDialectTier.guessed);
    });
  });
}
