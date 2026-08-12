import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/map/recording_author_filter.dart';

void main() {
  group('resolveRecordingAuthorFilter', () {
    test('does not require a user id for the all-recordings filter', () {
      final RecordingAuthorFilterResolution result =
          resolveRecordingAuthorFilter(
        requestedFilter: 'all',
        storedUserId: null,
      );

      expect(result.isAvailable, isTrue);
      expect(result.userId, isNull);
    });

    test('returns a trimmed positive current-user id', () {
      final RecordingAuthorFilterResolution result =
          resolveRecordingAuthorFilter(
        requestedFilter: 'me',
        storedUserId: ' 42 ',
      );

      expect(result.isAvailable, isTrue);
      expect(result.userId, 42);
    });

    for (final String? invalidUserId in <String?>[
      null,
      '',
      ' ',
      'not-a-number',
      '0',
      '-7',
    ]) {
      test('fails closed for current-user id ${invalidUserId ?? 'null'}', () {
        final RecordingAuthorFilterResolution result =
            resolveRecordingAuthorFilter(
          requestedFilter: 'me',
          storedUserId: invalidUserId,
        );

        expect(result.isAvailable, isFalse);
        expect(result.userId, isNull);
      });
    }
  });

  group('map render generation', () {
    test('accepts only the exact generation that began the async render', () {
      expect(
        mapRenderGenerationIsCurrent(expected: 7, current: 7),
        isTrue,
      );
      expect(
        mapRenderGenerationIsCurrent(expected: 7, current: 8),
        isFalse,
      );
    });

    test('rejects an old cluster build after a true-false-true ABA change', () {
      const int generationBeforeToggle = 12;
      const int generationAfterTwoToggles = 14;

      expect(
        mapRenderGenerationIsCurrent(
          expected: generationBeforeToggle,
          current: generationAfterTwoToggles,
        ),
        isFalse,
      );
    });

    test('all marker-affecting filter paths invalidate async renders', () {
      final String source = File('lib/map/mapv2.dart').readAsStringSync();

      expect(
        source,
        contains(
          'else if (shouldRefreshDialects || shouldRebuildMarkers)',
        ),
      );
      expect(
        source,
        contains('dataGeneration: dataGeneration'),
      );
      expect(
        source,
        contains('expectedGeneration'),
      );
    });
  });
}
