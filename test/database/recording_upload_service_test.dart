import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/recording_update_fields.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  late _UploadHarness harness;

  setUp(() {
    harness = _UploadHarness();
  });

  tearDown(() {
    harness.releaseAllGates();
    harness.api.verifyExhausted();
    harness.store.verifyFaultsExhausted();
  });

  group('activated upload-session capture (no API or DB)', () {
    const ActivatedAuthSessionSnapshot verified = ActivatedAuthSessionSnapshot(
      accessToken: 'token-a',
      userId: '42',
      subject: 'bird@example.test',
      sessionId: 'session-a',
      verified: true,
    );

    test('logged-out capture does not read optional device metadata', () async {
      int deviceReads = 0;

      final RecordingUploadSession? result =
          await captureActivatedRecordingUploadSession(
        captureActivatedSession: () async => null,
        readOptionalDeviceId: () async {
          deviceReads++;
          return 'device-a';
        },
        environment: 'prod',
        backendHost: 'api.example.test',
      );

      expect(result, isNull);
      expect(deviceReads, 0);
    });

    test('unverified capture does not read optional device metadata', () async {
      int deviceReads = 0;

      final RecordingUploadSession? result =
          await captureActivatedRecordingUploadSession(
        captureActivatedSession: () async => const ActivatedAuthSessionSnapshot(
          accessToken: 'token-a',
          userId: '42',
          subject: 'bird@example.test',
          sessionId: 'session-a',
          verified: false,
        ),
        readOptionalDeviceId: () async {
          deviceReads++;
          return 'device-a';
        },
        environment: 'prod',
        backendHost: 'api.example.test',
      );

      expect(result, isNull);
      expect(deviceReads, 0);
    });

    test('optional device metadata failure cannot block a valid session',
        () async {
      final RecordingUploadSession? result =
          await captureActivatedRecordingUploadSession(
        captureActivatedSession: () async => verified,
        readOptionalDeviceId: () async =>
            throw const _TestException('keychain unavailable'),
        environment: 'prod',
        backendHost: 'api.example.test',
      );

      expect(result, isNotNull);
      expect(result!.accessToken, 'token-a');
      expect(result.userId, '42');
      expect(result.accountEmail, 'bird@example.test');
      expect(result.logicalSessionId, 'session-a');
      expect(result.deviceId, isNull);
      expect(result.environment, 'prod');
      expect(result.backendHost, 'api.example.test');
    });

    test('captures optional device metadata for a verified session', () async {
      final RecordingUploadSession? result =
          await captureActivatedRecordingUploadSession(
        captureActivatedSession: () async => verified,
        readOptionalDeviceId: () async => 'device-a',
        environment: 'prod',
        backendHost: 'api.example.test',
      );

      expect(result!.deviceId, 'device-a');
    });
  });

  group('stale persistence snapshots', () {
    test('metadata edit cannot roll back completed recording upload state', () {
      final Recording stale = _recording()
        ..name = 'edited name'
        ..note = 'edited note';
      final Recording completed = _recording(
        backendId: 900,
        sent: true,
      )
        ..parentUploadAttempted = true
        ..uploadDeviceId = 'frozen-device';
      final Map<String, Object?> persisted = completed.toJson()
        ..addAll(recordingMetadataUpdateFields(stale));

      expect(persisted['name'], 'edited name');
      expect(persisted['BEId'], 900);
      expect(persisted['sent'], 1);
      expect(persisted['uploadKey'], 'recording-upload-key-42');
      expect(persisted['parentUploadAttempted'], 1);
      expect(persisted['uploadDeviceId'], 'frozen-device');
      for (final String forbidden in <String>[
        'BEId',
        'sent',
        'sending',
        'uploadKey',
        'uploadLease',
        'captureReviewed',
      ]) {
        expect(
            recordingMetadataUpdateFields(stale), isNot(contains(forbidden)));
      }
    });

    test('content refresh cannot roll back completed part upload state', () {
      final RecordingPart stale = _part()
        ..gpsLatitudeStart = 50.5
        ..path = 'logical://refreshed-cache.wav';
      final RecordingPart completed = _part(
        backendId: 101,
        backendRecordingId: 900,
        sent: true,
      );
      final Map<String, Object?> persisted = completed.toJson()
        ..addAll(recordingPartContentUpdateFields(stale));

      expect(persisted['gpsLatitudeStart'], 50.5);
      expect(persisted['path'], 'logical://refreshed-cache.wav');
      expect(persisted['BEId'], 101);
      expect(persisted['backendRecordingId'], 900);
      expect(persisted['sent'], 1);
      expect(persisted['uploadKey'], 'part-upload-key-1');
    });
  });

  group('post-upload workflow leases', () {
    late RecordingWorkflowLeaseService workflow;

    setUp(() {
      workflow = RecordingWorkflowLeaseService(
        store: harness.store,
        sessions: harness.sessions,
      );
      harness.seed(
        _recording(backendId: 900, sent: true),
        <RecordingPart>[
          _part(
            backendId: 101,
            backendRecordingId: 900,
            sent: true,
          ),
        ],
      );
    });

    for (final String reservedLeaseId in <String>[
      'delete:42',
      '  DELETE:42:worker  ',
    ]) {
      test('rejects reserved workflow lease id "$reservedLeaseId"', () async {
        await expectLater(
          workflow.run<void>(
            recordingId: 42,
            leaseId: reservedLeaseId,
            operation: (_) async {},
          ),
          throwsA(_validationContaining('non-reserved')),
        );

        expect(harness.sessions.captureCalls, 0);
        expect(harness.store.calls, isEmpty);
      });
    }

    test('a deletion-held lease prevents the dialect workflow', () async {
      harness.store.forceBusy = true;
      bool operationStarted = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            operationStarted = true;
          },
        ),
        throwsA(
          isA<UploadException>().having(
            (UploadException error) => error.statusCode,
            'statusCode',
            409,
          ),
        ),
      );

      expect(operationStarted, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('an unreviewed capture cannot enter a post-upload workflow', () async {
      harness.seed(
        _recording(
          backendId: 900,
          sent: true,
          captureReviewed: false,
        ),
        <RecordingPart>[
          _part(
            backendId: 101,
            backendRecordingId: 900,
            sent: true,
          ),
        ],
      );
      bool operationStarted = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            operationStarted = true;
          },
        ),
        throwsA(_validationContaining('not been reviewed')),
      );

      expect(operationStarted, isFalse);
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('cleans up when workflow acquire commits but acknowledgement is lost',
        () async {
      final _TestException failure =
          _TestException('workflow claim result lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.acquireRecording,
          invocation: 1,
          error: failure,
        ),
      );
      bool operationStarted = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            operationStarted = true;
          },
        ),
        throwsA(same(failure)),
      );

      expect(operationStarted, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
    });

    test('rejects a workflow row that does not match the acquired id',
        () async {
      harness.seed(
        _recording(id: 99, backendId: 900, sent: true),
        <RecordingPart>[
          _part(
            recordingId: 99,
            backendId: 101,
            backendRecordingId: 900,
            sent: true,
          ),
        ],
        storageId: 42,
      );
      bool operationStarted = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            operationStarted = true;
          },
        ),
        throwsA(_validationContaining('workflow lease')),
      );

      expect(operationStarted, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('blocks a competing deletion until the workflow is released',
        () async {
      final _AsyncGate gate = _AsyncGate();
      final Future<String> running = workflow.run<String>(
        recordingId: 42,
        leaseId: 'dialect-lease',
        operation: (RecordingWorkflowLeaseContext context) async {
          expect(context.recording.BEId, 900);
          expect(
            context.session.backendHost,
            'api.production.example.test',
          );
          await gate.block();
          return 'done';
        },
      );

      await gate.entered.future;
      expect(
        await harness.store.tryAcquireRecording(42, 'delete:42:test'),
        isFalse,
      );
      gate.release();

      expect(await running, 'done');
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(
        await harness.store.tryAcquireRecording(42, 'delete:42:test'),
        isTrue,
      );
      await harness.store.releaseRecording(42, 'delete:42:test');
    });

    test('heartbeats prevent deletion during a long workflow request',
        () async {
      harness = _UploadHarness(
        storeLeaseTimeout: const Duration(milliseconds: 12),
      );
      harness.seed(
        _recording(backendId: 900, sent: true),
        <RecordingPart>[
          _part(
            backendId: 101,
            backendRecordingId: 900,
            sent: true,
          ),
        ],
      );
      workflow = RecordingWorkflowLeaseService(
        store: harness.store,
        sessions: harness.sessions,
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
      );
      final _AsyncGate gate = _AsyncGate();
      final Future<void> running = workflow.run<void>(
        recordingId: 42,
        leaseId: 'dialect-lease',
        operation: (_) => gate.block(),
      );

      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        await harness.store.tryAcquireRecording(42, 'delete:42:test'),
        isFalse,
      );
      expect(
        harness.store.count(_StoreOperation.renewRecording),
        greaterThan(0),
      );

      gate.release();
      await running;
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('session loss still keeps a long workflow leased while it unwinds',
        () async {
      harness = _UploadHarness(
        storeLeaseTimeout: const Duration(milliseconds: 12),
      );
      harness.seed(
        _recording(backendId: 900, sent: true),
        <RecordingPart>[
          _part(
            backendId: 101,
            backendRecordingId: 900,
            sent: true,
          ),
        ],
      );
      harness.sessions.notCurrentAt.addAll(
        List<int>.generate(999, (int index) => index + 2),
      );
      workflow = RecordingWorkflowLeaseService(
        store: harness.store,
        sessions: harness.sessions,
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
      );
      final _AsyncGate gate = _AsyncGate();
      final Future<void> running = workflow.run<void>(
        recordingId: 42,
        leaseId: 'dialect-lease',
        operation: (_) => gate.block(),
      );

      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        await harness.store.tryAcquireRecording(42, 'delete:42:test'),
        isFalse,
      );
      expect(
        harness.store.count(_StoreOperation.renewRecording),
        greaterThan(1),
      );

      gate.release();
      await expectLater(
        running,
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('heartbeat failure aborts workflow completion and releases ownership',
        () async {
      workflow = RecordingWorkflowLeaseService(
        store: harness.store,
        sessions: harness.sessions,
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
      );
      final _TestException failure =
          _TestException('workflow heartbeat failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.renewRecording,
          invocation: 1,
          error: failure,
        ),
      );
      final _AsyncGate gate = _AsyncGate();
      final Future<void> running = workflow.run<void>(
        recordingId: 42,
        leaseId: 'dialect-lease',
        operation: (_) => gate.block(),
      );

      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      gate.release();

      await expectLater(running, throwsA(same(failure)));
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
    });

    test('final renewal catches a session change after a fast operation',
        () async {
      harness.sessions.notCurrentAt.add(2);
      bool operationCompleted = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            operationCompleted = true;
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(operationCompleted, isTrue);
      expect(harness.store.count(_StoreOperation.renewRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('operation failure stays primary and skips the final renewal',
        () async {
      final _TestException failure =
          _TestException('workflow operation failed');

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (_) async {
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );

      expect(harness.store.count(_StoreOperation.renewRecording), 0);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('environment or account change stops the next workflow request',
        () async {
      harness.sessions.notCurrentAt.add(2);
      bool sentAfterRenewal = false;

      await expectLater(
        workflow.run<void>(
          recordingId: 42,
          leaseId: 'dialect-lease',
          operation: (RecordingWorkflowLeaseContext context) async {
            await context.renew();
            sentAfterRenewal = true;
          },
        ),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(sentAfterRenewal, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });
  });

  group('input validation and recording leases', () {
    for (final int invalidId in <int>[0, -1]) {
      test('rejects invalid recording id $invalidId before touching the store',
          () async {
        await expectLater(
          harness.service.send(invalidId),
          throwsA(_validationContaining('positive integer')),
        );

        expect(harness.store.calls, isEmpty);
        expect(harness.api.calls, isEmpty);
      });
    }

    for (final String invalidLeaseId in <String>['', '   ']) {
      test(
          'rejects ${invalidLeaseId.isEmpty ? 'an empty' : 'a whitespace-only'} '
          'lease id before touching the store', () async {
        harness = _UploadHarness(newLeaseId: () => invalidLeaseId);

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('must not be empty')),
        );

        expect(harness.store.calls, isEmpty);
        expect(harness.api.calls, isEmpty);
      });
    }

    for (final String reservedLeaseId in <String>[
      'delete:42',
      '  DELETE:42:worker  ',
    ]) {
      test('rejects reserved upload lease id "$reservedLeaseId"', () async {
        harness = _UploadHarness(newLeaseId: () => reservedLeaseId);

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('reserved prefix')),
        );

        expect(harness.store.calls, isEmpty);
        expect(harness.api.calls, isEmpty);
      });
    }

    test('returns busy without loading or contacting the API', () async {
      harness.store.forceBusy = true;

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.busy);
      expect(result.recording, isNull);
      expect(harness.store.count(_StoreOperation.acquireRecording), 1);
      expect(harness.store.count(_StoreOperation.loadRecording), 0);
      expect(harness.api.calls, isEmpty);
    });

    test('releases a lease when the recording disappears after acquisition',
        () async {
      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('not found')),
      );

      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.api.calls, isEmpty);
    });

    test('releases a lease and preserves a load failure', () async {
      final _TestException failure = _TestException('load recording failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.loadRecording,
          invocation: 1,
          error: failure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.api.calls, isEmpty);
    });

    test('cleans up an acquire that commits and then reports failure',
        () async {
      final _TestException failure = _TestException('claim result lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.acquireRecording,
          invocation: 1,
          error: failure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.api.calls, isEmpty);
    });

    test('rejects a loaded recording that does not match the leased id',
        () async {
      final Recording wrongRecording = _recording(id: 99, partCount: 1);
      harness.seed(
        wrongRecording,
        <RecordingPart>[_part(id: 1, recordingId: 99)],
        storageId: 42,
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('does not match')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('returns alreadySent only after aggregate and session validation',
        () async {
      harness.seed(
        _recording(
          sent: true,
          backendId: 900,
          partCount: 0,
        ),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.alreadySent);
      expect(result.recording!.BEId, 900);
      expect(harness.store.count(_StoreOperation.loadParts), 1);
      expect(harness.policy.calls, 1);
      expect(harness.sessions.captureCalls, 1);
      expect(harness.sessions.currentCalls, 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.partCount, 0);
      expect(harness.store.count(_StoreOperation.saveRecording), 0);
      expect(harness.api.calls, isEmpty);

      final int loadPartsIndex = harness.trace.indexOf('store.loadParts#1');
      final int sessionIndex = harness.trace.indexOf('session.current#1');
      final int releaseIndex =
          harness.trace.indexOf('store.releaseRecording#1');
      expect(loadPartsIndex, greaterThan(-1));
      expect(sessionIndex, greaterThan(loadPartsIndex));
      expect(releaseIndex, greaterThan(sessionIndex));
    });

    test('sent parent with a missing part row fails before any API call',
        () async {
      harness.seed(
        _recording(
          sent: true,
          backendId: 900,
          partCount: 2,
        ),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('Expected 2')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.policy.calls, 0);
      expect(harness.sessions.captureCalls, 0);
      expect(harness.store.recordingSnapshot(42)!.sent, isTrue);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });
  });

  group('policy, authentication, and aggregate validation', () {
    test('defers an unreviewed capture before policy, session, or API',
        () async {
      harness.seed(
        _recording(captureReviewed: false),
        <RecordingPart>[_part()],
      );

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.deferred);
      expect(result.reason, contains('reviewed'));
      expect(result.recording!.captureReviewed, isFalse);
      expect(harness.store.count(_StoreOperation.loadParts), 0);
      expect(harness.policy.calls, 0);
      expect(harness.sessions.captureCalls, 0);
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
    });

    test('defers when policy disallows upload and releases the lease',
        () async {
      harness.seedBasic(partCount: 1);
      harness.policy.allowed = false;

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.deferred);
      expect(result.reason, contains('network policy'));
      expect(harness.sessions.captureCalls, 0);
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('defers when no authenticated session exists', () async {
      harness.seedBasic(partCount: 1);
      harness.sessions.capturedSession = null;

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.deferred);
      expect(result.reason, contains('authenticated session'));
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('policy failure is propagated and the lease is released', () async {
      harness.seedBasic(partCount: 1);
      final _TestException failure = _TestException('policy read failed');
      harness.policy.error = failure;

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('session capture failure is propagated and the lease is released',
        () async {
      harness.seedBasic(partCount: 1);
      final _TestException failure = _TestException('auth read failed');
      harness.sessions.captureError = failure;

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    for (final ({
      String label,
      String userId,
      String accessToken,
      String logicalSessionId,
      String environment,
      String backendHost,
    }) invalid in const <({
      String label,
      String userId,
      String accessToken,
      String logicalSessionId,
      String environment,
      String backendHost,
    })>[
      (
        label: 'user id',
        userId: '   ',
        accessToken: 'token',
        logicalSessionId: 'logical-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
      ),
      (
        label: 'access token',
        userId: '7',
        accessToken: ' ',
        logicalSessionId: 'logical-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
      ),
      (
        label: 'logical session id',
        userId: '7',
        accessToken: 'token',
        logicalSessionId: ' ',
        environment: 'prod',
        backendHost: 'api.production.example.test',
      ),
      (
        label: 'environment',
        userId: '7',
        accessToken: 'token',
        logicalSessionId: 'logical-session',
        environment: '',
        backendHost: 'api.production.example.test',
      ),
      (
        label: 'backend host',
        userId: '7',
        accessToken: 'token',
        logicalSessionId: 'logical-session',
        environment: 'prod',
        backendHost: '   ',
      ),
    ]) {
      test('rejects an empty captured ${invalid.label}', () async {
        harness.seedBasic(partCount: 1);
        harness.sessions.capturedSession = RecordingUploadSession(
          userId: invalid.userId,
          accessToken: invalid.accessToken,
          logicalSessionId: invalid.logicalSessionId,
          environment: invalid.environment,
          backendHost: invalid.backendHost,
          accountEmail: 'bird@example.test',
        );

        await expectLater(
          harness.service.send(42),
          throwsA(isA<RecordingUploadSessionChangedException>()),
        );

        expect(harness.api.calls, isEmpty);
        expect(harness.store.hasRecordingLease(42), isFalse);
      });
    }

    test('rejects an empty part list before policy and API work', () async {
      harness.seed(_recording(partCount: 0), const <RecordingPart>[]);

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('without recording parts')),
      );

      expect(harness.policy.calls, 0);
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    for (final String? uploadKey in <String?>[null, '', '   ']) {
      test(
          'rejects ${_uploadKeyDescription(uploadKey)} '
          'recording upload key before API work', () async {
        harness.seed(
          _recording(
            sent: true,
            backendId: 900,
            uploadKey: uploadKey,
          ),
          <RecordingPart>[
            _part(
              id: 1,
              sent: true,
              backendId: 101,
              backendRecordingId: 900,
            ),
          ],
        );

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('no durable upload key')),
        );

        expect(harness.policy.calls, 0);
        expect(harness.sessions.captureCalls, 0);
        expect(harness.api.calls, isEmpty);
        expect(harness.store.hasRecordingLease(42), isFalse);
      });
    }

    for (final String? uploadKey in <String?>[null, '', '   ']) {
      test(
          'rejects ${_uploadKeyDescription(uploadKey)} '
          'part upload key before API work', () async {
        harness.seed(
          _recording(
            sent: true,
            backendId: 900,
          ),
          <RecordingPart>[
            _part(
              id: 1,
              sent: true,
              backendId: 101,
              backendRecordingId: 900,
              uploadKey: uploadKey,
              omitUploadKey: uploadKey == null,
            ),
          ],
        );

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('no durable upload key')),
        );

        expect(harness.policy.calls, 0);
        expect(harness.sessions.captureCalls, 0);
        expect(harness.api.calls, isEmpty);
        expect(harness.store.hasRecordingLease(42), isFalse);
      });
    }

    test('rejects a configured part count mismatch', () async {
      harness.seed(
        _recording(partCount: 3),
        <RecordingPart>[
          _part(id: 1),
          _part(id: 2),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('Expected 3')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    for (final int? invalidPartId in <int?>[null, 0, -1]) {
      test('rejects invalid local part id $invalidPartId', () async {
        harness.seed(
          _recording(partCount: 1),
          <RecordingPart>[_part(id: invalidPartId)],
        );

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('positive local id')),
        );

        expect(harness.api.calls, isEmpty);
      });
    }

    test('rejects duplicate local part ids', () async {
      harness.seed(
        _recording(partCount: 2),
        <RecordingPart>[
          _part(id: 1),
          _part(id: 1),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('Duplicate local')),
      );

      expect(harness.api.calls, isEmpty);
    });

    test('rejects a part owned by another recording', () async {
      harness.seed(
        _recording(partCount: 1),
        <RecordingPart>[_part(id: 1, recordingId: 77)],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('different recording')),
      );

      expect(harness.api.calls, isEmpty);
    });

    test('rejects duplicate durable part keys before creating a parent',
        () async {
      harness.seed(
        _recording(partCount: 2),
        <RecordingPart>[
          _part(id: 1, uploadKey: 'shared-part-key'),
          _part(id: 2, uploadKey: 'shared-part-key'),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('duplicate durable upload key')),
      );

      expect(harness.policy.calls, 0);
      expect(harness.sessions.captureCalls, 0);
      expect(harness.api.calls, isEmpty);
    });

    test('rejects a negative configured part count', () async {
      harness.seed(
        _recording(partCount: -1),
        <RecordingPart>[_part(id: 1)],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('invalid expected part count')),
      );

      expect(harness.api.calls, isEmpty);
    });

    for (final ({
      String label,
      double value,
      void Function(RecordingPart, double) apply,
    }) invalid in <({
      String label,
      double value,
      void Function(RecordingPart, double) apply,
    })>[
      (
        label: 'non-finite start latitude',
        value: double.nan,
        apply: (RecordingPart part, double value) =>
            part.gpsLatitudeStart = value,
      ),
      (
        label: 'non-finite end longitude',
        value: double.infinity,
        apply: (RecordingPart part, double value) =>
            part.gpsLongitudeEnd = value,
      ),
      (
        label: 'latitude above 90',
        value: 90.0001,
        apply: (RecordingPart part, double value) =>
            part.gpsLatitudeEnd = value,
      ),
      (
        label: 'latitude below -90',
        value: -90.0001,
        apply: (RecordingPart part, double value) =>
            part.gpsLatitudeStart = value,
      ),
      (
        label: 'longitude above 180',
        value: 180.0001,
        apply: (RecordingPart part, double value) =>
            part.gpsLongitudeStart = value,
      ),
      (
        label: 'longitude below -180',
        value: -180.0001,
        apply: (RecordingPart part, double value) =>
            part.gpsLongitudeEnd = value,
      ),
    ]) {
      test('rejects ${invalid.label} before creating a parent', () async {
        final RecordingPart part = _part(id: 1);
        invalid.apply(part, invalid.value);
        harness.seed(_recording(partCount: 1), <RecordingPart>[part]);

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('invalid GPS')),
        );

        expect(harness.api.calls, isEmpty);
      });
    }

    for (final String timeRange in <String>['zero', 'backwards']) {
      test('rejects a $timeRange part time range before creating a parent',
          () async {
        final RecordingPart part = _part(id: 1);
        part.endTime = timeRange == 'zero'
            ? part.startTime
            : part.startTime.subtract(const Duration(seconds: 1));
        harness.seed(_recording(partCount: 1), <RecordingPart>[part]);

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('invalid time range')),
        );

        expect(harness.api.calls, isEmpty);
      });
    }

    test('rejects a whitespace-only path before creating a parent', () async {
      harness.seed(
        _recording(partCount: 1),
        <RecordingPart>[_part(id: 1, path: '   ')],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('no readable local file')),
      );

      expect(harness.files.calls, isEmpty);
      expect(harness.api.calls, isEmpty);
    });

    for (final int invalidBackendId in <int>[0, -1]) {
      test('rejects existing parent backend id $invalidBackendId', () async {
        harness.seed(
          _recording(
            backendId: invalidBackendId,
            partCount: 1,
          ),
          <RecordingPart>[_part(id: 1)],
        );

        await expectLater(
          harness.service.send(42),
          throwsA(
            isA<UploadException>().having(
              (UploadException error) => error.statusCode,
              'statusCode',
              502,
            ),
          ),
        );

        expect(harness.api.calls, isEmpty);
      });
    }

    test('rejects a sent part without a valid backend id', () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: null,
            backendRecordingId: 900,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('no valid backend id')),
      );

      expect(harness.api.partCalls, isEmpty);
    });

    test('rejects a sent part associated with another backend parent',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 901,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 900')),
      );

      expect(harness.api.partCalls, isEmpty);
    });
  });

  group('successful upload and resume behavior', () {
    test('a throwing progress observer cannot fail a successful upload',
        () async {
      harness.seedBasic(partCount: 1);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(
        1,
        _ApiStep<int>.returning(
          101,
          progress: const <(int, int)>[(4, 10), (10, 10)],
        ),
      );
      int observerCalls = 0;

      final RecordingUploadResult result = await harness.service.send(
        42,
        onProgress: (int _, int __, int ___) {
          observerCalls++;
          throw const _TestException('observer failed');
        },
      );

      expect(observerCalls, 2);
      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.store.recordingSnapshot(42)!.sent, isTrue);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.api.remoteParentCreations, 1);
      expect(harness.api.remotePartCreations, 1);
    });

    test('uploads a new parent and all parts with durable ordered transitions',
        () async {
      harness.seedBasic(partCount: 3);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(
        1,
        _ApiStep<int>.returning(
          101,
          progress: const <(int, int)>[(4, 10), (10, 10)],
        ),
      );
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.api.scriptPart(3, _ApiStep<int>.returning(103));
      final List<(int, int, int)> progress = <(int, int, int)>[];

      final RecordingUploadResult result = await harness.service.send(
        42,
        onProgress: (int partId, int sent, int total) {
          progress.add((partId, sent, total));
        },
      );

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(result.recording!.sent, isTrue);
      expect(result.recording!.sending, isFalse);
      expect(result.recording!.BEId, 900);
      expect(
        progress,
        const <(int, int, int)>[(1, 4, 10), (1, 10, 10)],
      );

      final Recording persisted = harness.store.recordingSnapshot(42)!;
      expect(persisted.sent, isTrue);
      expect(persisted.sending, isFalse);
      expect(persisted.BEId, 900);
      expect(
        harness.store.partSnapshots(42).map((RecordingPart part) => part.BEId),
        <int?>[101, 102, 103],
      );
      expect(
        harness.store
            .partSnapshots(42)
            .every((RecordingPart part) => part.sent && !part.sending),
        isTrue,
      );
      expect(harness.store.completedExpectedCounts, <int>[3]);
      expect(harness.store.hasRecordingLease(42), isFalse);

      expect(harness.api.createCalls.single.idempotencyKey,
          'recording:recording-upload-key-42');
      expect(
        harness.api.partCalls
            .map((_PartCall call) => call.idempotencyKey)
            .toList(),
        <String>[
          'recording-part:part-upload-key-1',
          'recording-part:part-upload-key-2',
          'recording-part:part-upload-key-3',
        ],
      );
      expect(
        harness.api.partCalls
            .map((_PartCall call) => call.part.backendRecordingId)
            .toSet(),
        <int?>{900},
      );
      expect(
        harness.api.partCalls.every(
            (_PartCall call) => identical(call.session, _defaultSession)),
        isTrue,
      );

      final int createIndex = harness.trace.indexOf(
        'api.create:recording:recording-upload-key-42',
      );
      final int freezeRequestIndex =
          harness.trace.indexOf('store.saveRecording#1');
      final int saveParentIndex =
          harness.trace.indexOf('store.saveRecording#2');
      final int firstPartIndex = harness.trace.indexOf('api.uploadPart:1');
      final int completionIndex =
          harness.trace.indexOf('store.completeRecording#1');
      expect(createIndex, greaterThan(-1));
      expect(freezeRequestIndex, lessThan(createIndex));
      expect(saveParentIndex, greaterThan(createIndex));
      expect(firstPartIndex, greaterThan(saveParentIndex));
      expect(completionIndex, greaterThan(firstPartIndex));
    });

    test('uses an existing parent and does not recreate it', () async {
      harness.seedBasic(partCount: 2, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, isEmpty);
      expect(
        harness.api.partCalls.map((_PartCall call) => call.partId),
        <int>[1, 2],
      );
    });

    test('repairs an unsent part under a stale sent parent', () async {
      harness.seed(
        _recording(
          sent: true,
          backendId: 900,
          partCount: 1,
        ),
        <RecordingPart>[_part(id: 1)],
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, isEmpty);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.partCalls.single.part.backendRecordingId, 900);
      expect(harness.store.count(_StoreOperation.saveRecording), 1);
      expect(harness.store.recordingSnapshot(42)!.sent, isTrue);
      expect(harness.store.recordingSnapshot(42)!.BEId, 900);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.store.partSnapshots(42).single.BEId, 101);
      expect(harness.store.hasRecordingLease(42), isFalse);

      final int clearStaleSentIndex =
          harness.trace.indexOf('store.saveRecording#1');
      final int uploadIndex = harness.trace.indexOf('api.uploadPart:1');
      expect(clearStaleSentIndex, greaterThan(-1));
      expect(uploadIndex, greaterThan(clearStaleSentIndex));
    });

    test('skips already-sent parts and uploads only missing parts', () async {
      harness.seed(
        _recording(backendId: 900, partCount: 3),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
          _part(id: 2),
          _part(
            id: 3,
            sent: true,
            backendId: 103,
            backendRecordingId: 900,
          ),
        ],
      );
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, isEmpty);
      expect(
        harness.api.partCalls.map((_PartCall call) => call.partId),
        <int>[2],
      );
      expect(harness.files.calls, <String>[
        'logical://part-2.wav',
        'logical://part-2.wav',
      ]);
    });

    test('uses initial part length when configured count is absent', () async {
      harness.seedBasic(partCount: 0, backendId: 900, numberOfParts: 2);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.store.completedExpectedCounts, <int>[2]);
      expect(harness.api.createCalls, isEmpty);
      expect(harness.store.recordingSnapshot(42)!.partCount, 0);
    });

    test('freezes fallback part length into the first parent request',
        () async {
      harness.seedBasic(partCount: 0, numberOfParts: 2);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(1));
      expect(harness.api.createCalls.single.recording.partCount, 2);
      expect(harness.store.recordingSnapshot(42)!.partCount, 2);
      expect(
        harness.trace.indexOf('store.saveRecording#1'),
        lessThan(
          harness.trace.indexOf('api.create:recording:recording-upload-key-42'),
        ),
      );
    });

    test('recycled local ids use new durable parent and part upload keys',
        () async {
      harness.seed(
        _recording(uploadKey: 'recording-generation-a'),
        <RecordingPart>[
          _part(id: 1, uploadKey: 'part-generation-a'),
        ],
      );
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final RecordingUploadResult first = await harness.service.send(42);

      harness.seed(
        _recording(uploadKey: 'recording-generation-b'),
        <RecordingPart>[
          _part(id: 1, uploadKey: 'part-generation-b'),
        ],
      );
      harness.api.scriptCreate(_ApiStep<int>.returning(901));
      harness.api.scriptPart(1, _ApiStep<int>.returning(102));

      final RecordingUploadResult second = await harness.service.send(42);

      expect(first.status, RecordingUploadStatus.uploaded);
      expect(second.status, RecordingUploadStatus.uploaded);
      expect(
        harness.api.createCalls
            .map((_CreateCall call) => call.idempotencyKey)
            .toList(),
        <String>[
          'recording:recording-generation-a',
          'recording:recording-generation-b',
        ],
      );
      expect(
        harness.api.partCalls
            .map((_PartCall call) => call.idempotencyKey)
            .toList(),
        <String>[
          'recording-part:part-generation-a',
          'recording-part:part-generation-b',
        ],
      );
      expect(harness.api.remoteParentCreations, 2);
      expect(harness.api.remotePartCreations, 2);
      expect(harness.store.recordingSnapshot(42)!.BEId, 901);
      expect(harness.store.partSnapshots(42).single.BEId, 102);
    });
  });

  group('pre-network recording and session binding', () {
    for (final String invalidUserId in <String>['0', '-7', 'not-a-number']) {
      test(
          'rejects invalid captured user id "$invalidUserId" before owner binding',
          () async {
        harness.seed(
          _recording(userId: null, mail: null),
          <RecordingPart>[_part(id: 1)],
        );
        harness.sessions.capturedSession = RecordingUploadSession(
          userId: invalidUserId,
          accessToken: 'corrupt-owner-token',
          logicalSessionId: 'logical-session',
          environment: 'prod',
          backendHost: 'api.production.example.test',
          accountEmail: 'bird@example.test',
        );

        await expectLater(
          harness.service.send(42),
          throwsA(isA<RecordingUploadSessionChangedException>()),
        );

        final Recording persisted = harness.store.recordingSnapshot(42)!;
        expect(persisted.userId, isNull);
        expect(persisted.mail, isNull);
        expect(harness.store.count(_StoreOperation.saveRecording), 0);
        expect(harness.sessions.currentCalls, 0);
        _expectRejectedSessionBinding(harness);
      });
    }

    test('complete sent aggregate still enforces session binding', () async {
      harness.seed(
        _recording(
          sent: true,
          backendId: 900,
          partCount: 1,
        ),
        <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );
      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '8',
        accessToken: 'other-user-token',
        logicalSessionId: 'other-user-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: 'bird@example.test',
      );

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      _expectRejectedSessionBinding(harness);
      expect(harness.sessions.currentCalls, 0);
      expect(harness.store.count(_StoreOperation.loadParts), 1);
      expect(harness.store.recordingSnapshot(42)!.sent, isTrue);
    });

    test('rejects an environment mismatch before any API call', () async {
      harness.seed(
        _recording(
          environment: 'dev',
          partCount: 1,
        ),
        <RecordingPart>[_part(id: 1)],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      _expectRejectedSessionBinding(harness);
      expect(harness.sessions.currentCalls, 0);
    });

    test('rejects a local numeric user id mismatch before any API call',
        () async {
      harness.seedBasic(partCount: 1);
      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '8',
        accessToken: 'other-user-token',
        logicalSessionId: 'other-user-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: 'bird@example.test',
      );

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      _expectRejectedSessionBinding(harness);
      expect(harness.sessions.currentCalls, 0);
    });

    test('rejects an owner email mismatch before any API call', () async {
      harness.seedBasic(partCount: 1);
      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '7',
        accessToken: 'other-email-token',
        logicalSessionId: 'other-email-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: 'another@example.test',
      );

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      _expectRejectedSessionBinding(harness);
      expect(harness.sessions.currentCalls, 0);
    });

    for (final String? missingEmail in <String?>[null, '', '   ']) {
      test(
          'rejects missing session owner email '
          '${missingEmail == null ? 'null' : '"$missingEmail"'}', () async {
        harness.seedBasic(partCount: 1);
        harness.sessions.capturedSession = RecordingUploadSession(
          userId: '7',
          accessToken: 'missing-email-token',
          logicalSessionId: 'missing-email-session',
          environment: 'prod',
          backendHost: 'api.production.example.test',
          accountEmail: missingEmail,
        );

        await expectLater(
          harness.service.send(42),
          throwsA(isA<RecordingUploadSessionChangedException>()),
        );

        _expectRejectedSessionBinding(harness);
        expect(harness.sessions.currentCalls, 0);
      });
    }

    test('accepts owner email case-insensitively after trimming', () async {
      harness.seed(
        _recording(
          backendId: 900,
          mail: '  Bird@Example.Test  ',
          partCount: 1,
        ),
        <RecordingPart>[_part(id: 1)],
      );
      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '7',
        accessToken: 'case-insensitive-email-token',
        logicalSessionId: 'case-insensitive-email-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: 'bird@example.test',
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, isEmpty);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('durably claims absent owner fields before creating the parent',
        () async {
      harness.seed(
        _recording(
          userId: null,
          mail: '   ',
          partCount: 1,
        ),
        <RecordingPart>[_part(id: 1)],
      );
      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '7',
        accessToken: 'claim-owner-token',
        logicalSessionId: 'claim-owner-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: '  Bird@Example.Test  ',
      );
      final _TestException failure =
          _TestException('parent request rejected after claim');
      harness.api.scriptCreate(_ApiStep<int>.throwing(failure));

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      final Recording persisted = harness.store.recordingSnapshot(42)!;
      expect(persisted.userId, 7);
      expect(persisted.mail, 'Bird@Example.Test');
      expect(persisted.sending, isFalse);
      expect(harness.api.createCalls.single.recording.userId, 7);
      expect(
        harness.api.createCalls.single.recording.mail,
        'Bird@Example.Test',
      );
      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);

      final int claimIndex = harness.trace.indexOf('store.saveRecording#1');
      final int networkIndex = harness.trace.indexOf(
        'api.create:recording:recording-upload-key-42',
      );
      expect(claimIndex, greaterThan(-1));
      expect(networkIndex, greaterThan(claimIndex));
    });
  });

  group('remote parent failures and idempotent recovery', () {
    test('parent API failure releases the recording and sends no parts',
        () async {
      harness.seedBasic(partCount: 2);
      final _TestException failure = _TestException('parent timeout');
      harness.api.scriptCreate(_ApiStep<int>.throwing(failure));

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('fallback part count survives request-freeze acknowledgement loss',
        () async {
      harness.seedBasic(partCount: 0, numberOfParts: 2);
      final _TestException dbFailure =
          _TestException('request freeze acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.saveRecording,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));

      final Recording frozen = harness.store.recordingSnapshot(42)!;
      expect(frozen.partCount, 2);
      expect(frozen.parentUploadAttempted, isTrue);
      expect(frozen.sending, isFalse);
      expect(harness.api.createCalls, isEmpty);

      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls.single.recording.partCount, 2);
      expect(harness.store.recordingSnapshot(42)!.partCount, 2);
    });

    for (final int backendId in <int>[0, -7]) {
      test('rejects malformed parent response id $backendId', () async {
        harness.seedBasic(partCount: 1);
        harness.api.scriptCreate(_ApiStep<int>.returning(backendId));

        await expectLater(
          harness.service.send(42),
          throwsA(
            isA<UploadException>().having(
              (UploadException error) => error.statusCode,
              'statusCode',
              502,
            ),
          ),
        );

        expect(harness.api.partCalls, isEmpty);
        expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
        expect(harness.store.hasRecordingLease(42), isFalse);
      });
    }

    test(
        'replays the same parent idempotency key after remote commit then timeout',
        () async {
      harness.seedBasic(partCount: 1);
      final _TestException timeout = _TestException('response lost');
      harness.api.scriptCreate(
        _ApiStep<int>.commitThenThrow(900, timeout),
      );

      await expectLater(harness.service.send(42), throwsA(same(timeout)));
      expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
      expect(
        harness.store.recordingSnapshot(42)!.parentUploadAttempted,
        isTrue,
      );
      expect(
        harness.store.recordingSnapshot(42)!.uploadDeviceId,
        'device-token-A',
      );

      harness.sessions.capturedSession = const RecordingUploadSession(
        userId: '7',
        accessToken: 'test-token',
        logicalSessionId: 'rotated-device-session',
        environment: 'prod',
        backendHost: 'api.production.example.test',
        accountEmail: 'bird@example.test',
        deviceId: 'rotated-device-token',
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(2));
      expect(
        harness.api.createCalls
            .map((_CreateCall call) => call.idempotencyKey)
            .toSet(),
        <String>{'recording:recording-upload-key-42'},
      );
      expect(
        harness.api.createCalls
            .map((_CreateCall call) => call.recording.uploadDeviceId)
            .toSet(),
        <String?>{'device-token-A'},
      );
      expect(harness.api.remoteParentCreations, 1);
      expect(harness.store.recordingSnapshot(42)!.BEId, 900);
    });

    test('save-parent failure before commit retries with the stable key',
        () async {
      harness.seedBasic(partCount: 1);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      final _TestException dbFailure = _TestException('save parent failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.saveRecording,
          invocation: 2,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      expect(harness.store.recordingSnapshot(42)!.BEId, isNull);

      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(2));
      expect(harness.api.remoteParentCreations, 1);
      expect(
        harness.api.createCalls.first.idempotencyKey,
        harness.api.createCalls.last.idempotencyKey,
      );
    });

    test('save-parent failure after commit resumes without another POST',
        () async {
      harness.seedBasic(partCount: 1);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      final _TestException dbFailure =
          _TestException('save parent acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.saveRecording,
          invocation: 2,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      expect(harness.store.recordingSnapshot(42)!.BEId, 900);

      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(1));
      expect(harness.api.remoteParentCreations, 1);
    });
  });

  group('part API failures and partial retry', () {
    for (final int failureIndex in <int>[0, 1, 2]) {
      test('failure at ${_ordinal(failureIndex + 1)} part is fail-fast',
          () async {
        harness.seedBasic(partCount: 3);
        harness.api.scriptCreate(_ApiStep<int>.returning(900));
        final _TestException failure =
            _TestException('part ${failureIndex + 1} failed');
        for (int index = 0; index < failureIndex; index++) {
          harness.api.scriptPart(
            index + 1,
            _ApiStep<int>.returning(101 + index),
          );
        }
        harness.api.scriptPart(
          failureIndex + 1,
          _ApiStep<int>.throwing(failure),
        );

        await expectLater(harness.service.send(42), throwsA(same(failure)));

        expect(
          harness.api.partCalls.map((_PartCall call) => call.partId),
          List<int>.generate(failureIndex + 1, (int index) => index + 1),
        );
        final List<RecordingPart> persisted = harness.store.partSnapshots(42);
        for (int index = 0; index < persisted.length; index++) {
          expect(persisted[index].sent, index < failureIndex);
          expect(persisted[index].sending, isFalse);
        }
        expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
        expect(harness.store.recordingSnapshot(42)!.BEId, 900);
      });
    }

    test(
        'middle-part retry keeps the parent and uploads only the missing suffix',
        () async {
      harness.seedBasic(partCount: 3);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException timeout = _TestException('middle timeout');
      harness.api.scriptPart(2, _ApiStep<int>.throwing(timeout));

      await expectLater(harness.service.send(42), throwsA(same(timeout)));

      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.api.scriptPart(3, _ApiStep<int>.returning(103));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(1));
      expect(
        harness.api.partCalls.map((_PartCall call) => call.partId),
        <int>[1, 2, 2, 3],
      );
      expect(
        harness.api.partCalls
            .where((_PartCall call) => call.partId == 2)
            .map((_PartCall call) => call.idempotencyKey)
            .toSet(),
        <String>{'recording-part:part-upload-key-2'},
      );
    });

    for (final int backendId in <int>[0, -3]) {
      test('rejects malformed part response id $backendId', () async {
        harness.seedBasic(partCount: 1, backendId: 900);
        harness.api.scriptPart(1, _ApiStep<int>.returning(backendId));

        await expectLater(
          harness.service.send(42),
          throwsA(
            isA<UploadException>().having(
              (UploadException error) => error.statusCode,
              'statusCode',
              502,
            ),
          ),
        );

        final RecordingPart persisted = harness.store.partSnapshots(42).single;
        expect(persisted.sent, isFalse);
        expect(persisted.sending, isFalse);
        expect(persisted.BEId, isNull);
        expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
      });
    }

    test('busy part fails without issuing its upload request', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.store.forceBusyPartIds.add(1);

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('busy')),
      );

      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('part commit-then-timeout replays one stable remote operation',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException timeout = _TestException('part response lost');
      harness.api.scriptPart(
        1,
        _ApiStep<int>.commitThenThrow(101, timeout),
      );

      await expectLater(harness.service.send(42), throwsA(same(timeout)));

      final _PartCall firstAttempt = harness.api.partCalls.single;
      expect(
        harness.store.partSnapshots(42).single.uploadAttempted,
        isTrue,
      );
      expect(
        harness.store.partSnapshots(42).single.uploadContentSha256,
        hasLength(64),
      );
      expect(
        harness.store.partSnapshots(42).single.uploadContentBytes,
        128,
      );
      expect(
        () => harness.store.editPartContent(
          42,
          1,
          path: 'logical://different-audio.wav',
          startTime: DateTime.utc(2030),
        ),
        throwsStateError,
      );

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(2));
      expect(harness.api.remotePartCreations, 1);
      expect(
        harness.api.partCalls
            .map((_PartCall call) => call.idempotencyKey)
            .toSet(),
        <String>{'recording-part:part-upload-key-1'},
      );
      expect(harness.api.partCalls.last.part.path, firstAttempt.part.path);
      expect(
        harness.api.partCalls.last.part.startTime,
        firstAttempt.part.startTime,
      );
      expect(harness.store.partSnapshots(42).single.BEId, 101);
    });

    test('attempt-marker failure before commit sends no part and releases',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException dbFailure =
          _TestException('attempt marker was not committed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.markPartAttempted,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));

      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.uploadAttempted, isFalse);
      expect(persisted.sending, isFalse);
      expect(persisted.sent, isFalse);
    });

    test(
        'attempt-marker acknowledgement loss sends no part then retries its stable key',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final RecordingPart original = harness.store.partSnapshots(42).single;
      final _TestException dbFailure =
          _TestException('attempt marker acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.markPartAttempted,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));

      expect(harness.api.partCalls, isEmpty);
      final RecordingPart frozen = harness.store.partSnapshots(42).single;
      expect(frozen.uploadAttempted, isTrue);
      expect(frozen.uploadKey, original.uploadKey);
      expect(frozen.sending, isFalse);
      expect(
        () => harness.store.editPartContent(
          42,
          1,
          path: 'logical://mutated-after-ambiguous-marker.wav',
          startTime: DateTime.utc(2031),
        ),
        throwsStateError,
      );

      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.store.count(_StoreOperation.markPartAttempted), 1);
      expect(harness.api.partCalls, hasLength(1));
      expect(
        harness.api.partCalls.single.idempotencyKey,
        'recording-part:${original.uploadKey}',
      );
      expect(harness.api.remotePartCreations, 1);
      expect(harness.store.partSnapshots(42).single.BEId, 101);
    });

    test('does not rewrite a frozen part onto a different backend parent',
        () async {
      final RecordingPart part = _part(
        id: 1,
        backendRecordingId: 901,
      )..uploadAttempted = true;
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[part],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 900')),
      );

      expect(harness.api.calls, isEmpty);
      expect(
        harness.store.partSnapshots(42).single.backendRecordingId,
        901,
      );
    });
  });

  group('part reconciliation', () {
    test('wrong-parent backend link fails without part mutation or API work',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: 999,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 900')),
      );

      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, 101);
      expect(persisted.backendRecordingId, 999);
      expect(persisted.sent, isFalse);
      expect(persisted.sending, isFalse);
      expect(harness.store.count(_StoreOperation.acquirePart), 0);
      expect(harness.store.count(_StoreOperation.savePart), 0);
      expect(harness.api.calls, isEmpty);
      expect(harness.files.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('backend 200 marks an ambiguous local part sent without a file',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: 900,
            path: null,
          ),
        ],
      );
      harness.api.scriptExists(1, _ApiStep<bool>.returning(true));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.existsCalls, hasLength(1));
      expect(harness.api.partCalls, isEmpty);
      expect(harness.files.calls, isEmpty);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.store.partSnapshots(42).single.BEId, 101);
    });

    test('backend 404 clears the stale id and uploads the local file',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );
      harness.api.scriptExists(1, _ApiStep<bool>.returning(false));
      harness.api.scriptPart(1, _ApiStep<int>.returning(202));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.existsCalls, hasLength(1));
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.partCalls.single.part.BEId, isNull);
      expect(harness.store.partSnapshots(42).single.BEId, 202);
    });

    test('legacy id without a parent is bound before successful reconciliation',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: null,
            path: null,
          ),
        ],
      );
      harness.api.scriptExists(1, _ApiStep<bool>.returning(true));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.existsCalls.single.part.backendRecordingId, 900);
      expect(harness.api.partCalls, isEmpty);
      expect(harness.api.remotePartCreations, 0);
      expect(harness.files.calls, isEmpty);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, 101);
      expect(persisted.backendRecordingId, 900);
      expect(persisted.sent, isTrue);
      expect(
        harness.trace.indexOf('store.savePart#1'),
        lessThan(harness.trace.indexOf('api.exists:1')),
      );
    });

    test('legacy missing parent is bound before absent reconciliation and POST',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: null,
          ),
        ],
      );
      harness.api.scriptExists(1, _ApiStep<bool>.returning(false));
      harness.api.scriptPart(1, _ApiStep<int>.returning(202));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(harness.api.existsCalls.single.part.backendRecordingId, 900);
      expect(harness.api.partCalls.single.part.BEId, isNull);
      expect(harness.api.partCalls.single.part.backendRecordingId, 900);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, 202);
      expect(persisted.backendRecordingId, 900);
      expect(
        harness.trace.indexOf('store.savePart#1'),
        lessThan(harness.trace.indexOf('api.exists:1')),
      );
    });

    test('reconciliation API error is preserved and the stale id remains',
        () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );
      final _TestException failure = _TestException('reconciliation failed');
      harness.api.scriptExists(1, _ApiStep<bool>.throwing(failure));

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.partCalls, isEmpty);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, 101);
      expect(persisted.backendRecordingId, 900);
      expect(persisted.sent, isFalse);
      expect(persisted.sending, isFalse);
      expect(harness.store.count(_StoreOperation.savePart), 1);
      expect(harness.files.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('backend 404 followed by a missing file remains unsent', () async {
      harness.seed(
        _recording(backendId: 900, partCount: 1),
        <RecordingPart>[
          _part(
            id: 1,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );
      harness.api.scriptExists(1, _ApiStep<bool>.returning(false));
      harness.files.results['logical://part-1.wav'] = false;

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('no readable local file')),
      );

      expect(harness.api.partCalls, isEmpty);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, isNull);
      expect(persisted.sent, isFalse);
      expect(persisted.sending, isFalse);
    });
  });

  group('local file validation', () {
    for (final String? path in <String?>[null, '']) {
      test('rejects local path ${path == null ? 'null' : 'empty'}', () async {
        harness.seed(
          _recording(backendId: 900, partCount: 1),
          <RecordingPart>[_part(id: 1, path: path)],
        );

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('no readable local file')),
        );

        expect(harness.api.partCalls, isEmpty);
        expect(harness.files.calls, isEmpty);
        expect(harness.store.partSnapshots(42).single.sending, isFalse);
      });
    }

    test('rejects a path that the fake probe reports missing', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.files.results['logical://part-1.wav'] = false;

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('no readable local file')),
      );

      expect(harness.api.partCalls, isEmpty);
      expect(harness.files.calls, <String>['logical://part-1.wav']);
    });

    for (final int missingPartId in <int>[1, 2, 3]) {
      test(
          'missing ${_ordinal(missingPartId)} file prevents a new parent '
          'and every part API call', () async {
        harness.seedBasic(partCount: 3);
        harness.files.results['logical://part-$missingPartId.wav'] = false;

        await expectLater(
          harness.service.send(42),
          throwsA(
            _validationContaining(
              'part $missingPartId has no readable local file',
            ),
          ),
        );

        expect(
          harness.files.calls,
          List<String>.generate(
            missingPartId,
            (int index) => 'logical://part-${index + 1}.wav',
          ),
        );
        expect(harness.api.calls, isEmpty);
        expect(harness.api.createCalls, isEmpty);
        expect(harness.api.partCalls, isEmpty);
        expect(harness.api.remoteParentCreations, 0);
        expect(harness.api.remotePartCreations, 0);

        final Recording persisted = harness.store.recordingSnapshot(42)!;
        expect(persisted.BEId, isNull);
        expect(persisted.parentUploadAttempted, isFalse);
        expect(persisted.sent, isFalse);
        expect(persisted.sending, isFalse);
        expect(persisted.uploadLease, isNull);
        expect(harness.store.hasRecordingLease(42), isFalse);
        for (final RecordingPart part in harness.store.partSnapshots(42)) {
          expect(part.BEId, isNull);
          expect(part.uploadAttempted, isFalse);
          expect(part.sent, isFalse);
          expect(part.sending, isFalse);
        }
      });
    }

    test('all required files are preflighted before the first API call',
        () async {
      harness.seedBasic(partCount: 3);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.api.scriptPart(3, _ApiStep<int>.returning(103));

      final RecordingUploadResult result = await harness.service.send(42);

      expect(result.status, RecordingUploadStatus.uploaded);
      expect(
        harness.files.calls,
        <String>[
          'logical://part-1.wav',
          'logical://part-2.wav',
          'logical://part-3.wav',
          'logical://part-1.wav',
          'logical://part-2.wav',
          'logical://part-3.wav',
        ],
      );
      final int firstApiCall = harness.trace.indexOf(
        'api.create:recording:recording-upload-key-42',
      );
      expect(firstApiCall, greaterThanOrEqualTo(0));
      for (final int partId in <int>[1, 2, 3]) {
        expect(
          harness.trace.indexOf('file.exists:logical://part-$partId.wav'),
          lessThan(firstApiCall),
        );
      }
    });

    test('file probe failure is propagated and flags are released', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException failure = _TestException('file probe failed');
      harness.files.errors['logical://part-1.wav'] = failure;

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.partSnapshots(42).single.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    for (final int invalidPartId in <int>[1, 2, 3]) {
      test('invalid ${_ordinal(invalidPartId)} WAV prevents every remote call',
          () async {
        harness.seedBasic(partCount: 3);
        harness.files.fingerprints['logical://part-$invalidPartId.wav'] =
            const RecordingUploadFileFingerprint(
          sha256: 'not-a-sha256',
          byteLength: 128,
        );

        await expectLater(
          harness.service.send(42),
          throwsA(_validationContaining('valid WAV')),
        );

        expect(harness.api.calls, isEmpty);
        expect(harness.api.remoteParentCreations, 0);
        expect(harness.api.remotePartCreations, 0);
        expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
        expect(
          harness.store.recordingSnapshot(42)!.parentUploadAttempted,
          isFalse,
        );
        expect(harness.store.hasRecordingLease(42), isFalse);
      });
    }

    test('zero-byte WAV fingerprint is rejected before parent creation',
        () async {
      harness.seedBasic(partCount: 1);
      harness.files.fingerprints['logical://part-1.wav'] =
          RecordingUploadFileFingerprint(
        sha256: List<String>.filled(64, 'a').join(),
        byteLength: 0,
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('valid WAV')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.count(_StoreOperation.freezePartContent), 0);
    });

    test('all fingerprints commit before a new parent request', () async {
      harness.seedBasic(partCount: 3);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.api.scriptPart(3, _ApiStep<int>.returning(103));

      await harness.service.send(42);

      final int createIndex = harness.trace.indexOf(
        'api.create:recording:recording-upload-key-42',
      );
      expect(createIndex, greaterThanOrEqualTo(0));
      for (final int invocation in <int>[1, 2, 3]) {
        expect(
          harness.trace.indexOf('store.freezePartContent#$invocation'),
          inInclusiveRange(0, createIndex - 1),
        );
      }
      for (final RecordingPart part in harness.store.partSnapshots(42)) {
        expect(part.uploadContentSha256, hasLength(64));
        expect(part.uploadContentBytes, 128);
      }
    });

    test('fingerprint persistence failure sends no parent or part', () async {
      harness.seedBasic(partCount: 3);
      final _TestException failure =
          _TestException('mock fingerprint DB write failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.freezePartContent,
          invocation: 2,
          error: failure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.api.calls, isEmpty);
      expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
      expect(
        harness.store.recordingSnapshot(42)!.parentUploadAttempted,
        isFalse,
      );
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(
        harness.store
            .partSnapshots(42)
            .map((RecordingPart part) => part.sending),
        everyElement(isFalse),
      );
    });

    test('acknowledgement loss after fingerprint commit retries safely',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException failure =
          _TestException('mock fingerprint acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.freezePartContent,
          invocation: 1,
          error: failure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      final RecordingPart frozen = harness.store.partSnapshots(42).single;
      expect(frozen.uploadContentSha256, hasLength(64));
      expect(frozen.uploadContentBytes, 128);
      expect(harness.api.calls, isEmpty);

      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.store.count(_StoreOperation.freezePartContent), 1);
      expect(harness.api.partCalls, hasLength(1));
    });

    test('file mutation between preflight and POST sends no part bytes',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.files.scriptedFingerprints['logical://part-1.wav'] =
          <RecordingUploadFileFingerprint?>[
        _testFingerprint('a'),
        _testFingerprint('b'),
      ];

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('changed after upload preflight')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.partSnapshots(42).single.uploadAttempted, isFalse);
      expect(
        harness.store.partSnapshots(42).single.uploadContentSha256,
        _testFingerprint('a').sha256,
      );
    });

    test('mutated bytes after ambiguous POST cannot reuse its stable key',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException timeout = _TestException('part response lost');
      harness.api.scriptPart(
        1,
        _ApiStep<int>.commitThenThrow(101, timeout),
      );

      await expectLater(harness.service.send(42), throwsA(same(timeout)));
      final RecordingPart frozen = harness.store.partSnapshots(42).single;
      expect(frozen.uploadAttempted, isTrue);
      expect(frozen.uploadContentSha256, hasLength(64));
      expect(harness.api.remotePartCreations, 1);

      harness.files.fingerprints['logical://part-1.wav'] =
          _testFingerprint('c');
      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('content changed')),
      );

      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.remotePartCreations, 1);
      expect(harness.store.partSnapshots(42).single.BEId, isNull);
    });

    test('partial persisted fingerprint fails closed before any API call',
        () async {
      final RecordingPart part = _part(id: 1)
        ..uploadContentSha256 = _testFingerprint('d').sha256;
      harness.seed(
        _recording(partCount: 1),
        <RecordingPart>[part],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('invalid frozen content fingerprint')),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.count(_StoreOperation.freezePartContent), 0);
    });

    test('preserves permanent unreadable-file API validation failure',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      const RecordingUploadValidationException failure =
          RecordingUploadValidationException(
        'Recording part 1 is no longer readable.',
      );
      harness.api.scriptPart(1, _ApiStep<int>.throwing(failure));

      await expectLater(harness.service.send(42), throwsA(same(failure)));

      expect(harness.files.calls, <String>[
        'logical://part-1.wav',
        'logical://part-1.wav',
      ]);
      expect(harness.api.partCalls, hasLength(1));
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.BEId, isNull);
      expect(persisted.sent, isFalse);
      expect(persisted.sending, isFalse);
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });
  });

  group('store failures around part and completion transitions', () {
    test('initial part-load failure releases the lease before any API call',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException dbFailure = _TestException('load parts failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.loadParts,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
    });

    test('completion refresh failure retains uploaded parts for a clean retry',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException dbFailure =
          _TestException('completion refresh failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.loadParts,
          invocation: 2,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    for (final _FaultTiming timing in _FaultTiming.values) {
      test(
          'part claim ${timing.name}-mutation failure releases all claimed state',
          () async {
        harness.seedBasic(partCount: 1, backendId: 900);
        final _TestException dbFailure =
            _TestException('part claim ${timing.name} failed');
        harness.store.addFault(
          timing == _FaultTiming.before
              ? _StoreFault.before(
                  _StoreOperation.acquirePart,
                  invocation: 1,
                  error: dbFailure,
                )
              : _StoreFault.after(
                  _StoreOperation.acquirePart,
                  invocation: 1,
                  error: dbFailure,
                ),
        );

        await expectLater(harness.service.send(42), throwsA(same(dbFailure)));

        expect(harness.api.partCalls, isEmpty);
        expect(harness.store.hasRecordingLease(42), isFalse);
        expect(harness.store.partSnapshots(42).single.sending, isFalse);
      });
    }

    test('part save failure before commit retries with the same remote key',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException dbFailure = _TestException('part save failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.savePart,
          invocation: 1,
          error: dbFailure,
        ),
      );
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.savePart,
          invocation: 2,
          error: _TestException('cleanup save also failed'),
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      expect(harness.store.partSnapshots(42).single.BEId, isNull);
      expect(harness.store.partSnapshots(42).single.sending, isFalse);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(2));
      expect(harness.api.remotePartCreations, 1);
      expect(
        harness.api.partCalls.first.idempotencyKey,
        harness.api.partCalls.last.idempotencyKey,
      );
    });

    test('part save failure after commit is reconciled locally on retry',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException dbFailure =
          _TestException('part save acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.savePart,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      expect(harness.store.partSnapshots(42).single.sent, isTrue);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.remotePartCreations, 1);
    });

    test('completion failure before commit retries without network calls',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException dbFailure = _TestException('complete failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.completeRecording,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      final Recording persisted = harness.store.recordingSnapshot(42)!;
      expect(harness.store.completionInputSent, <bool>[true]);
      expect(persisted.sent, isFalse);
      expect(persisted.sending, isFalse);
      expect(persisted.uploadLease, isNull);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.createCalls, isEmpty);
    });

    test('completion commit-then-failure is alreadySent on retry', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException dbFailure =
          _TestException('completion acknowledgement lost');
      harness.store.addFault(
        _StoreFault.after(
          _StoreOperation.completeRecording,
          invocation: 1,
          error: dbFailure,
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(dbFailure)));
      final Recording persisted = harness.store.recordingSnapshot(42)!;
      expect(harness.store.completionInputSent, <bool>[true]);
      expect(persisted.sent, isTrue);
      expect(persisted.sending, isFalse);
      expect(persisted.uploadLease, isNull);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.alreadySent);
      expect(harness.api.partCalls, hasLength(1));
    });

    test('part cleanup failure does not replace the API failure', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _TestException apiFailure = _TestException('part API failed');
      harness.api.scriptPart(1, _ApiStep<int>.throwing(apiFailure));
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.savePart,
          invocation: 1,
          error: _TestException('part cleanup failed'),
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(apiFailure)));

      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
    });

    test('recording cleanup failure does not replace the API failure',
        () async {
      harness.seedBasic(partCount: 1);
      final _TestException apiFailure = _TestException('parent API failed');
      harness.api.scriptCreate(_ApiStep<int>.throwing(apiFailure));
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.releaseRecording,
          invocation: 1,
          error: _TestException('recording cleanup failed'),
        ),
      );

      await expectLater(harness.service.send(42), throwsA(same(apiFailure)));
    });
  });

  group('session lease safety', () {
    test('session-provider current check failure fails closed before API',
        () async {
      harness.seedBasic(partCount: 1);
      final _TestException providerFailure =
          _TestException('session provider unavailable');
      harness.sessions.currentErrors[1] = providerFailure;

      await expectLater(
        harness.service.send(42),
        throwsA(same(providerFailure)),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      expect(harness.store.partSnapshots(42).single.sending, isFalse);
    });

    test('session change before parent creation sends no API request',
        () async {
      harness.seedBasic(partCount: 1);
      harness.sessions.notCurrentAt.add(1);

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test(
        'session callback failure immediately before the first parent POST '
        'sends no request and releases a retryable parent', () async {
      harness.seedBasic(partCount: 1);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      final _TestException providerFailure =
          _TestException('session unavailable at parent byte boundary');
      // #1 validates the captured session and #2 follows the durable request
      // freeze. #3 is the API's callback immediately before its first POST.
      harness.sessions.currentErrors[3] = providerFailure;

      await expectLater(
        harness.service.send(42),
        throwsA(same(providerFailure)),
      );

      expect(harness.api.createCalls, isEmpty);
      expect(harness.api.remoteParentCreations, 0);
      final Recording retryable = harness.store.recordingSnapshot(42)!;
      expect(retryable.parentUploadAttempted, isTrue);
      expect(retryable.BEId, isNull);
      expect(retryable.sent, isFalse);
      expect(retryable.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
    });

    test(
        'session change after a parent 307 prevents replay and releases a '
        'retryable parent', () async {
      harness.seedBasic(partCount: 1);
      final _AsyncGate redirectGate = _AsyncGate();
      harness.api.scriptCreate(
        _ApiStep<int>.returning(
          900,
          createPostLegs: 2,
          betweenCreatePostLegsGate: redirectGate,
        ),
      );

      final Future<RecordingUploadResult> upload = harness.service.send(42);
      await redirectGate.entered.future;

      // The first mocked request returned 307. Model logout/account/env
      // replacement before the helper attempts its replay.
      expect(harness.api.createCalls, hasLength(1));
      harness.sessions.notCurrentAt.add(harness.sessions.currentCalls + 1);
      redirectGate.release();

      await expectLater(
        upload,
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.api.createCalls, hasLength(1));
      expect(harness.api.remoteParentCreations, 0);
      final Recording retryable = harness.store.recordingSnapshot(42)!;
      expect(retryable.parentUploadAttempted, isTrue);
      expect(retryable.BEId, isNull);
      expect(retryable.sent, isFalse);
      expect(retryable.sending, isFalse);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);

      harness.sessions.notCurrentAt.clear();
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(2));
      expect(harness.api.remoteParentCreations, 1);
      expect(harness.store.recordingSnapshot(42)!.sent, isTrue);
    });

    test('frozen parent retry rechecks its session after file preflight',
        () async {
      harness.seed(
        _recording(partCount: 1)..parentUploadAttempted = true,
        <RecordingPart>[_part(id: 1)],
      );
      harness.sessions.notCurrentAt.add(2);

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.files.calls, <String>['logical://part-1.wav']);
      expect(harness.api.calls, isEmpty);
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test(
        'session change after parent creation persists parent but sends no part',
        () async {
      harness.seedBasic(partCount: 1);
      harness.api.scriptCreate(_ApiStep<int>.returning(900));
      harness.sessions.notCurrentAt.add(4);

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.store.recordingSnapshot(42)!.BEId, 900);
      expect(harness.api.partCalls, isEmpty);
      expect(harness.store.partSnapshots(42).single.sending, isFalse);
    });

    test('session change after file probe prevents the part POST', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.sessions.notCurrentAt.add(3);

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.files.calls, <String>[
        'logical://part-1.wav',
        'logical://part-1.wav',
      ]);
      expect(harness.api.partCalls, isEmpty);
    });

    test(
        'session change while attempt marker commits sends zero part bytes and '
        'leaves a retryable marker', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _AsyncGate markerGate = _AsyncGate();
      harness.store.gateAfterMutation(
        _StoreOperation.markPartAttempted,
        invocation: 1,
        gate: markerGate,
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final Future<RecordingUploadResult> upload = harness.service.send(42);
      await markerGate.entered.future;

      // Model a logout/account/environment switch after the marker has
      // committed but before its Future acknowledges completion.
      expect(harness.store.partSnapshots(42).single.uploadAttempted, isTrue);
      harness.sessions.notCurrentAt.add(harness.sessions.currentCalls + 1);
      markerGate.release();

      await expectLater(
        upload,
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.api.partCalls, isEmpty);
      expect(harness.api.remotePartCreations, 0);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      final RecordingPart failedPart = harness.store.partSnapshots(42).single;
      expect(failedPart.uploadAttempted, isTrue);
      expect(failedPart.sent, isFalse);
      expect(failedPart.sending, isFalse);

      harness.sessions.notCurrentAt.clear();
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.remotePartCreations, 1);
      expect(harness.store.count(_StoreOperation.markPartAttempted), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
    });

    test(
        'session check failure while attempt marker commits sends zero part '
        'bytes and leaves a retryable marker', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _AsyncGate markerGate = _AsyncGate();
      harness.store.gateAfterMutation(
        _StoreOperation.markPartAttempted,
        invocation: 1,
        gate: markerGate,
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final _TestException providerFailure =
          _TestException('session check unavailable after marker commit');

      final Future<RecordingUploadResult> upload = harness.service.send(42);
      await markerGate.entered.future;

      // A session-provider error is also fail-closed at the byte boundary.
      expect(harness.store.partSnapshots(42).single.uploadAttempted, isTrue);
      harness.sessions.currentErrors[harness.sessions.currentCalls + 1] =
          providerFailure;
      markerGate.release();

      await expectLater(upload, throwsA(same(providerFailure)));

      expect(harness.api.partCalls, isEmpty);
      expect(harness.api.remotePartCreations, 0);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
      final RecordingPart failedPart = harness.store.partSnapshots(42).single;
      expect(failedPart.uploadAttempted, isTrue);
      expect(failedPart.sent, isFalse);
      expect(failedPart.sending, isFalse);

      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(harness.api.remotePartCreations, 1);
      expect(harness.store.count(_StoreOperation.markPartAttempted), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.partSnapshots(42).single.sent, isTrue);
    });

    test('session change during API staging sends zero part bytes and releases',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      final _AsyncGate stagingGate = _AsyncGate();
      harness.api.scriptPart(
        1,
        _ApiStep<int>.returning(101, gate: stagingGate),
      );

      final Future<RecordingUploadResult> upload = harness.service.send(42);
      await stagingGate.entered.future;
      harness.sessions.notCurrentAt.add(harness.sessions.currentCalls + 1);
      stagingGate.release();

      await expectLater(
        upload,
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );
      expect(harness.api.partCalls, isEmpty);
      expect(harness.api.remotePartCreations, 0);
      expect(harness.store.count(_StoreOperation.releaseRecording), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.partSnapshots(42).single.sent, isFalse);
      expect(harness.store.partSnapshots(42).single.sending, isFalse);
    });

    test('session change before completion leaves durable parts for retry',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      // The immutable upload adapter performs one additional revalidation
      // immediately before opening the HTTP request stream.
      harness.sessions.notCurrentAt.add(6);

      await expectLater(
        harness.service.send(42),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(harness.store.partSnapshots(42).single.sent, isTrue);
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);

      harness.sessions.notCurrentAt.clear();
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
    });
  });

  group('concurrency', () {
    test('takes over a stale upload lease and clears its orphan part claim',
        () async {
      harness = _UploadHarness(
        storeLeaseTimeout: const Duration(minutes: 5),
      );
      harness.seedBasic(partCount: 1, backendId: 900);
      expect(
        await harness.store.tryAcquireRecording(42, 'stale-upload'),
        isTrue,
      );
      expect(
        await harness.store.tryAcquireRecordingPart(42, 1, 'stale-upload'),
        isTrue,
      );
      await harness.store.markRecordingPartAttempted(
        42,
        1,
        'stale-upload',
      );
      harness.store.ageRecordingLease(
        42,
        const Duration(minutes: 6),
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final RecordingUploadResult recovered = await harness.service.send(42);

      expect(recovered.status, RecordingUploadStatus.uploaded);
      expect(harness.api.partCalls, hasLength(1));
      expect(
        harness.api.partCalls.single.idempotencyKey,
        'recording-part:part-upload-key-1',
      );
      expect(harness.store.count(_StoreOperation.acquireRecording), 2);
      expect(harness.store.count(_StoreOperation.acquirePart), 2);
      expect(harness.store.count(_StoreOperation.markPartAttempted), 1);
      expect(harness.store.hasRecordingLease(42), isFalse);
      final RecordingPart persisted = harness.store.partSnapshots(42).single;
      expect(persisted.uploadAttempted, isTrue);
      expect(persisted.sent, isTrue);
      expect(persisted.sending, isFalse);
    });

    test('a second worker is busy while the first holds the durable lease',
        () async {
      harness.seedBasic(partCount: 1);
      final _AsyncGate gate = _AsyncGate();
      harness.api.scriptCreate(
        _ApiStep<int>.returning(900, gate: gate),
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final Future<RecordingUploadResult> first = harness.service.send(42);
      await gate.entered.future;

      final RecordingUploadResult second = await harness.service.send(42);
      expect(second.status, RecordingUploadStatus.busy);
      expect(harness.api.createCalls, hasLength(1));

      gate.release();
      final RecordingUploadResult firstResult = await first;
      expect(firstResult.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(1));
      expect(harness.store.hasRecordingLease(42), isFalse);
    });

    test('a long API request renews the lease before its timeout', () async {
      harness = _UploadHarness(
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
        storeLeaseTimeout: const Duration(milliseconds: 12),
      );
      harness.seedBasic(partCount: 1);
      final _AsyncGate gate = _AsyncGate();
      harness.api.scriptCreate(
        _ApiStep<int>.returning(900, gate: gate),
      );
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));

      final Future<RecordingUploadResult> first = harness.service.send(42);
      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final RecordingUploadResult second = await harness.service.send(42);

      expect(second.status, RecordingUploadStatus.busy);
      expect(
        harness.store.count(_StoreOperation.renewRecording),
        greaterThan(0),
      );
      expect(harness.api.createCalls, hasLength(1));

      gate.release();
      final RecordingUploadResult firstResult = await first;
      expect(firstResult.status, RecordingUploadStatus.uploaded);
    });

    test(
        'lease renewal failure after remote success is recovered by stable replay',
        () async {
      harness = _UploadHarness(
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
      );
      harness.seedBasic(partCount: 1);
      final _AsyncGate gate = _AsyncGate();
      final _TestException leaseFailure =
          _TestException('lease heartbeat failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.renewRecording,
          invocation: 1,
          error: leaseFailure,
        ),
      );
      harness.api.scriptCreate(
        _ApiStep<int>.returning(900, gate: gate),
      );

      final Future<RecordingUploadResult> first = harness.service.send(42);
      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      gate.release();

      await expectLater(first, throwsA(same(leaseFailure)));
      expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
      expect(harness.api.remoteParentCreations, 1);

      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      final RecordingUploadResult retry = await harness.service.send(42);

      expect(retry.status, RecordingUploadStatus.uploaded);
      expect(harness.api.createCalls, hasLength(2));
      expect(
        harness.api.createCalls.first.idempotencyKey,
        harness.api.createCalls.last.idempotencyKey,
      );
      expect(harness.api.remoteParentCreations, 1);
    });

    test('API failure remains primary when lease renewal also fails', () async {
      harness = _UploadHarness(
        leaseHeartbeatInterval: const Duration(milliseconds: 2),
      );
      harness.seedBasic(partCount: 1);
      final _AsyncGate gate = _AsyncGate();
      final _TestException apiFailure = _TestException('API failed');
      harness.store.addFault(
        _StoreFault.before(
          _StoreOperation.renewRecording,
          invocation: 1,
          error: _TestException('lease heartbeat failed'),
        ),
      );
      harness.api.scriptCreate(
        _ApiStep<int>.throwing(apiFailure, gate: gate),
      );

      final Future<RecordingUploadResult> upload = harness.service.send(42);
      await gate.entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      gate.release();

      await expectLater(upload, throwsA(same(apiFailure)));
      expect(harness.store.hasRecordingLease(42), isFalse);
      expect(harness.store.recordingSnapshot(42)!.BEId, isNull);
    });
  });

  group('completion refresh invariants', () {
    test('a disappeared row cannot shrink a fallback expected count', () async {
      harness.seedBasic(partCount: 0, backendId: 900, numberOfParts: 2);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.store.scriptPartLoad(
        2,
        () => <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 2 parts but found 1')),
      );

      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
    });

    test('an added row prevents completion', () async {
      harness.seedBasic(partCount: 2, backendId: 900, numberOfParts: 2);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(102));
      harness.store.scriptPartLoad(
        2,
        () => <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 900,
          ),
          _part(
            id: 2,
            sent: true,
            backendId: 102,
            backendRecordingId: 900,
          ),
          _part(
            id: 3,
            sent: true,
            backendId: 103,
            backendRecordingId: 900,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 2 parts but found 3')),
      );

      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
    });

    test('a silently unsent persisted part prevents completion', () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.store.scriptPartLoad(
        2,
        () => <RecordingPart>[
          _part(
            id: 1,
            sent: false,
            backendId: null,
            backendRecordingId: 900,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('still unsent')),
      );

      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
    });

    test('a persisted part linked to another parent prevents completion',
        () async {
      harness.seedBasic(partCount: 1, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.store.scriptPartLoad(
        2,
        () => <RecordingPart>[
          _part(
            id: 1,
            sent: true,
            backendId: 101,
            backendRecordingId: 999,
          ),
        ],
      );

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('expected 900')),
      );

      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
    });

    test('duplicate backend part ids cannot complete the aggregate', () async {
      harness.seedBasic(partCount: 2, backendId: 900);
      harness.api.scriptPart(1, _ApiStep<int>.returning(101));
      harness.api.scriptPart(2, _ApiStep<int>.returning(101));

      await expectLater(
        harness.service.send(42),
        throwsA(_validationContaining('duplicate backend ids')),
      );

      expect(harness.api.partCalls, hasLength(2));
      expect(
        harness.store.partSnapshots(42).map((RecordingPart part) => part.BEId),
        <int?>[101, 101],
      );
      expect(harness.store.recordingSnapshot(42)!.sent, isFalse);
      expect(harness.store.completedExpectedCounts, isEmpty);
    });
  });
}

