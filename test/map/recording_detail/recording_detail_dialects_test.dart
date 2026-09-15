import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/dialects/dialect_time_resolver.dart';
import 'package:strnadi/map/recording_detail/recording_dialect_entry.dart';
import 'package:strnadi/map/recording_detail/recording_dialect_resolver.dart';

Map<String, dynamic> part({
  String? confirmed,
  String? predicted,
  String? guessed,
  Object representant = false,
  String start = '2026-09-15T10:00:00Z',
  String end = '2026-09-15T10:00:05Z',
}) => {
  'representantFlag': representant,
  'startDate': start,
  'endDate': end,
  'detectedDialects': [
    {
      'confirmedDialect': confirmed,
      'predictedDialect': predicted,
      'userGuessDialect': guessed,
    },
  ],
};

void main() {
  final resolver = RecordingDialectResolver(
    recordingCreatedAt: DateTime.utc(2026, 9, 15, 10),
    totalSeconds: 30,
  );

  test('admin-confirmed parts win over predicted representative parts', () {
    final result = resolver.resolve([
      part(predicted: 'BC', representant: true),
      part(confirmed: 'BE', predicted: 'BC'),
    ]);
    expect(result.map((entry) => entry.canonicalCode), ['BE']);
    expect(result.single.confidence, RecordingDialectConfidence.confirmed);
    expect(result.single.isRepresentant, isFalse);
  });

  test('authoritative no-dialect suppresses guesses and predicted parts', () {
    expect(
      resolver.resolve([
        part(confirmed: 'No dialect', predicted: 'BC', guessed: 'BE'),
        part(predicted: 'BC', representant: true),
      ]),
      isEmpty,
    );
  });

  test('unknown confirmed sentinel permits meaningful prediction', () {
    final entry = resolver.resolve([
      part(confirmed: 'Unknown', predicted: 'BC', guessed: 'BE'),
    ]).single;
    expect(entry.canonicalCode, 'BC');
    expect(entry.confidence, RecordingDialectConfidence.predicted);
  });

  test('representative selection and timestamp sorting are preserved', () {
    final result = resolver.resolve([
      part(predicted: 'BE'),
      part(
        predicted: 'BC',
        representant: 'yes',
        start: '2026-09-15T10:00:10Z',
        end: '2026-09-15T10:00:15Z',
      ),
      part(guessed: 'CD', representant: 1),
    ]);
    expect(result.map((entry) => entry.canonicalCode), ['CD', 'BC']);
    expect(result.every((entry) => entry.isRepresentant), isTrue);
    expect(result.first.confidence, RecordingDialectConfidence.userGuess);
  });

  test('concatenated offsets exclude gaps and clamp to recording duration', () {
    final start = DateTime.utc(2026, 9, 15, 10);
    final segmented = RecordingDialectResolver(
      recordingCreatedAt: start,
      totalSeconds: 15,
      parts: [
        DialectTimeSegment(
          start: start,
          end: start.add(const Duration(seconds: 10)),
        ),
        DialectTimeSegment(
          start: start.add(const Duration(seconds: 60)),
          end: start.add(const Duration(seconds: 70)),
        ),
      ],
    );
    final entry = segmented.resolve([
      part(
        predicted: 'BC',
        start: '2026-09-15T10:01:02Z',
        end: '2026-09-15T10:01:08Z',
      ),
    ]).single;
    expect(entry.startOffset, const Duration(seconds: 12));
    expect(entry.endOffset, const Duration(seconds: 15));
  });

  test('epoch offsets and reversed ranges are kept safe', () {
    final entry = resolver.resolve([
      part(
        predicted: 'BC',
        start: '1970-01-01T00:00:07Z',
        end: '1970-01-01T00:00:04Z',
      ),
    ]).single;
    expect(entry.startOffset, const Duration(seconds: 7));
    expect(entry.endOffset, const Duration(seconds: 7));
    expect(
      resolver.resolve([part(predicted: 'BC', start: 'invalid')]),
      isEmpty,
    );
  });
}
