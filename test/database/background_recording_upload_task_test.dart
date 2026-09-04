import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/background_recording_upload_task.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  group('background recording task (all dependencies mocked)', () {
    late _Harness harness;

    setUp(() {
      harness = _Harness();
    });

    test('invalid input is permanent and never reads the database', () async {
      final bool result = await harness.run(rawRecordingId: 'not-an-id');

      expect(result, isTrue);
      expect(harness.loadCalls, 0);
      expect(
        harness.notices,
        <BackgroundRecordingUploadNotice>[
          BackgroundRecordingUploadNotice.missingId,
        ],
      );
      expect(harness.uploadCalls, 0);
    });

    test('initial mocked DB read failure requests a retry', () async {
      harness.loadError = StateError('mock DB unavailable');

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.loadCalls, 1);
      expect(
        harness.notices,
        <BackgroundRecordingUploadNotice>[
          BackgroundRecordingUploadNotice.databaseReadFailure,
        ],
      );
      expect(harness.reconcileCalls, 0);
    });

    test('missing mocked DB row is permanent', () async {
      harness.recording = null;

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.loadCalls, 1);
      expect(
        harness.notices,
        <BackgroundRecordingUploadNotice>[
          BackgroundRecordingUploadNotice.notFound,
        ],
      );
      expect(harness.uploadCalls, 0);
    });

    test('mocked reconciliation failure requests a retry', () async {
      harness.reconcileError = StateError('mock DB busy');

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.uploadCalls, 0);
      expect(
        harness.notices.last,
        BackgroundRecordingUploadNotice.uploadFailed,
      );
    });

    test('record disappearing after reconciliation requests a retry', () async {
      harness.removeOnSecondLoad = true;

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.loadCalls, 2);
      expect(harness.uploadCalls, 0);
    });

    test('busy recording requests a retry and starts no health server',
        () async {
      harness.recording!.sending = true;

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.healthStarts, 0);
      expect(harness.uploadCalls, 0);
    });

    for (final Object error in <Object>[
      UploadException('unauthorized', 401),
      UploadException('conflict', 409),
      UploadException('server', 503),
      const RecordingUploadSessionChangedException(),
      StateError('mock persistence failed'),
    ]) {
      test('retryable mocked upload failure $error returns false', () async {
        harness.uploadError = error;

        final bool result = await harness.run();

        expect(result, isFalse);
        expect(harness.uploadCalls, 1);
        expect(harness.dialectCalls, 0);
        expect(harness.healthStops, 1);
      });
    }

    for (final Object error in <Object>[
      UploadException('bad request', 400),
      UploadException('forbidden', 403),
      UploadException('missing', 404),
      const RecordingUploadValidationException('invalid local aggregate'),
    ]) {
      test('permanent mocked upload failure $error returns true', () async {
        harness.uploadError = error;

        final bool result = await harness.run();

        expect(result, isTrue);
        expect(harness.uploadCalls, 1);
        expect(harness.dialectCalls, 0);
        expect(harness.healthStops, 1);
      });
    }

    test('retryable dialect failure retries without losing uploaded state',
        () async {
      harness.dialectError = UploadException('server', 500);

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.uploadCalls, 1);
      expect(harness.dialectCalls, 1);
      expect(harness.recording!.uploaded, isTrue);
      expect(harness.healthStops, 1);
    });

    test('success notification failure cannot retry a completed upload',
        () async {
      harness.noticeError =
          const _Failure('mock notification plugin unavailable');

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.uploadCalls, 1);
      expect(harness.dialectCalls, 1);
      expect(harness.ancillaryFailures, contains('notification'));
      expect(harness.healthStops, 1);
    });

    test('failure notification cannot replace retry classification', () async {
      harness.uploadError = UploadException('server', 500);
      harness.noticeError =
          const _Failure('mock notification plugin unavailable');

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.ancillaryFailures, contains('notification'));
    });

    test('health registration failure is ancillary', () async {
      harness.healthStartError = const _Failure('mock port unavailable');

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.uploadCalls, 1);
      expect(harness.dialectCalls, 1);
      expect(harness.ancillaryFailures, contains('health registration'));
      expect(harness.healthStops, 0);
    });

    test('health shutdown failure cannot replace success', () async {
      harness.healthStopError = const _Failure('mock port shutdown failed');

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.healthStops, 1);
      expect(harness.ancillaryFailures, contains('health shutdown'));
    });

    test('an already-owned health server is not stopped by this worker',
        () async {
      harness.healthStartedResult = false;

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.healthStarts, 1);
      expect(harness.healthStops, 0);
      expect(harness.uploadCalls, 1);
      expect(harness.dialectCalls, 1);
    });

    test('task failure reporting cannot replace retry classification',
        () async {
      final UploadException failure = UploadException('mock timeout', 503);
      harness
        ..uploadError = failure
        ..throwTaskFailureReporter = true;

      final bool result = await harness.run();

      expect(result, isFalse);
      expect(harness.taskFailures, <Object>[failure]);
      expect(
        harness.notices.last,
        BackgroundRecordingUploadNotice.uploadFailed,
      );
    });

    test('broken ancillary reporting cannot alter a completed upload',
        () async {
      harness
        ..noticeError = const _Failure('mock notification unavailable')
        ..throwAncillaryReporter = true;

      final bool result = await harness.run();

      expect(result, isTrue);
      expect(harness.ancillaryFailures, <String>['notification']);
      expect(harness.healthStops, 1);
    });
  });
}

