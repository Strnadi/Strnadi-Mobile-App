import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localRecordings/upload_integration_helpers.dart';

void main() {
  group('backend incomplete-upload snapshot (pure fake payloads)', () {
    test('parses positive numeric and string ids from the real list shape', () {
      final BackendIncompleteUploadSnapshot snapshot =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: 200,
        payload: <dynamic>[243, '244'],
      );

      expect(snapshot.isAuthoritative, isTrue);
      expect(snapshot.entriesByRecordingId.keys, <int>{243, 244});
      expect(snapshot.entryFor(243)?.hasExactPartCounts, isFalse);
      expect(
        snapshot.entryFor(243)?.requiresFullPartReconciliation,
        isTrue,
      );
      expect(snapshot.authoritativelyConfirmsComplete(245), isTrue);
      expect(snapshot.authoritativelyConfirmsComplete(243), isFalse);
    });

    test('200 empty and 204 are authoritative empty results', () {
      final BackendIncompleteUploadSnapshot empty200 =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: 200,
        payload: const <dynamic>[],
      );
      final BackendIncompleteUploadSnapshot empty204 =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: 204,
        payload: null,
      );

      for (final BackendIncompleteUploadSnapshot snapshot
          in <BackendIncompleteUploadSnapshot>[empty200, empty204]) {
        expect(snapshot.isAuthoritative, isTrue);
        expect(snapshot.entriesByRecordingId, isEmpty);
        expect(snapshot.authoritativelyConfirmsComplete(900), isTrue);
      }
    });

    test('non-success response cannot override stale local state', () {
      final BackendIncompleteUploadSnapshot unavailable =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: 503,
        payload: const <dynamic>[],
      );

      expect(unavailable.isAuthoritative, isFalse);
      expect(unavailable.authoritativelyConfirmsComplete(900), isFalse);
    });

    test('malformed 200 payload fails closed instead of looking empty', () {
      for (final dynamic payload in <dynamic>[
        null,
        <dynamic>[243, 0],
        <dynamic>['invalid'],
        <String, dynamic>{},
        <String, dynamic>{'data': null},
      ]) {
        final BackendIncompleteUploadSnapshot snapshot =
            backendIncompleteUploadSnapshotFromResponse(
          statusCode: 200,
          payload: payload,
        );

        expect(snapshot.isAuthoritative, isFalse, reason: 'Payload: $payload');
        expect(
          snapshot.authoritativelyConfirmsComplete(900),
          isFalse,
          reason: 'Payload: $payload',
        );
      }
    });

    test('keeps exact counts and positive uploaded part ids from objects', () {
      final BackendIncompleteUploadSnapshot snapshot =
          backendIncompleteUploadSnapshotFromResponse(
        statusCode: 200,
        payload: <dynamic>[
          <String, dynamic>{
            'id': 900,
            'expectedPartsCount': 2,
            'uploadedPartsCount': 1,
            'parts': <dynamic>[
              <String, dynamic>{'id': 101},
            ],
          },
        ],
      );
      final BackendIncompleteUploadEntry entry = snapshot.entryFor(900)!;

      expect(entry.hasExactPartCounts, isTrue);
      expect(entry.expectedPartsCount, 2);
      expect(entry.uploadedPartsCount, 1);
      expect(entry.uploadedBackendPartIds, <int>{101});
      expect(entry.requiresFullPartReconciliation, isFalse);
    });
  });

  group('best-effort upload batches', () {
    test('attempts every item after individual failures', () async {
      final List<int> attempted = <int>[];
      final StateError firstFailure = StateError('first failed');
      final ArgumentError thirdFailure = ArgumentError('third failed');

      final BestEffortBatchResult<int> result = await runBestEffortBatch<int>(
        <int>[1, 2, 3, 4],
        (int item) async {
          attempted.add(item);
          if (item == 1) throw firstFailure;
          if (item == 3) throw thirdFailure;
        },
      );

      expect(attempted, <int>[1, 2, 3, 4]);
      expect(result.succeededItems, <int>[2, 4]);
      expect(
        result.failures.map((BestEffortBatchFailure<int> value) => value.item),
        <int>[1, 3],
      );
      expect(result.failures.first.error, same(firstFailure));
      expect(result.failures.last.error, same(thirdFailure));
      expect(result.succeeded, isFalse);
    });

    test('reports an empty or fully successful batch without failures',
        () async {
      final BestEffortBatchResult<int> empty = await runBestEffortBatch<int>(
        const <int>[],
        (_) async {},
      );
      final BestEffortBatchResult<int> successful =
          await runBestEffortBatch<int>(
        <int>[1, 2],
        (_) async {},
      );

      expect(empty.succeeded, isTrue);
      expect(empty.succeededItems, isEmpty);
      expect(successful.succeeded, isTrue);
      expect(successful.succeededItems, <int>[1, 2]);
    });
  });

  group('recording upload action state', () {
    test('a sending flag, durable lease, or sending part is active', () {
      expect(
        recordingUploadIsActive(
          recordingSending: true,
          recordingLease: null,
          partSendingStates: const <bool>[false],
        ),
        isTrue,
      );
      expect(
        recordingUploadIsActive(
          recordingSending: false,
          recordingLease: ' lease-42 ',
          partSendingStates: const <bool>[false],
        ),
        isTrue,
      );
      expect(
        recordingUploadIsActive(
          recordingSending: false,
          recordingLease: '   ',
          partSendingStates: const <bool>[false, true],
        ),
        isTrue,
      );
    });

    test('an idle recording with only a blank lease is inactive', () {
      expect(
        recordingUploadIsActive(
          recordingSending: false,
          recordingLease: '   ',
          partSendingStates: const <bool>[false, false],
        ),
        isFalse,
      );
    });

    test('active ownership disables both initial send and part resend', () {
      expect(
        canStartRecordingUpload(
          captureReviewed: true,
          recordingSent: false,
          uploadIsActive: true,
        ),
        isFalse,
      );
      expect(
        canResendRecordingParts(
          captureReviewed: true,
          uploadIsActive: true,
          hasIdleUnsentParts: true,
        ),
        isFalse,
      );
    });

    test('an unreviewed capture exposes no send or resend action', () {
      expect(
        canStartRecordingUpload(
          captureReviewed: false,
          recordingSent: false,
          uploadIsActive: false,
        ),
        isFalse,
      );
      expect(
        canResendRecordingParts(
          captureReviewed: false,
          uploadIsActive: false,
          hasIdleUnsentParts: true,
        ),
        isFalse,
      );
    });
  });

  group('incomplete upload discovery and reconciliation', () {
    test('explicit backend completion suppresses stale local warnings', () {
      expect(
        aggregateUploadNeedsAttention(
          backendExpectedPartsCount: 1,
          backendUploadedPartsCount: 1,
          backendSaysIncomplete: false,
          localSaysIncomplete: true,
        ),
        isFalse,
        reason: 'A remotely complete 1-of-1 upload must never prompt.',
      );
      expect(
        aggregateUploadNeedsAttention(
          backendExpectedPartsCount: 1,
          backendUploadedPartsCount: 2,
          backendSaysIncomplete: true,
          localSaysIncomplete: true,
        ),
        isFalse,
        reason: 'An uploaded surplus is also explicit completion evidence.',
      );
    });

    test('incomplete backend counts still require attention', () {
      expect(
        aggregateUploadNeedsAttention(
          backendExpectedPartsCount: 2,
          backendUploadedPartsCount: 1,
          backendSaysIncomplete: true,
          localSaysIncomplete: false,
        ),
        isTrue,
      );
    });

    test('invalid backend completion counts do not hide local issues', () {
      for (final ({
        int? expected,
        int? uploaded,
      }) counts in <({
        int? expected,
        int? uploaded,
      })>[
        (expected: null, uploaded: 1),
        (expected: 0, uploaded: 1),
        (expected: -1, uploaded: 1),
        (expected: 1, uploaded: null),
        (expected: 2, uploaded: 1),
      ]) {
        expect(
          aggregateUploadNeedsAttention(
            backendExpectedPartsCount: counts.expected,
            backendUploadedPartsCount: counts.uploaded,
            backendSaysIncomplete: false,
            localSaysIncomplete: true,
          ),
          isTrue,
          reason: 'Counts $counts are not explicit completion evidence.',
        );
      }
    });

    test('complete local state remains quiet without backend evidence', () {
      expect(
        aggregateUploadNeedsAttention(
          backendExpectedPartsCount: null,
          backendUploadedPartsCount: null,
          backendSaysIncomplete: false,
          localSaysIncomplete: false,
        ),
        isFalse,
      );
    });

    test('only exact missing backend counts are displayable', () {
      expect(
        backendMissingPartCountsAreDisplayable(
          hasExactBackendPartCounts: true,
          expectedPartsCount: 2,
          uploadedPartsCount: 1,
        ),
        isTrue,
      );
      for (final ({
        bool exact,
        int expected,
        int uploaded,
      }) state in <({
        bool exact,
        int expected,
        int uploaded,
      })>[
        (exact: false, expected: 2, uploaded: 1),
        (exact: true, expected: 1, uploaded: 1),
        (exact: true, expected: 1, uploaded: 2),
        (exact: true, expected: 0, uploaded: 0),
        (exact: true, expected: 1, uploaded: -1),
      ]) {
        expect(
          backendMissingPartCountsAreDisplayable(
            hasExactBackendPartCounts: state.exact,
            expectedPartsCount: state.expected,
            uploadedPartsCount: state.uploaded,
          ),
          isFalse,
          reason: 'State $state must use the generic message.',
        );
      }
    });

    test('aggregate retry requires every expected local row', () {
      expect(
        incompleteAggregateCanBeRetried(
          localPartsCount: 2,
          expectedPartsCount: 2,
        ),
        isTrue,
      );
      for (final ({int local, int expected}) counts
          in <({int local, int expected})>[
        (local: 0, expected: 0),
        (local: 1, expected: 2),
        (local: 3, expected: 2),
        (local: 1, expected: -1),
      ]) {
        expect(
          incompleteAggregateCanBeRetried(
            localPartsCount: counts.local,
            expectedPartsCount: counts.expected,
          ),
          isFalse,
          reason: 'An aggregate with counts $counts cannot pass preflight.',
        );
      }
    });

    test('an ambiguous unsent backend id is retryable without a local file',
        () {
      expect(
        incompletePartCanBeRetried(
          sent: false,
          sending: false,
          backendPartId: 101,
          localPath: null,
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: false,
        ),
        isTrue,
      );
    });

    test('a missing local-only part requires a non-blank file path', () {
      for (final String? path in <String?>[null, '', '   ']) {
        expect(
          incompletePartCanBeRetried(
            sent: false,
            sending: false,
            backendPartId: null,
            localPath: path,
            uploadedBackendPartIds: null,
            reconcileAllBackendParts: false,
          ),
          isFalse,
        );
      }
      expect(
        incompletePartCanBeRetried(
          sent: false,
          sending: false,
          backendPartId: null,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: false,
        ),
        isTrue,
      );
    });

    test('a backend-confirmed missing part requires local repair audio', () {
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: 101,
          localPath: null,
          uploadedBackendPartIds: <int>{102},
          reconcileAllBackendParts: false,
        ),
        isFalse,
      );
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: 101,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: <int>{102},
          reconcileAllBackendParts: false,
        ),
        isTrue,
      );
    });

    test('busy and already confirmed parts are not retried', () {
      expect(
        incompletePartCanBeRetried(
          sent: false,
          sending: true,
          backendPartId: 101,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: false,
        ),
        isFalse,
      );
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: 101,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: <int>{101},
          reconcileAllBackendParts: false,
        ),
        isFalse,
      );
    });

    test('id-only backend issue reconciles every safe idle local part', () {
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: 101,
          localPath: null,
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: true,
        ),
        isTrue,
        reason: 'The aggregate service can reconcile the remembered id.',
      );
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: null,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: true,
        ),
        isTrue,
      );
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: false,
          backendPartId: null,
          localPath: null,
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: true,
        ),
        isFalse,
      );
      expect(
        incompletePartCanBeRetried(
          sent: true,
          sending: true,
          backendPartId: 101,
          localPath: '/mock/part.wav',
          uploadedBackendPartIds: null,
          reconcileAllBackendParts: true,
        ),
        isFalse,
      );
    });

    test('only a fully linked sent part counts as locally uploaded', () {
      expect(
        localPartCountsAsUploaded(
          sent: true,
          backendPartId: 101,
          backendRecordingId: 900,
          expectedBackendRecordingId: 900,
        ),
        isTrue,
      );
      for (final ({
        bool sent,
        int? part,
        int? parent,
        int? expected,
      }) state in <({
        bool sent,
        int? part,
        int? parent,
        int? expected,
      })>[
        (sent: false, part: 101, parent: 900, expected: 900),
        (sent: true, part: null, parent: 900, expected: 900),
        (sent: true, part: 0, parent: 900, expected: 900),
        (sent: true, part: 101, parent: null, expected: 900),
        (sent: true, part: 101, parent: 901, expected: 900),
      ]) {
        expect(
          localPartCountsAsUploaded(
            sent: state.sent,
            backendPartId: state.part,
            backendRecordingId: state.parent,
            expectedBackendRecordingId: state.expected,
          ),
          isFalse,
        );
      }
    });
  });
}
