import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/background_recording_upload_task.dart';
import 'package:strnadi/database/recording_upload_scheduling.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/database/upload_protocol.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  group('Workmanager recording dispatcher (all boundaries mocked)', () {
    for (final String taskName in <String>[
      recordingBackgroundTaskName,
      iosRecordingBackgroundTaskIdentifier,
    ]) {
      test('$taskName initializes before forwarding the exact payload',
          () async {
        final List<String> calls = <String>[];
        final Map<String, dynamic> inputData = <String, dynamic>{
          'recordingId': 42,
          'attempt': 3,
        };
        Map<String, dynamic>? receivedInput;

        final bool result = await dispatchBackgroundRecordingTask(
          taskName: taskName,
          inputData: inputData,
          initialize: () async {
            calls.add('initialize');
          },
          handleRecordingTask: (Map<String, dynamic>? input) async {
            calls.add('handle');
            receivedInput = input;
            return false;
          },
        );

        expect(result, isFalse);
        expect(calls, <String>['initialize', 'handle']);
        expect(receivedInput, same(inputData));
      });
    }

    test('null input is forwarded so the task handler can classify it',
        () async {
      var handled = false;

      final bool result = await dispatchBackgroundRecordingTask(
        taskName: recordingBackgroundTaskName,
        inputData: null,
        initialize: () async {},
        handleRecordingTask: (Map<String, dynamic>? input) async {
          handled = true;
          expect(input, isNull);
          return true;
        },
      );

      expect(result, isTrue);
      expect(handled, isTrue);
    });

    test('unknown tasks initialize but never enter recording persistence',
        () async {
      final List<String> calls = <String>[];

      final bool result = await dispatchBackgroundRecordingTask(
        taskName: 'unrelatedMaintenanceTask',
        inputData: const <String, dynamic>{'recordingId': 42},
        initialize: () async {
          calls.add('initialize');
        },
        handleRecordingTask: (_) async {
          calls.add('handle');
          return false;
        },
        onUnknownTask: (String taskName) {
          calls.add('unknown:$taskName');
        },
      );

      expect(result, isTrue);
      expect(
        calls,
        <String>['initialize', 'unknown:unrelatedMaintenanceTask'],
      );
    });

    test('essential initialization failure prevents recording access',
        () async {
      final StateError failure = StateError('mock configuration unavailable');
      var handled = false;

      await expectLater(
        dispatchBackgroundRecordingTask(
          taskName: recordingBackgroundTaskName,
          inputData: const <String, dynamic>{'recordingId': 42},
          initialize: () async => throw failure,
          handleRecordingTask: (_) async {
            handled = true;
            return true;
          },
        ),
        throwsA(same(failure)),
      );

      expect(handled, isFalse);
    });

    test('task-handler failures remain visible to Workmanager', () async {
      final StateError failure = StateError('mock worker crashed');

      await expectLater(
        dispatchBackgroundRecordingTask(
          taskName: recordingBackgroundTaskName,
          inputData: const <String, dynamic>{'recordingId': 42},
          initialize: () async {},
          handleRecordingTask: (_) async => throw failure,
        ),
        throwsA(same(failure)),
      );
    });
  });

  group('scheduled recording job lifecycle (mock API, DB, and scheduler)', () {
    test('reviewed Android capture runs the complete worker lifecycle',
        () async {
      final _RecordingJobHarness harness = _RecordingJobHarness();

      await harness.schedule(isIOS: false);
      final bool result = await harness.runScheduledJob();

      expect(result, isTrue);
      expect(harness.request!.uniqueName, 'sendRecording_42');
      expect(
        harness.request!.existingWorkPolicy,
        RecordingBackgroundExistingWorkPolicy.keep,
      );
      expect(harness.recording.uploaded, isTrue);
      expect(harness.recording.backendId, 900);
      expect(harness.calls, <String>[
        'review:42',
        'schedule:42',
        'initialize',
        'load:42',
        'reconcile',
        'load:42',
        'health:start:42',
        'upload:42',
        'dialects:42:900',
        'notice:uploadSucceeded:42',
        'health:stop:42',
      ]);
    });

    test('transient upload failure retries and converges on the next run',
        () async {
      final _RecordingJobHarness harness = _RecordingJobHarness()
        ..uploadOutcomes.add(UploadException('mock server unavailable', 503))
        ..uploadOutcomes.add(null);

      await harness.schedule(isIOS: false);
      final bool firstResult = await harness.runScheduledJob();
      final bool retryResult = await harness.runScheduledJob();

      expect(firstResult, isFalse);
      expect(retryResult, isTrue);
      expect(harness.uploadCalls, 2);
      expect(harness.dialectCalls, 1);
      expect(harness.healthStarts, 2);
      expect(harness.healthStops, 2);
      expect(
        harness.notices,
        <BackgroundRecordingUploadNotice>[
          BackgroundRecordingUploadNotice.uploadFailed,
          BackgroundRecordingUploadNotice.uploadSucceeded,
        ],
      );
    });

    test('uploaded parent survives a transient dialect failure and retry',
        () async {
      final _RecordingJobHarness harness = _RecordingJobHarness()
        ..dialectOutcomes.add(UploadException('mock dialect timeout', 500))
        ..dialectOutcomes.add(null);

      await harness.schedule(isIOS: true);
      final bool firstResult = await harness.runScheduledJob();
      expect(firstResult, isFalse);
      expect(harness.recording.uploaded, isTrue);
      expect(harness.recording.backendId, 900);

      final bool retryResult = await harness.runScheduledJob();

      expect(retryResult, isTrue);
      expect(harness.uploadCalls, 2);
      expect(harness.dialectCalls, 2);
      expect(harness.request!.taskName, iosRecordingBackgroundTaskIdentifier);
      expect(
        harness.request!.existingWorkPolicy,
        RecordingBackgroundExistingWorkPolicy.append,
      );
    });

    test('permanent recording rejection completes without an endless retry',
        () async {
      final _RecordingJobHarness harness = _RecordingJobHarness()
        ..uploadOutcomes.add(UploadException('mock invalid recording', 400));

      await harness.schedule(isIOS: false);
      final bool result = await harness.runScheduledJob();

      expect(result, isTrue);
      expect(harness.uploadCalls, 1);
      expect(harness.dialectCalls, 0);
      expect(
        harness.notices,
        <BackgroundRecordingUploadNotice>[
          BackgroundRecordingUploadNotice.uploadFailed,
        ],
      );
    });

    test('unreviewed capture cannot reach the scheduler or worker', () async {
      final _RecordingJobHarness harness = _RecordingJobHarness()
        ..reviewed = false;

      await expectLater(
        harness.schedule(isIOS: false),
        throwsA(isA<RecordingUploadValidationException>()),
      );

      expect(harness.request, isNull);
      expect(harness.calls, <String>['review:42']);
      expect(harness.uploadCalls, 0);
    });
  });

  group('production background-job wiring', () {
    test('Workmanager callback delegates through the tested dispatcher', () {
      final String source =
          File('lib/callback_dispatcher.dart').readAsStringSync();

      expect(source, contains('dispatchBackgroundRecordingTask('));
      expect(source, contains('handleRecordingTask: _handleSendRecordingTask'));
      expect(source, contains('initialize: () async'));
      expect(source, contains('_backgroundUploadHealthServer.start('));
      expect(source, contains('_backgroundUploadHealthServer.stop('));
    });

    test('database scheduler uses the tested platform request builder', () {
      final String source =
          File('lib/database/src/database_repository.dart').readAsStringSync();

      expect(source, contains('buildRecordingBackgroundWorkRequest('));
      expect(source, contains('request.uniqueName'));
      expect(source, contains('request.taskName'));
      expect(source, contains('inputData: request.inputData'));
    });

    test('iOS native registration matches the Dart task identifier', () {
      final String appDelegate =
          File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final String infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(
        appDelegate,
        contains(
          'registerBGProcessingTask(withIdentifier: '
          '"$iosRecordingBackgroundTaskIdentifier")',
        ),
      );
      expect(
        infoPlist,
        contains('<string>$iosRecordingBackgroundTaskIdentifier</string>'),
      );
    });
  });
}