Matcher _validationContaining(String text) {
  return isA<RecordingUploadValidationException>().having(
    (RecordingUploadValidationException error) => error.message,
    'message',
    contains(text),
  );
}

String _uploadKeyDescription(String? uploadKey) {
  if (uploadKey == null) return 'missing';
  if (uploadKey.isEmpty) return 'empty';
  return 'whitespace-only';
}

void _expectRejectedSessionBinding(_UploadHarness harness) {
  expect(harness.api.calls, isEmpty);
  expect(harness.store.hasRecordingLease(42), isFalse);
  expect(harness.store.recordingSnapshot(42)!.sending, isFalse);
  expect(harness.store.count(_StoreOperation.releaseRecording), 1);
}

String _ordinal(int value) {
  switch (value) {
    case 1:
      return 'first';
    case 2:
      return 'middle';
    case 3:
      return 'last';
    default:
      return '$value';
  }
}

const RecordingUploadSession _defaultSession = RecordingUploadSession(
  userId: '7',
  accessToken: 'test-token',
  logicalSessionId: 'default-logical-session',
  environment: 'prod',
  accountEmail: 'bird@example.test',
  deviceId: 'device-token-A',
  backendHost: 'api.production.example.test',
);

Recording _recording({
  int? id = 42,
  int? userId = 7,
  int? backendId,
  String? mail = 'bird@example.test',
  bool sent = false,
  bool sending = false,
  int? partCount = 1,
  String environment = 'prod',
  String? uploadKey = 'recording-upload-key-42',
  bool captureReviewed = true,
}) {
  return Recording(
    id: id,
    userId: userId,
    BEId: backendId,
    mail: mail,
    createdAt: DateTime.utc(2026, 7, 18, 8),
    estimatedBirdsCount: 3,
    device: 'test-device',
    byApp: true,
    note: 'test note',
    name: 'test recording',
    path: 'logical://whole-recording.wav',
    downloaded: true,
    sent: sent,
    sending: sending,
    uploadKey: uploadKey,
    captureReviewed: captureReviewed,
    partCount: partCount,
    env: environment,
    totalSeconds: 12,
  );
}

