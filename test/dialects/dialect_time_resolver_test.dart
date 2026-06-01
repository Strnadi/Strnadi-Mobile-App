import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/dialects/dialect_time_resolver.dart';

void main() {
  group('resolveDialectOffset', () {
    test('uses epoch-relative timestamps as direct offsets', () {
      final offset = resolveDialectOffset(
        timestamp: DateTime.parse('1970-01-01T00:01:37Z'),
        recordingCreatedAt: DateTime.parse('2026-04-19T10:00:00Z'),
        parts: <DialectTimeSegment>[
          DialectTimeSegment(
            start: DateTime.utc(2026, 4, 19, 10, 0, 0),
            end: DateTime.utc(2026, 4, 19, 10, 2, 0),
          ),
        ],
        totalSeconds: 300,
      );

      expect(offset, const Duration(minutes: 1, seconds: 37));
    });

    test('converts absolute timestamps into concatenated-part offsets', () {
      final offset = resolveDialectOffset(
        timestamp: DateTime.parse('2026-04-19T10:05:30Z'),
        recordingCreatedAt: DateTime.parse('2026-04-19T10:00:00Z'),
        parts: <DialectTimeSegment>[
          DialectTimeSegment(
            start: DateTime.utc(2026, 4, 19, 10, 0, 0),
            end: DateTime.utc(2026, 4, 19, 10, 1, 0),
          ),
          DialectTimeSegment(
            start: DateTime.utc(2026, 4, 19, 10, 5, 0),
            end: DateTime.utc(2026, 4, 19, 10, 7, 0),
          ),
        ],
        totalSeconds: 300,
      );

      expect(offset, const Duration(minutes: 1, seconds: 30));
    });
  });
}
