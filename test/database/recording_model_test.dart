import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/Models/recording.dart';

void main() {
  group('Recording.fromJson totalSeconds', () {
    test('normalizes an integer SQLite value to double', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: 60),
      );

      expect(recording.totalSeconds, 60.0);
    });

    test('preserves a double SQLite value', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: 60.5),
      );

      expect(recording.totalSeconds, 60.5);
    });

    test('accepts a null duration', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: null),
      );

      expect(recording.totalSeconds, isNull);
    });
  });

  group('Recording capture review state', () {
    test('a malformed row without the migrated column fails closed', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..remove('captureReviewed'),
      );

      expect(recording.captureReviewed, isFalse);
    });

    test('a null review flag fails closed', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..['captureReviewed'] = null,
      );

      expect(recording.captureReviewed, isFalse);
    });

    test('round-trips an unreviewed durable capture', () {
      final Recording recording = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..['captureReviewed'] = 0,
      );

      expect(recording.captureReviewed, isFalse);
      expect(recording.toJson()['captureReviewed'], 0);
    });
  });

  group('Recording equality and hashCode', () {
    test('equal metadata has the same hash regardless of backend id', () {
      final Recording first = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..['BEId'] = 100,
      );
      final Recording second = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..['BEId'] = 200,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(<Recording>{first, second}, hasLength(1));
    });

    test('nullable metadata is compared exactly instead of as a wildcard', () {
      final Recording missingOwner = Recording.fromJson(
        _recordingRow(totalSeconds: 60)..['mail'] = null,
      );
      final Recording owned = Recording.fromJson(
        _recordingRow(totalSeconds: 60),
      );

      expect(missingOwner, isNot(owned));
    });
  });
}

Map<String, Object?> _recordingRow({required num? totalSeconds}) {
  return <String, Object?>{
    'id': 42,
    'userId': 7,
    'BEId': null,
    'mail': 'owner@example.test',
    'createdAt': DateTime.utc(2026, 7, 18, 10).toIso8601String(),
    'estimatedBirdsCount': 1,
    'device': 'Test device',
    'byApp': 1,
    'note': null,
    'name': 'Test recording',
    'path': 'logical://recording.wav',
    'totalSeconds': totalSeconds,
    'sent': 0,
    'downloaded': 1,
    'sending': 0,
    'uploadKey': 'recording-key',
    'uploadLease': null,
    'uploadLeaseUpdatedAt': null,
    'parentUploadAttempted': 0,
    'uploadDeviceId': null,
    'captureReviewed': 1,
    'partCount': 1,
    'env': 'development',
  };
}