RecordingPart _part({
  int? id = 1,
  int? recordingId = 42,
  int? backendId,
  int? backendRecordingId,
  bool sent = false,
  bool sending = false,
  String? path = 'logical://part-1.wav',
  String? uploadKey,
  bool omitUploadKey = false,
}) {
  final int sequence = id ?? 0;
  return RecordingPart(
    id: id,
    BEId: backendId,
    recordingId: recordingId,
    backendRecordingId: backendRecordingId,
    startTime: DateTime.utc(2026, 7, 18, 8, 0, sequence),
    endTime: DateTime.utc(2026, 7, 18, 8, 0, sequence + 1),
    gpsLatitudeStart: 50.08 + sequence / 1000,
    gpsLatitudeEnd: 50.081 + sequence / 1000,
    gpsLongitudeStart: 14.42 + sequence / 1000,
    gpsLongitudeEnd: 14.421 + sequence / 1000,
    path: path == 'logical://part-1.wav' && id != null
        ? 'logical://part-$id.wav'
        : path,
    length: 1,
    sent: sent,
    sending: sending,
    uploadKey: omitUploadKey ? null : uploadKey ?? 'part-upload-key-$id',
  );
}

Recording _copyRecording(Recording source) {
  return Recording(
    id: source.id,
    userId: source.userId,
    BEId: source.BEId,
    mail: source.mail,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      source.createdAt.millisecondsSinceEpoch,
      isUtc: source.createdAt.isUtc,
    ),
    estimatedBirdsCount: source.estimatedBirdsCount,
    device: source.device,
    byApp: source.byApp,
    note: source.note,
    name: source.name,
    path: source.path,
    downloaded: source.downloaded,
    sent: source.sent,
    sending: source.sending,
    uploadKey: source.uploadKey,
    uploadLease: source.uploadLease,
    uploadLeaseUpdatedAt: source.uploadLeaseUpdatedAt,
    parentUploadAttempted: source.parentUploadAttempted,
    uploadDeviceId: source.uploadDeviceId,
    captureReviewed: source.captureReviewed,
    partCount: source.partCount,
    env: source.env,
    totalSeconds: source.totalSeconds,
  );
}

