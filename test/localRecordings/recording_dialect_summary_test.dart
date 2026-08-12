import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localRecordings/recording_dialect_summary.dart';

void main() {
  group('selectRecordingDialectSummary', () {
    test('prefers administrator confirmation over AI and manual values', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'BC',
            aiPredicted: 'BE',
            manualGuess: 'No Dialect',
          ),
        ],
      );

      expect(selection.dialect, 'BC');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('real admin value beats an unfinished AI result', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'BE',
            aiPredicted: 'Unfinished',
          ),
        ],
      );

      expect(selection.dialect, 'BE');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('prefers AI prediction over a manual no-dialect guess', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            aiPredicted: 'BE',
            manualGuess: 'No Dialect',
          ),
        ],
      );

      expect(selection.dialect, 'BE');
      expect(selection.source, RecordingDialectSummarySource.aiPredicted);
      expect(selection.isNoDialect, isFalse);
    });

    test('uses manual guess only when no higher-confidence value exists', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(manualGuess: 'XB'),
        ],
      );

      expect(selection.dialect, 'XB');
      expect(selection.source, RecordingDialectSummarySource.manualGuess);
    });

    test('returns unknown selection when all rows and values are absent', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[],
      );

      expect(selection.hasDialect, isFalse);
      expect(selection.source, RecordingDialectSummarySource.none);
      expect(selection.isNoDialect, isFalse);
    });

    test('does not infer no-dialect from an absent manual guess', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(),
        ],
      );

      expect(selection, isA<RecordingDialectSummarySelection>());
      expect(selection.dialect, isNull);
      expect(selection.isNoDialect, isFalse);
    });

    test('returns unknown for null and placeholder-only values', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'Unknown dialect',
            aiPredicted: 'Undetermined',
            manualGuess: 'Unassessed',
          ),
          RecordingDialectSummaryRow(
            adminConfirmed: null,
            aiPredicted: null,
            manualGuess: null,
          ),
        ],
      );

      expect(selection.dialect, isNull);
      expect(selection.source, RecordingDialectSummarySource.none);
    });

    test('returns unknown for sentinel-only AI and manual rows', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            aiPredicted: 'Unfinished',
            manualGuess: 'Unusable',
          ),
          RecordingDialectSummaryRow(manualGuess: "I don't know"),
        ],
      );

      expect(selection.dialect, isNull);
      expect(selection.source, RecordingDialectSummarySource.none);
    });

    test('falls through an unfinished AI result to a real manual dialect', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            aiPredicted: 'Unfinished',
            manualGuess: 'XB',
          ),
        ],
      );

      expect(selection.dialect, 'XB');
      expect(selection.source, RecordingDialectSummarySource.manualGuess);
    });

    test('falls through an unusable admin result to a real AI dialect', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'Unusable',
            aiPredicted: 'BE',
          ),
        ],
      );

      expect(selection.dialect, 'BE');
      expect(selection.source, RecordingDialectSummarySource.aiPredicted);
    });

    test('preserves an explicit manual no-dialect value as final fallback', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(manualGuess: 'No Dialect'),
        ],
      );

      expect(selection.dialect, 'No Dialect');
      expect(selection.source, RecordingDialectSummarySource.manualGuess);
      expect(selection.isNoDialect, isTrue);
    });

    test('normalizes a localized explicit no-dialect value', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(manualGuess: 'Bez dialektu'),
        ],
      );

      expect(selection.dialect, 'No Dialect');
      expect(selection.isNoDialect, isTrue);
    });

    test('skips placeholder admin values and falls back to AI', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'Unassessed',
            aiPredicted: 'BlBh',
            manualGuess: 'XB',
          ),
          RecordingDialectSummaryRow(adminConfirmed: 'Unknown dialect'),
        ],
      );

      expect(selection.dialect, 'BlBh');
      expect(selection.source, RecordingDialectSummarySource.aiPredicted);
    });

    test('prefers a concrete value over no-dialect within the same tier', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(adminConfirmed: 'No Dialect'),
          RecordingDialectSummaryRow(adminConfirmed: 'BC'),
        ],
      );

      expect(selection.dialect, 'BC');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('keeps confirmed no-dialect authoritative over lower tiers', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'No Dialect',
            aiPredicted: 'BE',
            manualGuess: 'XB',
          ),
        ],
      );

      expect(selection.dialect, 'No Dialect');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('selects confirmed no-dialect when no substantive alternative exists',
        () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'No Dialect',
            aiPredicted: 'Unassessed',
            manualGuess: null,
          ),
        ],
      );

      expect(selection.dialect, 'No Dialect');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
      expect(selection.isNoDialect, isTrue);
    });

    test('includes legacy administrator data in the highest tier', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            aiPredicted: 'BE',
            manualGuess: 'XB',
          ),
        ],
        legacyRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(
            adminConfirmed: 'BC',
            manualGuess: 'No Dialect',
          ),
        ],
      );

      expect(selection.dialect, 'BC');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('confirmed value in a later row beats an earlier manual no-dialect',
        () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(manualGuess: 'No Dialect'),
          RecordingDialectSummaryRow(adminConfirmed: 'BE'),
        ],
      );

      expect(selection.dialect, 'BE');
      expect(selection.source, RecordingDialectSummarySource.adminConfirmed);
    });

    test('falls back to a legacy manual guess when it is all that exists', () {
      final selection = selectRecordingDialectSummary(
        detectedRows: const <RecordingDialectSummaryRow>[],
        legacyRows: const <RecordingDialectSummaryRow>[
          RecordingDialectSummaryRow(manualGuess: 'XB'),
        ],
      );

      expect(selection.dialect, 'XB');
      expect(selection.source, RecordingDialectSummarySource.manualGuess);
    });
  });

  group('formatRecordingDialectSummary', () {
    String format(RecordingDialectSummarySelection selection) {
      return formatRecordingDialectSummary(
        selection,
        unknownLabel: 'unknown-label',
        withoutDialectLabel: 'without-label',
        localizeDialect: (dialect) => 'localized:$dialect',
      );
    }

    test('formats a missing selection as unknown, never without-dialect', () {
      expect(
        format(const RecordingDialectSummarySelection.none()),
        'unknown-label',
      );
    });

    test('formats only an explicit no-dialect selection as without-dialect',
        () {
      expect(
        format(
          const RecordingDialectSummarySelection(
            dialect: 'No Dialect',
            source: RecordingDialectSummarySource.manualGuess,
          ),
        ),
        'without-label',
      );
    });

    test('delegates a concrete dialect to the localization callback', () {
      expect(
        format(
          const RecordingDialectSummarySelection(
            dialect: 'BE',
            source: RecordingDialectSummarySource.aiPredicted,
          ),
        ),
        'localized:BE',
      );
    });
  });

  test('selector module has no database or API dependency', () {
    final source = File(
      'lib/localRecordings/recording_dialect_summary.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('databaseNew')));
    expect(source, isNot(contains('/api/')));
    expect(source, isNot(contains('http_adapter')));
    expect(source, isNot(contains('sqflite')));
  });

  test('recording list adapts current and legacy admin data to the selector',
      () {
    final source = File('lib/localRecordings/recList.dart').readAsStringSync();

    expect(
      source,
      contains('getDetectedDialectsByRecordingLocalId(recordingId)'),
    );
    expect(source, contains('getDialectsByRecordingId(recordingId)'));
    expect(source, contains('adminConfirmed: dialect.confirmedDialect'));
    expect(source, contains('aiPredicted: dialect.predictedDialect'));
    expect(source, contains('manualGuess: dialect.userGuessDialect'));
    expect(source, contains('adminConfirmed: dialect.adminDialect'));
  });
}
