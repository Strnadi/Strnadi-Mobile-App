import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android recording notification lifecycle source contract', () {
    late String manifest;
    late String bootstrap;
    late String recorder;
    late String boundary;

    setUpAll(() {
      manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      bootstrap = File('lib/bootstrap/app_bootstrap.dart').readAsStringSync();
      recorder = File('lib/recording/streamRec.dart').readAsStringSync();
      boundary = File(
        'lib/recording/recording_foreground_service.dart',
      ).readAsStringSync();
    });

    test('task removal and boot cannot resurrect a recorder notification', () {
      expect(manifest, contains('android:stopWithTask="true"'));
      expect(manifest, isNot(contains('android:stopWithTask="false"')));
      expect(bootstrap, contains('autoRunOnBoot: false'));
      expect(bootstrap, isNot(contains('autoRunOnBoot: true')));
    });

    test('cold start reconciles a legacy sticky service after plugin init', () {
      final int initialization =
          bootstrap.indexOf('FlutterForegroundTask.init(');
      final int reconciliation = bootstrap.indexOf(
        'await reconcileStaleRecordingForegroundService(',
        initialization,
      );
      final int injectedBoundary = bootstrap.indexOf(
        'service: const FlutterRecordingForegroundService()',
        reconciliation,
      );

      expect(initialization, greaterThanOrEqualTo(0));
      expect(reconciliation, greaterThan(initialization));
      expect(injectedBoundary, greaterThan(reconciliation));
    });

    test('a system-started legacy task immediately reconciles itself', () {
      expect(recorder, contains('taskStarter == TaskStarter.system'));
      expect(
        recorder,
        contains('await reconcileStaleRecordingForegroundService('),
      );
    });

    test('idle recorder entry retries reconciliation before user actions', () {
      final int postFrame = recorder.indexOf(
        'WidgetsBinding.instance.addPostFrameCallback((_) {',
      );
      final int entryReconciliation = recorder.indexOf(
        'unawaited(_reconcileForegroundServiceOnRecorderEntry())',
        postFrame,
      );
      final int toggle = recorder.indexOf(
        'Future<void> _toggleRecording() async',
      );
      final int toggleBarrier = recorder.indexOf(
        'await _foregroundServiceEntryCompleter.future',
        toggle,
      );
      final int permissionRead = recorder.indexOf(
        'if (!_hasMicPermission)',
        toggle,
      );

      expect(postFrame, greaterThanOrEqualTo(0));
      expect(entryReconciliation, greaterThan(postFrame));
      expect(toggleBarrier, greaterThan(toggle));
      expect(permissionRead, greaterThan(toggleBarrier));
      expect(
        recorder,
        contains('await reconcileStaleRecordingForegroundService('),
      );
    });

    test('confirmed discard stops the service before deleting or resetting',
        () {
      final int discard =
          recorder.indexOf('Future<void> _discardRecordingResources()');
      final int nextMethod = recorder.indexOf(
        'Future<void> _cleanupFailedRecordingStart',
        discard,
      );
      final String body = recorder.substring(discard, nextMethod);

      final int shutdown = body.indexOf('await _shutdownRecordingRuntime()');
      final int delete = body.indexOf('await _deleteTemporarySegmentFiles()');
      final int reset = body.indexOf('_resetDiscardedRecordingState()');
      expect(shutdown, greaterThanOrEqualTo(0));
      expect(delete, greaterThan(shutdown));
      expect(reset, greaterThan(delete));
    });

    test('successful finish still awaits runtime shutdown', () {
      final int finish = recorder.indexOf('Future<void> _stop() async');
      final int nextMethod = recorder.indexOf(
        'Future<String> _getPath',
        finish,
      );
      final String body = recorder.substring(finish, nextMethod);

      final int durableDraft = body.indexOf(
        'RecordingDraftHandoffCoordinator.database().persistCapture(',
      );
      final int requireShutdown =
          body.indexOf('shouldShutdownRuntime = true', durableDraft);
      final int navigate =
          body.indexOf('Navigator.pushReplacement(', requireShutdown);
      final int shutdown =
          body.indexOf('await _shutdownRecordingRuntime()', navigate);

      expect(durableDraft, greaterThanOrEqualTo(0));
      expect(requireShutdown, greaterThan(durableDraft));
      expect(navigate, greaterThan(requireShutdown));
      expect(shutdown, greaterThan(navigate));
    });

    test('stop failure is verified, retried, and remains observable', () {
      expect(boundary, contains('result is ServiceRequestFailure'));
      expect(boundary, contains('if (!await service.isRunning())'));
      expect(
        boundary,
        contains(
          "throw StateError('The service still reports itself as running.')",
        ),
      );
      expect(
        boundary,
        contains('RecordingForegroundServiceStopException('),
      );
      expect(
        recorder,
        contains(
          'Discard was cancelled because recording runtime cleanup failed.',
        ),
      );
      expect(
        recorder,
        contains("t('streamRec.errors.foregroundServiceCleanup')"),
      );
    });

    test('recorder lifecycle uses only the injectable service boundary', () {
      for (final String directCall in <String>[
        'FlutterForegroundTask.isRunningService',
        'FlutterForegroundTask.startService',
        'FlutterForegroundTask.updateService',
        'FlutterForegroundTask.stopService',
      ]) {
        expect(recorder, isNot(contains(directCall)));
      }
      expect(
        recorder,
        contains(
          'widget.foregroundService ?? '
          'const FlutterRecordingForegroundService()',
        ),
      );
    });

    test('focused lifecycle tests cannot open a real API or database', () {
      final String tests = <String>[
        File(
          'test/recording/recording_foreground_service_test.dart',
        ).readAsStringSync(),
        File(
          'test/recording/foreground_notification_lifecycle_contract_test.dart',
        ).readAsStringSync(),
      ].join('\n');

      expect(
        tests,
        isNot(contains(<String>['api', 'strnadi'].join('.'))),
      );
      expect(
        tests,
        isNot(contains(<String>['DatabaseNew', 'database'].join('.'))),
      );
      expect(
        tests,
        isNot(contains(<String>['package:', 'sqflite', '/'].join())),
      );
      expect(
        tests,
        isNot(contains(<String>['Http', 'Client'].join())),
      );
    });
  });
}