RecordingPart _copyPart(RecordingPart source) {
  return RecordingPart(
    id: source.id,
    BEId: source.BEId,
    recordingId: source.recordingId,
    backendRecordingId: source.backendRecordingId,
    startTime: DateTime.fromMillisecondsSinceEpoch(
      source.startTime.millisecondsSinceEpoch,
      isUtc: source.startTime.isUtc,
    ),
    endTime: DateTime.fromMillisecondsSinceEpoch(
      source.endTime.millisecondsSinceEpoch,
      isUtc: source.endTime.isUtc,
    ),
    gpsLatitudeStart: source.gpsLatitudeStart,
    gpsLatitudeEnd: source.gpsLatitudeEnd,
    gpsLongitudeStart: source.gpsLongitudeStart,
    gpsLongitudeEnd: source.gpsLongitudeEnd,
    square: source.square,
    path: source.path,
    length: source.length,
    dataBase64Temp: source.dataBase64Temp,
    sent: source.sent,
    sending: source.sending,
    uploadAttempted: source.uploadAttempted,
    uploadKey: source.uploadKey,
    uploadContentSha256: source.uploadContentSha256,
    uploadContentBytes: source.uploadContentBytes,
  );
}

class _UploadHarness {
  _UploadHarness({
    String Function()? newLeaseId,
    Duration leaseHeartbeatInterval = const Duration(minutes: 1),
    Duration? storeLeaseTimeout,
  }) {
    store = _FakeUploadStore(
      trace,
      leaseTimeout: storeLeaseTimeout,
    );
    api = _FakeUploadApi(trace);
    sessions = _FakeSessionProvider(trace);
    policy = _FakePolicy(trace);
    files = _FakeFileProbe(trace);
    service = RecordingUploadService(
      store: store,
      api: api,
      sessions: sessions,
      policy: policy,
      files: files,
      newLeaseId: newLeaseId ?? () => 'lease-${++_leaseCounter}',
      leaseHeartbeatInterval: leaseHeartbeatInterval,
    );
  }

