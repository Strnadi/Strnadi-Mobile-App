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

    test('substantive confirmation beats a representative processing sentinel',
        () {
      final parts = const [
        _PartSnapshot(id: 1, representant: true),
        _PartSnapshot(
          id: 2,
          representant: false,
          substantiveConfirmed: true,
        ),
      ];

      final selected = selectDialectSourceParts<_PartSnapshot>(
        parts: parts,
        isRepresentant: (part) => part.representant,
        hasSubstantiveConfirmedDialect: (part) => part.substantiveConfirmed,
      );

      expect(selected.map((part) => part.id), <int>[2]);
    });

    test('admin No Dialect beats a representative prediction', () {
      final parts = const [
        _PartSnapshot(id: 1, representant: true),
        _PartSnapshot(
          id: 2,
          representant: false,
          authoritativeNoDialect: true,
        ),
      ];

      final selected = selectDialectSourceParts<_PartSnapshot>(
        parts: parts,
        isRepresentant: (part) => part.representant,
        hasSubstantiveConfirmedDialect: (part) => part.substantiveConfirmed,
        hasAuthoritativeNoDialect: (part) => part.authoritativeNoDialect,
      );

      expect(selected.map((part) => part.id), <int>[2]);
    });

    test('substantive confirmation beats admin No Dialect at the same tier',
        () {
      final parts = const [
        _PartSnapshot(
          id: 1,
          representant: true,
          authoritativeNoDialect: true,
        ),
        _PartSnapshot(
          id: 2,
          representant: false,
          substantiveConfirmed: true,
        ),
      ];

      final selected = selectDialectSourceParts<_PartSnapshot>(
        parts: parts,
        isRepresentant: (part) => part.representant,
        hasSubstantiveConfirmedDialect: (part) => part.substantiveConfirmed,
        hasAuthoritativeNoDialect: (part) => part.authoritativeNoDialect,
      );

      expect(selected.map((part) => part.id), <int>[2]);
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

    test('collapses regular failsafe dialect lists to one dialect', () {
      expect(
        limitFailsafeDialects(
          dialects: const <String>['BE', 'XB'],
          usedFailsafe: true,
        ),
        <String>['BE'],
      );
    });
  });

  group('shouldRenderDialectMarker', () {
    const emptySummary = RecordingDialectSummary(
      dialects: <String>[],
      selectedTier: SelectedDialectTier.none,
    );
    const classifiedSummary = RecordingDialectSummary(
      dialects: <String>['BC'],
      selectedTier: SelectedDialectTier.confirmed,
    );

    test('keeps a processed Unknown recording visible in AI+Admin mode', () {
      expect(
        shouldRenderDialectMarker(
          summary: emptySummary,
          mode: DialectSummaryMode.aiAdmin,
          hasAiProcessedFallback: true,
        ),
        isTrue,
      );
    });

    test('keeps a processed Unknown recording visible in all mode', () {
      expect(
        shouldRenderDialectMarker(
          summary: emptySummary,
          mode: DialectSummaryMode.all,
          hasAiProcessedFallback: true,
        ),
        isTrue,
      );
    });

    test('does not leak an AI fallback into admin-only mode', () {
      expect(
        shouldRenderDialectMarker(
          summary: emptySummary,
          mode: DialectSummaryMode.adminOnly,
          hasAiProcessedFallback: true,
        ),
        isFalse,
      );
    });

    test('hides an unclassified recording without a processed fallback', () {
      expect(
        shouldRenderDialectMarker(
          summary: emptySummary,
          mode: DialectSummaryMode.aiAdmin,
          hasAiProcessedFallback: false,
        ),
        isFalse,
      );
    });

    test('renders sentinel-only state-6 data as one Unknown marker', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            confirmed: 'Unfinished',
            predicted: 'Unknown',
          ),
        ],
        mode: DialectSummaryMode.aiAdmin,
        canonicalize: canonicalize,
      );

      expect(summary.hasAnySelectedDialect, isFalse);
      expect(
        shouldRenderDialectMarker(
          summary: summary,
          mode: DialectSummaryMode.aiAdmin,
          hasAiProcessedFallback: true,
        ),
        isTrue,
      );
      expect(dialectsForMapMarker(summary), <String>['Unknown']);
    });

    test('shows a selected dialect in every mode', () {
      for (final mode in DialectSummaryMode.values) {
        expect(
          shouldRenderDialectMarker(
            summary: classifiedSummary,
            mode: mode,
            hasAiProcessedFallback: false,
          ),
          isTrue,
          reason: mode.name,
        );
      }
    });
  });

  group('shouldShowMapRecording', () {
    test('shows an otherwise eligible recording before dialect data arrives',
        () {
      expect(
        shouldShowMapRecording(
          matchesAge: true,
          isExplicitlyHidden: false,
          isVisibleInSelectedMode: null,
        ),
        isTrue,
      );
    });

    test('hides a recording excluded by the selected dialect mode', () {
      expect(
        shouldShowMapRecording(
          matchesAge: true,
          isExplicitlyHidden: false,
          isVisibleInSelectedMode: false,
        ),
        isFalse,
      );
    });

    test('age exclusion always wins', () {
      expect(
        shouldShowMapRecording(
          matchesAge: false,
          isExplicitlyHidden: false,
          isVisibleInSelectedMode: true,
        ),
        isFalse,
      );
    });

    test('explicit no-FRP or No Dialect exclusion always wins', () {
      expect(
        shouldShowMapRecording(
          matchesAge: true,
          isExplicitlyHidden: true,
          isVisibleInSelectedMode: true,
        ),
        isFalse,
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
            substantiveConfirmedSource: true,
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

    test('does not select a guessed-only dialect in AI+Admin mode', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(guessed: 'XB'),
        ],
        mode: DialectSummaryMode.aiAdmin,
        canonicalize: canonicalize,
      );

      expect(summary.hasAnySelectedDialect, isFalse);
      expect(summary.selectedTier, SelectedDialectTier.none);
    });

    test('does not select a predicted-only dialect in admin-only mode', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(predicted: 'BC'),
        ],
        mode: DialectSummaryMode.adminOnly,
        canonicalize: canonicalize,
      );

      expect(summary.hasAnySelectedDialect, isFalse);
      expect(summary.selectedTier, SelectedDialectTier.none);
    });

    test('falls through a confirmed sentinel to a real prediction', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            confirmed: 'Unfinished',
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

    test('confirmed No Dialect suppresses lower-tier real values', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(
            confirmed: 'No Dialect',
            predicted: 'BE',
            guessed: 'XB',
          ),
        ],
        mode: DialectSummaryMode.all,
        canonicalize: canonicalize,
      );

      expect(summary.dialects, isEmpty);
      expect(summary.selectedTier, SelectedDialectTier.confirmed);
      expect(summary.hasAuthoritativeNoDialect, isTrue);
      expect(
        shouldRenderDialectMarker(
          summary: summary,
          mode: DialectSummaryMode.all,
          hasAiProcessedFallback: true,
        ),
        isFalse,
      );
      expect(dialectsForMapMarker(summary), isEmpty);
    });

    test('real confirmation beats No Dialect at the same tier', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(confirmed: 'No Dialect'),
          DetectedDialectSnapshot(confirmed: 'BE'),
        ],
        mode: DialectSummaryMode.all,
        canonicalize: canonicalize,
      );

      expect(summary.dialects, <String>['BE']);
      expect(summary.selectedTier, SelectedDialectTier.confirmed);
      expect(summary.hasAuthoritativeNoDialect, isFalse);
    });

    test('does not split a real dialect with Unknown', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(predicted: 'BE'),
          DetectedDialectSnapshot(predicted: 'Unknown'),
        ],
        mode: DialectSummaryMode.aiAdmin,
        canonicalize: canonicalize,
      );

      expect(dialectsForMapMarker(summary), <String>['BE']);
    });

    test('does not split a real dialect with Unfinished', () {
      final summary = summarizeRecordingDialects(
        rows: const <DetectedDialectSnapshot>[
          DetectedDialectSnapshot(predicted: 'BE'),
          DetectedDialectSnapshot(predicted: 'Unfinished'),
        ],
        mode: DialectSummaryMode.aiAdmin,
        canonicalize: canonicalize,
      );

      expect(dialectsForMapMarker(summary), <String>['BE']);
    });

    test('filters every semantic processing sentinel', () {
      for (final sentinel in const <String>[
        'Unknown',
        'Unknown dialect',
        'Unfinished',
        'Unassessed',
        'Undetermined',
        'Unusable',
        'No Dialect',
      ]) {
        final summary = summarizeRecordingDialects(
          rows: <DetectedDialectSnapshot>[
            DetectedDialectSnapshot(predicted: sentinel),
          ],
          mode: DialectSummaryMode.aiAdmin,
          canonicalize: canonicalize,
        );

        expect(
          summary.hasAnySelectedDialect,
          isFalse,
          reason: sentinel,
        );
      }
    });
  });
}

class _PartSnapshot {
  const _PartSnapshot({
    required this.id,
    required this.representant,
    this.substantiveConfirmed = false,
    this.authoritativeNoDialect = false,
  });

  final int id;
  final bool representant;
  final bool substantiveConfirmed;
  final bool authoritativeNoDialect;
}
