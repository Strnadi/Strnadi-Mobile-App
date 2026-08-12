import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/database/upload_protocol.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  group('upload response ids', () {
    for (final dynamic payload in <dynamic>[
      17,
      17.0,
      '17',
      '"17"',
      <String, dynamic>{'id': 17},
      <String, dynamic>{
        'data': <String, dynamic>{'filteredPartId': '17'},
      },
    ]) {
      test('accepts positive integral payload $payload', () {
        expect(
          readPositiveUploadResponseId(
            payload,
            entity: 'dialect',
            mapKeys: const <String>['id', 'filteredPartId', 'data'],
          ),
          17,
        );
      });
    }

    for (final dynamic payload in <dynamic>[
      null,
      0,
      -1,
      1.5,
      '',
      'not-an-id',
      <String, dynamic>{},
      <String, dynamic>{'id': 0},
      <String, dynamic>{
        'data': <String, dynamic>{'id': -4}
      },
    ]) {
      test('rejects malformed payload $payload', () {
        expect(
          () => readPositiveUploadResponseId(
            payload,
            entity: 'dialect',
            mapKeys: const <String>['id', 'filteredPartId', 'data'],
          ),
          throwsA(
            isA<UploadException>().having(
              (UploadException error) => error.statusCode,
              'statusCode',
              502,
            ),
          ),
        );
      });
    }
  });

  group('recording-part reconciliation payloads (fake API, no DB)', () {
    Map<String, dynamic> payload({
      dynamic id = 900,
      dynamic parts = const <dynamic>[],
    }) {
      return <String, dynamic>{'id': id, 'parts': parts};
    }

    Map<String, dynamic> part({
      dynamic id = 101,
      dynamic recordingId = 900,
    }) {
      return <String, dynamic>{'id': id, 'recordingId': recordingId};
    }

    Matcher malformedBackendPayload() {
      return isA<UploadException>().having(
        (UploadException error) => error.statusCode,
        'statusCode',
        502,
      );
    }

    test('confirms an expected part only under the expected parent', () {
      expect(
        recordingPayloadConfirmsPartExists(
          payload(parts: <dynamic>[part(id: 100), part(id: 101)]),
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        isTrue,
      );
    });

    test('accepts a JSON response string from the fake transport', () {
      expect(
        recordingPayloadConfirmsPartExists(
          '{"id":900,"parts":[{"id":101,"recordingId":900}]}',
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        isTrue,
      );
    });

    test('proves an expected part absent from a valid complete payload', () {
      expect(
        recordingPayloadConfirmsPartExists(
          payload(parts: <dynamic>[part(id: 100), part(id: 102)]),
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        isFalse,
      );
    });

    test('proves an expected part absent from a valid empty parts list', () {
      expect(
        recordingPayloadConfirmsPartExists(
          payload(),
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        isFalse,
      );
    });

    for (final ({int recordingId, int partId}) ids
        in <({int recordingId, int partId})>[
      (recordingId: 0, partId: 101),
      (recordingId: -1, partId: 101),
      (recordingId: 900, partId: 0),
      (recordingId: 900, partId: -1),
    ]) {
      test('rejects invalid expected identities $ids before parsing', () {
        expect(
          () => recordingPayloadConfirmsPartExists(
            payload(),
            expectedRecordingId: ids.recordingId,
            expectedPartId: ids.partId,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    for (final dynamic malformed in <dynamic>[
      null,
      900,
      <dynamic>[],
      '',
      'not-json',
      '[]',
    ]) {
      test('fails closed for non-recording payload $malformed', () {
        expect(
          () => recordingPayloadConfirmsPartExists(
            malformed,
            expectedRecordingId: 900,
            expectedPartId: 101,
          ),
          throwsA(malformedBackendPayload()),
        );
      });
    }

    for (final dynamic invalidParentId in <dynamic>[
      null,
      0,
      -1,
      900.5,
      '900',
      901,
    ]) {
      test('fails closed for parent identity $invalidParentId', () {
        expect(
          () => recordingPayloadConfirmsPartExists(
            payload(id: invalidParentId),
            expectedRecordingId: 900,
            expectedPartId: 101,
          ),
          throwsA(malformedBackendPayload()),
        );
      });
    }

    for (final dynamic malformedParts in <dynamic>[
      null,
      <String, dynamic>{},
      'parts',
      1,
    ]) {
      test('fails closed when parts is not a list: $malformedParts', () {
        expect(
          () => recordingPayloadConfirmsPartExists(
            payload(parts: malformedParts),
            expectedRecordingId: 900,
            expectedPartId: 101,
          ),
          throwsA(malformedBackendPayload()),
        );
      });
    }

    test('fails closed when the parts field is omitted', () {
      expect(
        () => recordingPayloadConfirmsPartExists(
          <String, dynamic>{'id': 900},
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        throwsA(malformedBackendPayload()),
      );
    });

    for (final dynamic malformedPart in <dynamic>[
      null,
      101,
      'part',
      <dynamic>[],
      <String, dynamic>{'recordingId': 900},
      <String, dynamic>{'id': 101},
      <String, dynamic>{'id': 0, 'recordingId': 900},
      <String, dynamic>{'id': -1, 'recordingId': 900},
      <String, dynamic>{'id': 101.5, 'recordingId': 900},
      <String, dynamic>{'id': '101', 'recordingId': 900},
      <String, dynamic>{'id': 101, 'recordingId': 0},
      <String, dynamic>{'id': 101, 'recordingId': 901},
      <String, dynamic>{'id': 101, 'recordingId': '900'},
    ]) {
      test('fails closed for malformed or foreign part $malformedPart', () {
        expect(
          () => recordingPayloadConfirmsPartExists(
            payload(parts: <dynamic>[malformedPart]),
            expectedRecordingId: 900,
            expectedPartId: 101,
          ),
          throwsA(malformedBackendPayload()),
        );
      });
    }

    test('fails closed for duplicate backend part identities', () {
      expect(
        () => recordingPayloadConfirmsPartExists(
          payload(parts: <dynamic>[part(id: 101), part(id: 101)]),
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        throwsA(malformedBackendPayload()),
      );
    });

    test('validates every part even after finding the expected identity', () {
      expect(
        () => recordingPayloadConfirmsPartExists(
          payload(parts: <dynamic>[
            part(id: 101),
            part(id: 102, recordingId: 901),
          ]),
          expectedRecordingId: 900,
          expectedPartId: 101,
        ),
        throwsA(malformedBackendPayload()),
      );
    });
  });

  group('dialect idempotency keys', () {
    test('uses both durable entity keys and no recyclable row ids', () {
      expect(
        dialectUploadIdempotencyKey(
          recordingUploadKey: 'recording-random-A',
          dialectUploadKey: 'dialect-random-B',
        ),
        'recording-dialect:recording-random-A:dialect-random-B',
      );
    });

    for (final ({String recording, String dialect}) keys
        in <({String recording, String dialect})>[
      (recording: '', dialect: 'dialect-key'),
      (recording: 'recording-key', dialect: ''),
      (recording: '   ', dialect: 'dialect-key'),
      (recording: 'recording-key', dialect: '   '),
    ]) {
      test('rejects missing durable key $keys', () {
        expect(
          () => dialectUploadIdempotencyKey(
            recordingUploadKey: keys.recording,
            dialectUploadKey: keys.dialect,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }
  });

  group('durably marked dialect attempts (all boundaries mocked)', () {
    test(
        'session change during marker persistence sends nothing and retry '
        'reuses the durable marker', () async {
      final Completer<void> markerEntered = Completer<void>();
      final Completer<void> releaseMarker = Completer<void>();
      var sessionCurrent = true;
      var durableMarker = false;
      var inMemoryMarker = false;
      var markerWrites = 0;
      var posts = 0;
      var beforePostChecks = 0;

      Future<void> renew() async {
        beforePostChecks++;
        if (!sessionCurrent) {
          throw const RecordingUploadSessionChangedException();
        }
      }

      final Future<int> first = runDialectUploadAttempt<int>(
        uploadAttempted: durableMarker,
        persistAttemptMarker: () async {
          markerWrites++;
          markerEntered.complete();
          await releaseMarker.future;
          durableMarker = true;
        },
        markAttemptedInMemory: () {
          inMemoryMarker = true;
        },
        renew: renew,
        post: (Future<void> Function() beforePost) async {
          await beforePost();
          posts++;
          return 17;
        },
      );

      await markerEntered.future;
      sessionCurrent = false;
      releaseMarker.complete();

      await expectLater(
        first,
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );
      expect(durableMarker, isTrue);
      expect(inMemoryMarker, isTrue);
      expect(markerWrites, 1);
      expect(posts, 0);

      sessionCurrent = true;
      final int retried = await runDialectUploadAttempt<int>(
        uploadAttempted: durableMarker,
        persistAttemptMarker: () async {
          markerWrites++;
        },
        markAttemptedInMemory: () {
          inMemoryMarker = true;
        },
        renew: renew,
        post: (Future<void> Function() beforePost) async {
          await beforePost();
          posts++;
          return 17;
        },
      );

      expect(retried, 17);
      expect(markerWrites, 1);
      expect(posts, 1);
      // One failed post-marker renewal plus the retry's post-marker and
      // immediate pre-POST renewals.
      expect(beforePostChecks, 3);
    });

    test('marker acknowledgement loss remains retryable without another write',
        () async {
      final StateError acknowledgementLoss =
          StateError('mock marker acknowledgement lost');
      var durableMarker = false;
      var inMemoryMarker = false;
      var markerWrites = 0;
      var posts = 0;

      await expectLater(
        runDialectUploadAttempt<void>(
          uploadAttempted: durableMarker,
          persistAttemptMarker: () async {
            markerWrites++;
            durableMarker = true;
            throw acknowledgementLoss;
          },
          markAttemptedInMemory: () {
            inMemoryMarker = true;
          },
          renew: () async {},
          post: (Future<void> Function() beforePost) async {
            posts++;
          },
        ),
        throwsA(same(acknowledgementLoss)),
      );

      expect(durableMarker, isTrue);
      expect(inMemoryMarker, isFalse);
      expect(markerWrites, 1);
      expect(posts, 0);

      await runDialectUploadAttempt<void>(
        uploadAttempted: durableMarker,
        persistAttemptMarker: () async {
          markerWrites++;
        },
        markAttemptedInMemory: () {
          inMemoryMarker = true;
        },
        renew: () async {},
        post: (Future<void> Function() beforePost) async {
          await beforePost();
          posts++;
        },
      );

      expect(markerWrites, 1);
      expect(posts, 1);
    });
  });

  group('persisted dialect backend association', () {
    test('accepts a positive dialect id owned by the expected recording', () {
      expect(
        () => validatePersistedDialectBackendAssociation(
          backendDialectId: 12,
          backendRecordingId: 34,
          expectedBackendRecordingId: 34,
        ),
        returnsNormally,
      );
    });

    for (final int invalidDialectId in <int>[0, -1]) {
      test('rejects invalid dialect id $invalidDialectId', () {
        expect(
          () => validatePersistedDialectBackendAssociation(
            backendDialectId: invalidDialectId,
            backendRecordingId: 34,
            expectedBackendRecordingId: 34,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    for (final int? wrongParent in <int?>[null, 0, -1, 33]) {
      test('rejects missing or mismatched backend parent $wrongParent', () {
        expect(
          () => validatePersistedDialectBackendAssociation(
            backendDialectId: 12,
            backendRecordingId: wrongParent,
            expectedBackendRecordingId: 34,
          ),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    test('rejects an invalid expected backend parent', () {
      expect(
        () => validatePersistedDialectBackendAssociation(
          backendDialectId: 12,
          backendRecordingId: 34,
          expectedBackendRecordingId: 0,
        ),
        throwsA(isA<RecordingUploadValidationException>()),
      );
    });
  });

  group('dialect request validation', () {
    final Map<String, dynamic> validBody = <String, dynamic>{
      'recordingId': 34,
      'startDate': '2026-07-18T10:00:00.000Z',
      'endDate': '2026-07-18T10:00:01.000Z',
      'dialectCode': 'BC',
    };

    test('accepts a complete request with a positive time range', () {
      expect(
        () => validateDialectUploadRequest(validBody),
        returnsNormally,
      );
    });

    for (final dynamic invalidRecordingId in <dynamic>[
      null,
      0,
      -1,
      1.5,
      '34',
    ]) {
      test('rejects backend recording id $invalidRecordingId', () {
        expect(
          () => validateDialectUploadRequest(<String, dynamic>{
            ...validBody,
            'recordingId': invalidRecordingId,
          }),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    for (final dynamic invalidCode in <dynamic>[null, '', '   ', 12]) {
      test('rejects dialect code $invalidCode', () {
        expect(
          () => validateDialectUploadRequest(<String, dynamic>{
            ...validBody,
            'dialectCode': invalidCode,
          }),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }

    for (final ({dynamic start, dynamic end}) range
        in <({dynamic start, dynamic end})>[
      (start: null, end: '2026-07-18T10:00:01.000Z'),
      (start: 'invalid', end: '2026-07-18T10:00:01.000Z'),
      (start: '2026-07-18T10:00:00.000Z', end: null),
      (start: '2026-07-18T10:00:00.000Z', end: 'invalid'),
      (start: '2026-07-18T10:00:00.000Z', end: '2026-07-18T10:00:00.000Z'),
      (start: '2026-07-18T10:00:01.000Z', end: '2026-07-18T10:00:00.000Z'),
    ]) {
      test('rejects invalid time range $range', () {
        expect(
          () => validateDialectUploadRequest(<String, dynamic>{
            ...validBody,
            'startDate': range.start,
            'endDate': range.end,
          }),
          throwsA(isA<RecordingUploadValidationException>()),
        );
      });
    }
  });

  group('background retry classification', () {
    for (final int status in <int>[401, 408, 409, 425, 429, 500, 503]) {
      test('retries upload status $status', () {
        expect(
          isRetryableRecordingUploadFailure(
            UploadException('failed', status),
          ),
          isTrue,
        );
      });
    }

    for (final int status in <int>[400, 403, 404, 410, 422]) {
      test('does not retry permanent upload status $status', () {
        expect(
          isRetryableRecordingUploadFailure(
            UploadException('failed', status),
          ),
          isFalse,
        );
      });
    }

    test('does not retry local validation failures', () {
      expect(
        isRetryableRecordingUploadFailure(
          const RecordingUploadValidationException('invalid'),
        ),
        isFalse,
      );
    });

    test('retries session, transport, and unknown persistence failures', () {
      expect(
        isRetryableRecordingUploadFailure(
          const RecordingUploadSessionChangedException(),
        ),
        isTrue,
      );
      expect(
        isRetryableRecordingUploadFailure(
          FetchException('timeout', 500),
        ),
        isTrue,
      );
      expect(
        isRetryableRecordingUploadFailure(StateError('database busy')),
        isTrue,
      );
    });
  });
}