  final List<String> trace = <String>[];
  late final _FakeUploadStore store;
  late final _FakeUploadApi api;
  late final _FakeSessionProvider sessions;
  late final _FakePolicy policy;
  late final _FakeFileProbe files;
  late final RecordingUploadService service;
  int _leaseCounter = 0;

  void seed(
    Recording recording,
    List<RecordingPart> parts, {
    int? storageId,
  }) {
    store.seed(recording, parts, storageId: storageId);
    for (final RecordingPart part in parts) {
      final String? path = part.path;
      if (path != null && path.isNotEmpty) {
        files.results.putIfAbsent(path, () => true);
      }
    }
  }

  void seedBasic({
    required int partCount,
    int? backendId,
    int? numberOfParts,
  }) {
    final int actualCount = numberOfParts ?? (partCount > 0 ? partCount : 1);
    seed(
      _recording(backendId: backendId, partCount: partCount),
      List<RecordingPart>.generate(
        actualCount,
        (int index) => _part(id: index + 1),
      ),
    );
  }

  void releaseAllGates() {
    api.releaseAllGates();
    store.releaseAllGates();
  }
}

enum _StoreOperation {
  acquireRecording,
  renewRecording,
  loadRecording,
  loadParts,
  saveRecording,
  acquirePart,
  markPartAttempted,
  freezePartContent,
  savePart,
  completeRecording,
  releaseRecording,
}

