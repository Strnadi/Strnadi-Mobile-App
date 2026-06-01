import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/mapUtils/dialect_marker_selection.dart';

void main() {
  String canonicalize(String? value) => (value ?? '').trim();

  group('selectDialectSourceParts', () {
    test('uses representants when at least one exists', () {
      final parts = const [
        _PartSnapshot(id: 1, representant: false),
        _PartSnapshot(id: 2, representant: true),
        _PartSnapshot(id: 3, representant: false),
      ];

      final selected = selectDialectSourceParts<_PartSnapshot>(
        parts: parts,
        isRepresentant: (part) => part.representant,
      );

      expect(selected.map((part) => part.id), <int>[2]);
    });

    test('falls back to all parts when no representant exists', () {
      final parts = const [
        _PartSnapshot(id: 1, representant: false),
        _PartSnapshot(id: 2, representant: false),
      ];

      final selected = selectDialectSourceParts<_PartSnapshot>(
        parts: parts,
        isRepresentant: (part) => part.representant,
      );

      expect(selected.map((part) => part.id), <int>[1, 2]);
    });
  });

  group('limitFailsafeDialects', () {
    test('keeps regular representative dialect lists unchanged', () {
      expect(
        limitFailsafeDialects(
          dialects: const <String>['BE', 'XB'],
          usedFailsafe: false,
        ),
        <String>['BE', 'XB'],
      );
    });

    test('collapses failsafe dialect lists to one dialect', () {
      expect(
        limitFailsafeDialects(
          dialects: const <String>['Unfinished', 'Unknown'],
          usedFailsafe: true,
        ),
        <String>['Unfinished'],
      );
    });
  });

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

    test('ignores model-only representants when an admin-confirmed one exists',
        () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            confirmed: 'BC',
            predicted: 'BE',
            adminConfirmedRepresentant: true,
          ),
          DetectedDialectSnapshot(
            predicted: 'XB',
            guessed: 'BlBh',
          ),
        ],
        mode: DialectSummaryMode.all,
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

class _PartSnapshot {
  const _PartSnapshot({
    required this.id,
    required this.representant,
  });

  final int id;
  final bool representant;
}
