import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_upload_scheduling.dart';
import 'package:strnadi/database/recording_upload_service.dart';

void main() {
  group('background recording id parsing', () {
    for (final (Object?, int) valid in <(Object?, int)>[
      (1, 1),
      (42.0, 42),
      (' 73 ', 73),
    ]) {
      test('accepts positive integral value ${valid.$1}', () {
        expect(parseScheduledRecordingId(valid.$1), valid.$2);
      });
    }

    for (final Object? invalid in <Object?>[
      null,
      0,
      -1,
      1.5,
      double.nan,
      double.infinity,
      '',
      '0',
      '-5',
      '1.5',
      true,
      <String, Object?>{'id': 1},
    ]) {
      test('rejects invalid value $invalid', () {
        expect(parseScheduledRecordingId(invalid), isNull);
      });
    }
  });

  group('persisted capture-review flag', () {
    test('accepts only SQLite/Dart true values', () {
      expect(persistedCaptureReviewFlag(1), isTrue);
      expect(persistedCaptureReviewFlag(true), isTrue);

      for (final Object? value in <Object?>[
        null,
        0,
        false,
        -1,
        2,
        '1',
        'true',
      ]) {
        expect(persistedCaptureReviewFlag(value), isFalse);
      }
    });
  });

  group('platform background work request', () {
    test('Android uses one stable keep-policy job per recording', () {
      final RecordingBackgroundWorkRequest request =
          buildRecordingBackgroundWorkRequest(
        recordingId: 42,
        isIOS: false,
      );

      expect(request.uniqueName, 'sendRecording_42');
      expect(request.taskName, recordingBackgroundTaskName);
      expect(request.inputData, <String, int>{'recordingId': 42});
      expect(
        request.existingWorkPolicy,
        RecordingBackgroundExistingWorkPolicy.keep,
      );
      expect(
        () => request.inputData['recordingId'] = 99,
        throwsUnsupportedError,
      );
    });

    test('iOS uses its registered processing identifier and append policy', () {
      final RecordingBackgroundWorkRequest request =
          buildRecordingBackgroundWorkRequest(
        recordingId: 42,
        isIOS: true,
      );

      expect(request.uniqueName, iosRecordingBackgroundTaskIdentifier);
      expect(request.taskName, iosRecordingBackgroundTaskIdentifier);
      expect(request.inputData, <String, int>{'recordingId': 42});
      expect(
        request.existingWorkPolicy,
        RecordingBackgroundExistingWorkPolicy.append,
      );
    });

    for (final int invalidId in <int>[0, -1]) {
      test('cannot build platform work for invalid id $invalidId', () {
        expect(
          () => buildRecordingBackgroundWorkRequest(
            recordingId: invalidId,
            isIOS: false,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    test('only the Android and iOS recording task names are recognized', () {
      expect(
          isRecordingBackgroundTaskName(recordingBackgroundTaskName), isTrue);
      expect(
        isRecordingBackgroundTaskName(iosRecordingBackgroundTaskIdentifier),
        isTrue,
      );
      for (final String invalid in <String>[
        '',
        'sendRecording_42',
        'SendRecording',
        'com.delta.strnadi.sendRecording.extra',
      ]) {
        expect(isRecordingBackgroundTaskName(invalid), isFalse);
      }
    });
  });

  group('review-gated background scheduling (mocked DB and scheduler)', () {
    test('a reviewed capture is scheduled exactly once', () async {
      final _FakeSchedulingBoundary fake = _FakeSchedulingBoundary(
        reviewed: true,
      );

      await scheduleReviewedRecordingUpload(
        recordingId: 42,
        loadCaptureReviewed: fake.load,
        schedule: fake.schedule,
      );

      expect(fake.loadedIds, <int>[42]);
      expect(fake.scheduledIds, <int>[42]);
    });

    for (final bool? reviewState in <bool?>[false, null]) {
      test('$reviewState review state cannot schedule background work',
          () async {
        final _FakeSchedulingBoundary fake = _FakeSchedulingBoundary(
          reviewed: reviewState,
        );

        await expectLater(
          scheduleReviewedRecordingUpload(
            recordingId: 42,
            loadCaptureReviewed: fake.load,
            schedule: fake.schedule,
          ),
          throwsA(
            isA<RecordingUploadValidationException>().having(
              (RecordingUploadValidationException error) => error.message,
              'message',
              contains('reviewed'),
            ),
          ),
        );

        expect(fake.loadedIds, <int>[42]);
        expect(fake.scheduledIds, isEmpty);
      });
    }

    for (final int invalidId in <int>[0, -1]) {
      test('invalid id $invalidId is rejected before the mocked DB', () async {
        final _FakeSchedulingBoundary fake = _FakeSchedulingBoundary(
          reviewed: true,
        );

        await expectLater(
          scheduleReviewedRecordingUpload(
            recordingId: invalidId,
            loadCaptureReviewed: fake.load,
            schedule: fake.schedule,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );

        expect(fake.loadedIds, isEmpty);
        expect(fake.scheduledIds, isEmpty);
      });
    }

    test('mocked DB failure cannot schedule background work', () async {
      final StateError failure = StateError('mocked DB read failed');
      final _FakeSchedulingBoundary fake = _FakeSchedulingBoundary(
        reviewed: true,
        loadError: failure,
      );

      await expectLater(
        scheduleReviewedRecordingUpload(
          recordingId: 42,
          loadCaptureReviewed: fake.load,
          schedule: fake.schedule,
        ),
        throwsA(same(failure)),
      );

      expect(fake.scheduledIds, isEmpty);
    });

    test('mocked scheduler failure is propagated after review', () async {
      final StateError failure = StateError('mocked scheduler failed');
      final _FakeSchedulingBoundary fake = _FakeSchedulingBoundary(
        reviewed: true,
        scheduleError: failure,
      );

      await expectLater(
        scheduleReviewedRecordingUpload(
          recordingId: 42,
          loadCaptureReviewed: fake.load,
          schedule: fake.schedule,
        ),
        throwsA(same(failure)),
      );

      expect(fake.loadedIds, <int>[42]);
      expect(fake.scheduledIds, <int>[42]);
    });
  });
}

class _FakeSchedulingBoundary {
  _FakeSchedulingBoundary({
    required this.reviewed,
    this.loadError,
    this.scheduleError,
  });

  final bool? reviewed;
  final Object? loadError;
  final Object? scheduleError;
  final List<int> loadedIds = <int>[];
  final List<int> scheduledIds = <int>[];

  Future<bool?> load(int recordingId) async {
    loadedIds.add(recordingId);
    final Object? failure = loadError;
    if (failure != null) throw failure;
    return reviewed;
  }

  Future<void> schedule(int recordingId) async {
    scheduledIds.add(recordingId);
    final Object? failure = scheduleError;
    if (failure != null) throw failure;
  }
}