enum _FaultTiming { before, after }

class _StoreFault {
  _StoreFault.before(
    this.operation, {
    required this.invocation,
    this.error,
  }) : timing = _FaultTiming.before;

  _StoreFault.after(
    this.operation, {
    required this.invocation,
    this.error,
  }) : timing = _FaultTiming.after;

  final _StoreOperation operation;
  final int invocation;
  final Object? error;
  final _FaultTiming timing;
  bool used = false;
}

class _FakeUploadStore implements RecordingUploadStore {
  _FakeUploadStore(
    this.trace, {
    this.leaseTimeout,
  });

  final List<String> trace;
  final Duration? leaseTimeout;
  final List<String> calls = <String>[];
  final Map<int, Recording> _recordings = <int, Recording>{};
  final Map<int, List<RecordingPart>> _parts = <int, List<RecordingPart>>{};
  final Map<int, String> _recordingLeases = <int, String>{};
  final Map<int, DateTime> _recordingLeaseUpdatedAt = <int, DateTime>{};
  final Map<String, String> _partLeases = <String, String>{};
  final Map<_StoreOperation, int> _counts = <_StoreOperation, int>{};
  final List<_StoreFault> _faults = <_StoreFault>[];
  final Map<int, List<RecordingPart> Function()> _scriptedPartLoads =
      <int, List<RecordingPart> Function()>{};
  final Map<String, _AsyncGate> _afterMutationGates = <String, _AsyncGate>{};
  final Set<int> forceBusyPartIds = <int>{};
  final List<int> completedExpectedCounts = <int>[];
  final List<bool> completionInputSent = <bool>[];