class _FakeRecording {
  _FakeRecording({required this.id});

  final int id;
  int? backendId;
  bool sending = false;
  bool uploaded = false;
}

class _RecordingJobHarness {
  final _FakeRecording recording = _FakeRecording(id: 42);
  final Queue<Object?> uploadOutcomes = Queue<Object?>();
  final Queue<Object?> dialectOutcomes = Queue<Object?>();
  final List<String> calls = <String>[];
  final List<BackgroundRecordingUploadNotice> notices =
      <BackgroundRecordingUploadNotice>[];

  bool reviewed = true;
  RecordingBackgroundWorkRequest? request;
  int uploadCalls = 0;
  int dialectCalls = 0;
  int healthStarts = 0;
  int healthStops = 0;

  Future<void> schedule({required bool isIOS}) {
    return scheduleReviewedRecordingUpload(
      recordingId: recording.id,
      loadCaptureReviewed: (int recordingId) async {
        calls.add('review:$recordingId');
        return reviewed;
      },
      schedule: (int recordingId) async {
        calls.add('schedule:$recordingId');
        request = buildRecordingBackgroundWorkRequest(
          recordingId: recordingId,
          isIOS: isIOS,
        );
      },
    );
  }

  Future<bool> runScheduledJob() {
    final RecordingBackgroundWorkRequest scheduled = request!;
    return dispatchBackgroundRecordingTask(
      taskName: scheduled.taskName,
      inputData: scheduled.inputData,
      initialize: () async {
        calls.add('initialize');
      },
      handleRecordingTask: (Map<String, dynamic>? inputData) {
        return handleBackgroundRecordingUploadTask<_FakeRecording>(
          rawRecordingId: inputData?['recordingId'],
          loadRecording: (int recordingId) async {
            calls.add('load:$recordingId');
            return recording;
          },
          reconcileInterruptedUploads: () async {
            calls.add('reconcile');
            recording.sending = false;
          },
          recordingIsSending: (_FakeRecording value) => value.sending,
          backendRecordingId: (_FakeRecording value) => value.backendId,
          uploadRecording: (_FakeRecording value) async {
            uploadCalls++;
            calls.add('upload:${value.id}');
            final Object? outcome =
                uploadOutcomes.isEmpty ? null : uploadOutcomes.removeFirst();
            if (outcome != null) throw outcome;
            value
              ..uploaded = true
              ..backendId = 900;
          },
          sendDialects: (int recordingId, int? backendRecordingId) async {
            dialectCalls++;
            calls.add('dialects:$recordingId:$backendRecordingId');
            final Object? outcome =
                dialectOutcomes.isEmpty ? null : dialectOutcomes.removeFirst();
            if (outcome != null) throw outcome;
          },
          sendNotice: (BackgroundRecordingUploadNotice notice, int? id) async {
            notices.add(notice);
            calls.add('notice:${notice.name}:$id');
          },
          startHealth: (int recordingId) async {
            healthStarts++;
            calls.add('health:start:$recordingId');
            return true;
          },
          stopHealth: (int recordingId) async {
            healthStops++;
            calls.add('health:stop:$recordingId');
          },
          isRetryable: isRetryableRecordingUploadFailure,
        );
      },
    );
  }
}