class _FakeRecording {
  _FakeRecording({
    required this.id,
    required this.backendId,
  });

  final int id;
  int? backendId;
  bool sending = false;
  bool uploaded = false;
}

class _Harness {
  _FakeRecording? recording = _FakeRecording(id: 42, backendId: null);
  Object? loadError;
  Object? reconcileError;
  Object? uploadError;
  Object? dialectError;
  Object? noticeError;
  Object? healthStartError;
  Object? healthStopError;
  bool removeOnSecondLoad = false;
  bool healthStartedResult = true;
  bool throwTaskFailureReporter = false;
  bool throwAncillaryReporter = false;

  int loadCalls = 0;
  int reconcileCalls = 0;
  int uploadCalls = 0;
  int dialectCalls = 0;
  int healthStarts = 0;
  int healthStops = 0;
  final List<BackgroundRecordingUploadNotice> notices =
      <BackgroundRecordingUploadNotice>[];
  final List<String> ancillaryFailures = <String>[];
  final List<Object> taskFailures = <Object>[];

  Future<bool> run({Object? rawRecordingId = 42}) {
    return handleBackgroundRecordingUploadTask<_FakeRecording>(
      rawRecordingId: rawRecordingId,
      loadRecording: (int id) async {
        loadCalls++;
        if (loadError != null) throw loadError!;
        if (removeOnSecondLoad && loadCalls == 2) return null;
        return recording;
      },
      reconcileInterruptedUploads: () async {
        reconcileCalls++;
        if (reconcileError != null) throw reconcileError!;
      },
      recordingIsSending: (_FakeRecording value) => value.sending,
      backendRecordingId: (_FakeRecording value) => value.backendId,
      uploadRecording: (_FakeRecording value) async {
        uploadCalls++;
        if (uploadError != null) throw uploadError!;
        value
          ..uploaded = true
          ..backendId = 900;
      },
      sendDialects: (int id, int? backendId) async {
        dialectCalls++;
        expect(id, 42);
        expect(backendId, 900);
        if (dialectError != null) throw dialectError!;
      },
      sendNotice: (
        BackgroundRecordingUploadNotice notice,
        int? id,
      ) async {
        notices.add(notice);
        if (noticeError != null) throw noticeError!;
      },
      startHealth: (int id) async {
        healthStarts++;
        if (healthStartError != null) throw healthStartError!;
        return healthStartedResult;
      },
      stopHealth: (int id) async {
        healthStops++;
        if (healthStopError != null) throw healthStopError!;
      },
      isRetryable: (Object error) {
        if (error is RecordingUploadSessionChangedException ||
            error is StateError) {
          return true;
        }
        if (error is RecordingUploadValidationException) return false;
        if (error is UploadException) {
          final int status = error.statusCode;
          return status == 401 ||
              status == 408 ||
              status == 409 ||
              status == 425 ||
              status == 429 ||
              status >= 500;
        }
        return true;
      },
      onTaskFailure: (Object error, StackTrace stackTrace) {
        taskFailures.add(error);
        if (throwTaskFailureReporter) {
          throw const _Failure('mock task reporter unavailable');
        }
      },
      onAncillaryFailure: (
        String operation,
        Object error,
        StackTrace stackTrace,
      ) {
        ancillaryFailures.add(operation);
        if (throwAncillaryReporter) {
          throw const _Failure('mock ancillary reporter unavailable');
        }
      },
    );
  }
}

class _Failure implements Exception {
  const _Failure(this.message);

  final String message;

  @override
  String toString() => '_Failure: $message';
}