  bool forceBusy = false;

  void seed(
    Recording recording,
    List<RecordingPart> parts, {
    int? storageId,
  }) {
    final int key = storageId ?? recording.id ?? 42;
    _recordings[key] = _copyRecording(recording);
    _parts[key] = parts.map(_copyPart).toList(growable: true);
  }

  void addFault(_StoreFault fault) {
    _faults.add(fault);
  }

  void gateAfterMutation(
    _StoreOperation operation, {
    required int invocation,
    required _AsyncGate gate,
  }) {
    _afterMutationGates[_operationInvocationKey(operation, invocation)] = gate;
  }

  void scriptPartLoad(
    int invocation,
    List<RecordingPart> Function() rows,
  ) {
    _scriptedPartLoads[invocation] = rows;
  }

  int count(_StoreOperation operation) => _counts[operation] ?? 0;

  bool hasRecordingLease(int recordingId) =>
      _recordingLeases.containsKey(recordingId);

  Recording? recordingSnapshot(int recordingId) {
    final Recording? recording = _recordings[recordingId];
    return recording == null ? null : _copyRecording(recording);
  }

  List<RecordingPart> partSnapshots(int recordingId) {
    return (_parts[recordingId] ?? const <RecordingPart>[])
        .map(_copyPart)
        .toList(growable: false);
  }

  void editPartContent(
    int recordingId,
    int partId, {
    required String path,
    required DateTime startTime,
  }) {
    final RecordingPart? part = _findPart(recordingId, partId);
    if (part == null) {
      throw StateError('Part $partId is missing.');
    }
    if (part.uploadAttempted && part.BEId == null) {
      throw StateError('Part $partId has an ambiguous remote attempt.');
    }
    part
      ..path = path
      ..startTime = startTime;
  }

  void ageRecordingLease(int recordingId, Duration age) {
    final String? lease = _recordingLeases[recordingId];
    if (lease == null) {
      throw StateError('Recording $recordingId has no lease to age.');
    }
    final DateTime agedAt = DateTime.now().subtract(age);
    _recordingLeaseUpdatedAt[recordingId] = agedAt;
    _recordings[recordingId]?.uploadLeaseUpdatedAt =
        agedAt.millisecondsSinceEpoch;
  }

  @override
  Future<bool> tryAcquireRecording(int recordingId, String leaseId) {
    return _run<bool>(_StoreOperation.acquireRecording, () {
      final String? currentLease = _recordingLeases[recordingId];
      final DateTime? updatedAt = _recordingLeaseUpdatedAt[recordingId];
      final bool expired = currentLease != null &&
          leaseTimeout != null &&
          updatedAt != null &&
          DateTime.now().difference(updatedAt) >= leaseTimeout!;
      if (forceBusy || (currentLease != null && !expired)) {
        return false;
      }
      _partLeases.removeWhere(
        (String key, String _) => key.startsWith('$recordingId:'),
      );
      for (final RecordingPart part
          in _parts[recordingId] ?? const <RecordingPart>[]) {
        part.sending = false;
      }
      _recordingLeases[recordingId] = leaseId;
      final DateTime now = DateTime.now();
      _recordingLeaseUpdatedAt[recordingId] = now;
      final Recording? recording = _recordings[recordingId];
      if (recording != null) {
        recording
          ..sending = true
          ..uploadLease = leaseId
          ..uploadLeaseUpdatedAt = now.millisecondsSinceEpoch;
      }
      return true;
    });
  }

  @override
  Future<void> renewRecording(int recordingId, String leaseId) {
    return _run<void>(_StoreOperation.renewRecording, () {
      _requireLease(recordingId, leaseId);
      final DateTime now = DateTime.now();
      _recordingLeaseUpdatedAt[recordingId] = now;
      _recordings[recordingId]?.uploadLeaseUpdatedAt =
          now.millisecondsSinceEpoch;
    });
  }

  @override
  Future<Recording?> loadRecording(int recordingId, String leaseId) {
    return _run<Recording?>(_StoreOperation.loadRecording, () {
      _requireLease(recordingId, leaseId);
      final Recording? recording = _recordings[recordingId];
      return recording == null ? null : _copyRecording(recording);
    });
  }

  @override
  Future<List<RecordingPart>> loadRecordingParts(
    int recordingId,
    String leaseId,
  ) {
    return _run<List<RecordingPart>>(_StoreOperation.loadParts, () {
      _requireLease(recordingId, leaseId);
      final int invocation = count(_StoreOperation.loadParts);
      final List<RecordingPart> rows = _scriptedPartLoads[invocation]?.call() ??
          (_parts[recordingId] ?? const <RecordingPart>[]);
      return rows.map(_copyPart).toList(growable: false);
    });
  }

  @override
  Future<void> saveRecording(Recording recording, String leaseId) {
    return _run<void>(_StoreOperation.saveRecording, () {
      final int recordingId =
          recording.id ?? (throw StateError('Recording id is null.'));
      _requireLease(recordingId, leaseId);
      _recordings[recordingId] = _copyRecording(recording);
    });
  }

  @override
  Future<bool> tryAcquireRecordingPart(
    int recordingId,
    int partId,
    String leaseId,
  ) {
    return _run<bool>(_StoreOperation.acquirePart, () {
      _requireLease(recordingId, leaseId);
      final String key = _partKey(recordingId, partId);
      final RecordingPart? part = _findPart(recordingId, partId);
      if (part == null ||
          forceBusyPartIds.contains(partId) ||
          part.sent ||
          part.sending ||
          _partLeases.containsKey(key)) {
        return false;
      }
      _partLeases[key] = leaseId;
      part.sending = true;
      return true;
    });
  }

  @override
  Future<void> markRecordingPartAttempted(
    int recordingId,
    int partId,
    String leaseId,
  ) {
    return _run<void>(_StoreOperation.markPartAttempted, () {
      _requireLease(recordingId, leaseId);
      final String key = _partKey(recordingId, partId);
      final RecordingPart? part = _findPart(recordingId, partId);
      if (part == null || _partLeases[key] != leaseId || !part.sending) {
        throw StateError('Part $partId is not owned by lease $leaseId.');
      }
      part.uploadAttempted = true;
    });
  }

  @override
  Future<void> freezeRecordingPartContent(
    int recordingId,
    int partId,
    RecordingUploadFileFingerprint fingerprint,
    String leaseId,
  ) {
    return _run<void>(_StoreOperation.freezePartContent, () {
      _requireLease(recordingId, leaseId);
      final RecordingPart? part = _findPart(recordingId, partId);
      if (part == null || part.sent) {
        throw StateError('Part $partId cannot freeze upload content.');
      }
      final String? existingHash = part.uploadContentSha256;
      final int? existingBytes = part.uploadContentBytes;
      if ((existingHash != null &&
              existingHash.toLowerCase() != fingerprint.sha256.toLowerCase()) ||
          (existingBytes != null && existingBytes != fingerprint.byteLength)) {
        throw StateError('Part $partId content was already frozen.');
      }
      part
        ..uploadContentSha256 = fingerprint.sha256.toLowerCase()
        ..uploadContentBytes = fingerprint.byteLength;
    });
  }

  @override
  Future<void> saveRecordingPart(
    int recordingId,
    RecordingPart part,
    String leaseId,
  ) {
    return _run<void>(_StoreOperation.savePart, () {
      _requireLease(recordingId, leaseId);
      final int partId =
          part.id ?? (throw StateError('Recording part id is null.'));
      final String key = _partKey(recordingId, partId);
      if (_partLeases[key] != leaseId) {
        throw StateError('Part $partId is not owned by lease $leaseId.');
      }
      final List<RecordingPart> parts =
          _parts[recordingId] ?? (throw StateError('Parts missing.'));
      final int index =
          parts.indexWhere((RecordingPart item) => item.id == partId);
      if (index < 0) {
        throw StateError('Part $partId is missing.');
      }
      parts[index] = _copyPart(part);
      if (part.sent || !part.sending) {
        _partLeases.remove(key);
      }
    });
  }

  @override
  Future<void> completeRecording(
    Recording recording,
    String leaseId, {
    required int expectedPartsCount,
  }) {
    completionInputSent.add(recording.sent);
    return _run<void>(_StoreOperation.completeRecording, () {
      final int recordingId =
          recording.id ?? (throw StateError('Recording id is null.'));
      _requireLease(recordingId, leaseId);
      final List<RecordingPart> parts =
          _parts[recordingId] ?? const <RecordingPart>[];
      if (parts.length != expectedPartsCount ||
          parts.any((RecordingPart part) => !part.sent)) {
        throw StateError('Fake store refused incomplete completion.');
      }
      completedExpectedCounts.add(expectedPartsCount);
      _recordings[recordingId] = _copyRecording(recording);
      _releaseLeaseState(recordingId, leaseId);
    });
  }

  @override
  Future<void> releaseRecording(int recordingId, String leaseId) {
    return _run<void>(_StoreOperation.releaseRecording, () {
      final String? owner = _recordingLeases[recordingId];
      if (owner != leaseId) {
        throw StateError(
          'Lease $leaseId cannot release recording owned by $owner.',
        );
      }
      final Recording? persisted = _recordings[recordingId];
      if (persisted != null) {
        persisted
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
      }
      for (final RecordingPart part
          in _parts[recordingId] ?? const <RecordingPart>[]) {
        part.sending = false;
      }
      _releaseLeaseState(recordingId, leaseId);
    });
  }

  Future<T> _run<T>(_StoreOperation operation, T Function() mutation) async {
    final int invocation = (_counts[operation] ?? 0) + 1;
    _counts[operation] = invocation;
    final String label = 'store.${operation.name}#$invocation';
    calls.add(label);
    trace.add(label);

    _StoreFault? fault;
    for (final _StoreFault candidate in _faults) {
      if (!candidate.used &&
          candidate.operation == operation &&
          candidate.invocation == invocation) {
        fault = candidate;
        candidate.used = true;
        break;
      }
    }

    if (fault != null && fault.timing == _FaultTiming.before) {
      if (fault.error != null) {
        throw fault.error!;
      }
    }

    final T result = mutation();
    final _AsyncGate? gate =
        _afterMutationGates[_operationInvocationKey(operation, invocation)];
    if (gate != null) {
      await gate.block();
    }

    if (fault != null && fault.timing == _FaultTiming.after) {
      if (fault.error != null) {
        throw fault.error!;
      }
    }
    return result;
  }

  void _requireLease(int recordingId, String leaseId) {
    final String? owner = _recordingLeases[recordingId];
    if (owner != leaseId) {
      throw StateError(
        'Recording $recordingId is owned by $owner, not $leaseId.',
      );
    }
  }

  RecordingPart? _findPart(int recordingId, int partId) {
    for (final RecordingPart part
        in _parts[recordingId] ?? const <RecordingPart>[]) {
      if (part.id == partId) return part;
    }
    return null;
  }

  void _releaseLeaseState(int recordingId, String leaseId) {
    if (_recordingLeases[recordingId] == leaseId) {
      _recordingLeases.remove(recordingId);
      _recordingLeaseUpdatedAt.remove(recordingId);
      final Recording? recording = _recordings[recordingId];
      if (recording != null) {
        recording
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
      }
    }
    final List<String> keysToRelease = _partLeases.entries
        .where((MapEntry<String, String> entry) =>
            entry.value == leaseId && entry.key.startsWith('$recordingId:'))
        .map((MapEntry<String, String> entry) => entry.key)
        .toList(growable: false);
    for (final String key in keysToRelease) {
      _partLeases.remove(key);
      final int partId = int.parse(key.split(':').last);
      final RecordingPart? part = _findPart(recordingId, partId);
      if (part != null) {
        part.sending = false;
      }
    }
  }

  void verifyFaultsExhausted() {
    final List<_StoreFault> unused =
        _faults.where((_StoreFault fault) => !fault.used).toList();
    if (unused.isNotEmpty) {
      throw StateError(
        'Unused store faults: ${unused.map((_StoreFault fault) => '${fault.operation.name}#${fault.invocation}').join(', ')}',
      );
    }
  }

  void releaseAllGates() {
    for (final _AsyncGate gate in _afterMutationGates.values) {
      gate.release();
    }
  }
}

String _partKey(int recordingId, int partId) => '$recordingId:$partId';

String _operationInvocationKey(_StoreOperation operation, int invocation) {
  return '${operation.name}#$invocation';
}

enum _ApiStepKind { returning, throwing, commitThenThrow }

class _ApiStep<T> {
  _ApiStep.returning(
    this.value, {
    this.gate,
    this.progress = const <(int, int)>[],
    this.createPostLegs = 1,
    this.betweenCreatePostLegsGate,
  })  : kind = _ApiStepKind.returning,
        error = null,
        assert(createPostLegs > 0);

  _ApiStep.throwing(
    this.error, {
    this.gate,
    this.progress = const <(int, int)>[],
    this.createPostLegs = 1,
    this.betweenCreatePostLegsGate,
  })  : kind = _ApiStepKind.throwing,
        value = null,
        assert(createPostLegs > 0);

  _ApiStep.commitThenThrow(
    this.value,
    this.error, {
    this.gate,
    this.progress = const <(int, int)>[],
    this.createPostLegs = 1,
    this.betweenCreatePostLegsGate,
  })  : kind = _ApiStepKind.commitThenThrow,
        assert(createPostLegs > 0);

  final _ApiStepKind kind;
  final T? value;
  final Object? error;
  final _AsyncGate? gate;
  final List<(int, int)> progress;
  final int createPostLegs;
  final _AsyncGate? betweenCreatePostLegsGate;
}

class _FakeUploadApi implements RecordingUploadApi {
  _FakeUploadApi(this.trace);

  final List<String> trace;
  final List<String> calls = <String>[];
  final Queue<_ApiStep<int>> _createSteps = Queue<_ApiStep<int>>();
  final Map<int, Queue<_ApiStep<int>>> _partSteps =
      <int, Queue<_ApiStep<int>>>{};
  final Map<int, Queue<_ApiStep<bool>>> _existsSteps =
      <int, Queue<_ApiStep<bool>>>{};
  final Map<String, int> _parentsByKey = <String, int>{};
  final Map<String, int> _partsByKey = <String, int>{};
  final List<_CreateCall> createCalls = <_CreateCall>[];
  final List<_PartCall> partCalls = <_PartCall>[];
  final List<_ExistsCall> existsCalls = <_ExistsCall>[];
  int remoteParentCreations = 0;
  int remotePartCreations = 0;

  void scriptCreate(_ApiStep<int> step) {
    _createSteps.add(step);
  }

  void scriptPart(int partId, _ApiStep<int> step) {
    _partSteps.putIfAbsent(partId, Queue<_ApiStep<int>>.new).add(step);
  }

  void scriptExists(int partId, _ApiStep<bool> step) {
    _existsSteps.putIfAbsent(partId, Queue<_ApiStep<bool>>.new).add(step);
  }

  @override
  Future<int> createRecording({
    required Recording recording,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
  }) async {
    final int? replay = _parentsByKey[idempotencyKey];
    if (replay != null) {
      await beforePost();
      _recordCreatePost(recording, session, idempotencyKey);
      return replay;
    }
    if (_createSteps.isEmpty) {
      throw StateError('Unexpected createRecording call for $idempotencyKey.');
    }
    final _ApiStep<int> step = _createSteps.removeFirst();
    for (int leg = 0; leg < step.createPostLegs; leg++) {
      await beforePost();
      _recordCreatePost(recording, session, idempotencyKey);
      if (leg + 1 < step.createPostLegs &&
          step.betweenCreatePostLegsGate != null) {
        await step.betweenCreatePostLegsGate!.block();
      }
    }
    if (step.gate != null) {
      await step.gate!.block();
    }
    if (step.kind == _ApiStepKind.throwing) {
      throw step.error!;
    }
    final int value = step.value!;
    if (value > 0) {
      _parentsByKey[idempotencyKey] = value;
      remoteParentCreations++;
    }
    if (step.kind == _ApiStepKind.commitThenThrow) {
      throw step.error!;
    }
    return value;
  }

  void _recordCreatePost(
    Recording recording,
    RecordingUploadSession session,
    String idempotencyKey,
  ) {
    calls.add('create');
    trace.add('api.create:$idempotencyKey');
    createCalls.add(
      _CreateCall(
        recording: _copyRecording(recording),
        session: session,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  @override
  Future<int> uploadRecordingPart({
    required RecordingPart part,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
    RecordingPartUploadProgress? onProgress,
  }) async {
    final int partId =
        part.id ?? (throw StateError('API received a null part id.'));

    final int? replay = _partsByKey[idempotencyKey];
    if (replay != null) {
      await beforePost();
      _recordPartPost(part, session, idempotencyKey, partId);
      return replay;
    }
    final Queue<_ApiStep<int>>? steps = _partSteps[partId];
    if (steps == null || steps.isEmpty) {
      throw StateError('Unexpected uploadRecordingPart call for part $partId.');
    }
    final _ApiStep<int> step = steps.removeFirst();
    if (step.gate != null) {
      await step.gate!.block();
    }
    await beforePost();
    _recordPartPost(part, session, idempotencyKey, partId);
    for (final (int, int) update in step.progress) {
      onProgress?.call(update.$1, update.$2);
    }
    if (step.kind == _ApiStepKind.throwing) {
      throw step.error!;
    }
    final int value = step.value!;
    if (value > 0) {
      _partsByKey[idempotencyKey] = value;
      remotePartCreations++;
    }
    if (step.kind == _ApiStepKind.commitThenThrow) {
      throw step.error!;
    }
    return value;
  }

  void _recordPartPost(
    RecordingPart part,
    RecordingUploadSession session,
    String idempotencyKey,
    int partId,
  ) {
    calls.add('uploadPart:$partId');
    trace.add('api.uploadPart:$partId');
    partCalls.add(
      _PartCall(
        part: _copyPart(part),
        session: session,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  @override
  Future<bool> recordingPartExists({
    required RecordingPart part,
    required RecordingUploadSession session,
  }) async {
    final int partId =
        part.id ?? (throw StateError('API received a null part id.'));
    calls.add('exists:$partId');
    trace.add('api.exists:$partId');
    existsCalls.add(
      _ExistsCall(part: _copyPart(part), session: session),
    );
    final Queue<_ApiStep<bool>>? steps = _existsSteps[partId];
    if (steps == null || steps.isEmpty) {
      throw StateError('Unexpected recordingPartExists call for part $partId.');
    }
    final _ApiStep<bool> step = steps.removeFirst();
    if (step.gate != null) {
      await step.gate!.block();
    }
    if (step.kind != _ApiStepKind.returning) {
      throw step.error!;
    }
    return step.value!;
  }

  void verifyExhausted() {
    final int pendingParts = _partSteps.values.fold<int>(
      0,
      (int count, Queue<_ApiStep<int>> queue) => count + queue.length,
    );
    final int pendingExists = _existsSteps.values.fold<int>(
      0,
      (int count, Queue<_ApiStep<bool>> queue) => count + queue.length,
    );
    if (_createSteps.isNotEmpty || pendingParts > 0 || pendingExists > 0) {
      throw StateError(
        'Unused API steps: create=${_createSteps.length}, '
        'parts=$pendingParts, exists=$pendingExists.',
      );
    }
  }

  void releaseAllGates() {
    for (final _ApiStep<int> step in _createSteps) {
      step.gate?.release();
    }
    for (final Queue<_ApiStep<int>> queue in _partSteps.values) {
      for (final _ApiStep<int> step in queue) {
        step.gate?.release();
      }
    }
    for (final Queue<_ApiStep<bool>> queue in _existsSteps.values) {
      for (final _ApiStep<bool> step in queue) {
        step.gate?.release();
      }
    }
  }
}

class _CreateCall {
  const _CreateCall({
    required this.recording,
    required this.session,
    required this.idempotencyKey,
  });

  final Recording recording;
  final RecordingUploadSession session;
  final String idempotencyKey;
}

class _PartCall {
  const _PartCall({
    required this.part,
    required this.session,
    required this.idempotencyKey,
  });

  final RecordingPart part;
  final RecordingUploadSession session;
  final String idempotencyKey;

  int get partId => part.id!;
}

class _ExistsCall {
  const _ExistsCall({
    required this.part,
    required this.session,
  });

  final RecordingPart part;
  final RecordingUploadSession session;
}

class _FakeSessionProvider implements RecordingUploadSessionProvider {
  _FakeSessionProvider(this.trace);

  final List<String> trace;
  RecordingUploadSession? capturedSession = _defaultSession;
  Object? captureError;
  final Set<int> notCurrentAt = <int>{};
  final Map<int, Object> currentErrors = <int, Object>{};
  int captureCalls = 0;
  int currentCalls = 0;

  @override
  Future<RecordingUploadSession?> capture() async {
    captureCalls++;
    trace.add('session.capture#$captureCalls');
    if (captureError != null) {
      throw captureError!;
    }
    return capturedSession;
  }

  @override
  Future<bool> isCurrent(RecordingUploadSession session) async {
    currentCalls++;
    trace.add('session.current#$currentCalls');
    final Object? error = currentErrors[currentCalls];
    if (error != null) {
      throw error;
    }
    return !notCurrentAt.contains(currentCalls);
  }
}

class _FakePolicy implements RecordingUploadPolicy {
  _FakePolicy(this.trace);

  final List<String> trace;
  bool allowed = true;
  Object? error;
  int calls = 0;

  @override
  Future<bool> canUpload() async {
    calls++;
    trace.add('policy.canUpload#$calls');
    if (error != null) throw error!;
    return allowed;
  }
}

class _FakeFileProbe implements RecordingUploadFileProbe {
  _FakeFileProbe(this.trace);

  final List<String> trace;
  final Map<String, bool> results = <String, bool>{};
  final Map<String, RecordingUploadFileFingerprint> fingerprints =
      <String, RecordingUploadFileFingerprint>{};
  final Map<String, List<RecordingUploadFileFingerprint?>>
      scriptedFingerprints = <String, List<RecordingUploadFileFingerprint?>>{};
  final Map<String, Object> errors = <String, Object>{};
  final List<String> calls = <String>[];

  @override
  Future<RecordingUploadFileFingerprint?> inspect(String path) async {
    calls.add(path);
    trace.add('file.exists:$path');
    final Object? error = errors[path];
    if (error != null) throw error;
    if (!results.containsKey(path)) {
      throw StateError('Unexpected file probe for $path.');
    }
    if (!results[path]!) return null;
    final List<RecordingUploadFileFingerprint?>? scripted =
        scriptedFingerprints[path];
    if (scripted != null && scripted.isNotEmpty) {
      return scripted.removeAt(0);
    }
    return fingerprints[path] ?? _defaultFingerprint(path);
  }

  static RecordingUploadFileFingerprint _defaultFingerprint(String path) {
    final int marker = path.codeUnits.fold<int>(
      0,
      (int value, int codeUnit) => (value * 31 + codeUnit) & 0xffffffff,
    );
    final String block = marker.toRadixString(16).padLeft(8, '0');
    return RecordingUploadFileFingerprint(
      sha256: List<String>.filled(8, block).join(),
      byteLength: 128,
    );
  }
}

class _AsyncGate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> _released = Completer<void>();

  Future<void> block() async {
    if (!entered.isCompleted) {
      entered.complete();
    }
    await _released.future;
  }

  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }
}

class _TestException implements Exception {
  const _TestException(this.message);

  final String message;

  @override
  String toString() => '_TestException: $message';
}

RecordingUploadFileFingerprint _testFingerprint(
  String hexDigit, {
  int byteLength = 128,
}) {
  return RecordingUploadFileFingerprint(
    sha256: List<String>.filled(64, hexDigit).join(),
    byteLength: byteLength,
  );
}
