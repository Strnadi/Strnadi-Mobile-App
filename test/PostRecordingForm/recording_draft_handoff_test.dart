import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/PostRecordingForm/recording_draft_handoff.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'package:strnadi/dialects/ModelHandler.dart';

void main() {
  group('durable recorder-to-form handoff (mocked DB, no API)', () {
    test('persists the complete aggregate before opening the form', () async {
      final List<String> events = <String>[];
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        events: events,
      );
      final RecordingDraftHandoffCoordinator coordinator =
          RecordingDraftHandoffCoordinator(persistence: persistence);
      RecordingDraftHandoff? navigatedDraft;

      await coordinator.persistBeforeNavigation(
        filepath: '/mock/final.wav',
        startTime: _start,
        recordingParts: <RecordingPartUnready>[
          _part(0),
          _part(1),
        ],
        recordingPartDurations: const <int>[7, 11],
        environment: 'development',
        device: 'Mock phone',
        navigate: (RecordingDraftHandoff handoff) {
          events.add('navigate');
          navigatedDraft = handoff;
        },
      );

      expect(events, <String>['insert', 'navigate']);
      expect(persistence.insertCalls, 1);
      expect(persistence.insertedDialects, isEmpty);
      expect(persistence.ownerBeforeInsert, (userId: null, mail: ''));
      final RecordingDraftHandoff handoff = navigatedDraft!;
      expect(handoff.recording.id, 41);
      expect(handoff.recording.uploadKey, 'recording-upload-41');
      expect(handoff.recording.createdAt, _start);
      expect(handoff.recording.path, '/mock/final.wav');
      expect(handoff.recording.partCount, 2);
      expect(handoff.recording.totalSeconds, 18);
      expect(handoff.recording.estimatedBirdsCount, 1);
      expect(handoff.recording.device, 'Mock phone');
      expect(handoff.recording.env, 'development');
      expect(handoff.recording.captureReviewed, isFalse);
      expect(handoff.recordingParts, hasLength(2));
      expect(
        handoff.recordingParts.map((RecordingPart part) => part.length),
        <int>[7, 11],
      );
      expect(
        handoff.recordingParts
            .map((RecordingPart part) => part.recordingId)
            .toSet(),
        <int?>{41},
      );
    });

    test('waits for the mocked durable commit before navigation', () async {
      final List<String> events = <String>[];
      final Completer<void> allowInsert = Completer<void>();
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        events: events,
        beforeInsert: () => allowInsert.future,
      );
      final RecordingDraftHandoffCoordinator coordinator =
          RecordingDraftHandoffCoordinator(persistence: persistence);

      final Future<void> operation = coordinator.persistBeforeNavigation(
        filepath: '/mock/final.wav',
        startTime: _start,
        recordingParts: <RecordingPartUnready>[_part(0)],
        recordingPartDurations: const <int>[5],
        environment: 'development',
        navigate: (_) => events.add('navigate'),
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['insert-start']);
      allowInsert.complete();
      await operation;
      expect(events, <String>['insert-start', 'insert', 'navigate']);
    });

    test('an insert failure never opens the form or attempts deletion',
        () async {
      final Object failure = StateError('mocked database unavailable');
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        insertError: failure,
      );
      bool navigated = false;

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistBeforeNavigation(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[_part(0)],
          recordingPartDurations: const <int>[5],
          environment: 'development',
          navigate: (_) => navigated = true,
        ),
        throwsA(same(failure)),
      );

      expect(navigated, isFalse);
      expect(persistence.insertCalls, 1);
      expect(persistence.deleteCalls, 0);
    });

    test('an ambiguous mocked commit keeps media DB-owned and never navigates',
        () async {
      const RecordingDraftPersistenceException failure =
          RecordingDraftPersistenceException(
        'mocked lost commit acknowledgement',
        commitState: RecordingDraftCommitState.mayHaveCommitted,
      );
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        insertError: failure,
      );
      bool navigated = false;

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistBeforeNavigation(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[_part(0)],
          recordingPartDurations: const <int>[5],
          environment: 'development',
          navigate: (_) => navigated = true,
        ),
        throwsA(same(failure)),
      );

      expect(failure.mayHaveCommitted, isTrue);
      expect(navigated, isFalse);
      expect(persistence.deleteCalls, 0);
    });

    test('a navigation failure leaves the durable draft recoverable', () async {
      final Object navigationFailure = StateError('mocked navigator failed');
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();
      RecordingDraftHandoff? durableDraft;

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistBeforeNavigation(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[_part(0)],
          recordingPartDurations: const <int>[5],
          environment: 'development',
          navigate: (RecordingDraftHandoff handoff) {
            durableDraft = handoff;
            throw navigationFailure;
          },
        ),
        throwsA(same(navigationFailure)),
      );

      expect(persistence.insertCalls, 1);
      expect(durableDraft?.recording.id, 41);
      expect(persistence.deleteCalls, 0);
      await durableDraft!.discard();
      expect(persistence.deletedIds, <int>[41]);
    });

    test('the form receives an immutable part collection', () async {
      final RecordingDraftHandoff handoff = await _persistOne();

      expect(
        () => handoff.recordingParts.add(_readyPart(99)),
        throwsUnsupportedError,
      );
    });

    test('metadata updates go through the injected mocked persistence',
        () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();
      final RecordingDraftHandoff handoff =
          await _persistOne(persistence: persistence);
      final Dialect dialect = Dialect(
        id: null,
        recordingId: 41,
        startDate: _start,
        endDate: _start.add(const Duration(seconds: 2)),
        userGuessDialect: 'xC',
      );

      handoff.recording.note = 'edited while form is open';
      await handoff.updateMetadata(<Dialect>[dialect]);

      expect(persistence.updateCalls, 1);
      expect(persistence.updatedRecording, same(handoff.recording));
      expect(persistence.updatedDialects, hasLength(1));
      expect(persistence.updatedDialects!.single, same(dialect));
      expect(handoff.recording.captureReviewed, isTrue);
    });

    test('discard deletes durable rows and owned files exactly once', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();
      final RecordingDraftHandoff handoff =
          await _persistOne(persistence: persistence);

      await handoff.discard();
      await handoff.discard();

      expect(handoff.isDiscarded, isTrue);
      expect(persistence.deleteCalls, 1);
      expect(persistence.deletedIds, <int>[41]);
    });

    test('a mocked deletion failure leaves discard retryable', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        deleteFailuresRemaining: 1,
      );
      final RecordingDraftHandoff handoff =
          await _persistOne(persistence: persistence);

      await expectLater(handoff.discard(), throwsStateError);
      expect(handoff.isDiscarded, isFalse);
      await handoff.discard();

      expect(handoff.isDiscarded, isTrue);
      expect(persistence.deleteCalls, 2);
    });

    test('cannot update a discarded draft', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();
      final RecordingDraftHandoff handoff =
          await _persistOne(persistence: persistence);
      await handoff.discard();

      await expectLater(
        handoff.updateMetadata(const <Dialect>[]),
        throwsStateError,
      );
      expect(persistence.updateCalls, 0);
    });

    test('fails closed if mocked persistence does not durably mark reviewed',
        () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        markReviewedOnUpdate: false,
      );
      final RecordingDraftHandoff handoff =
          await _persistOne(persistence: persistence);

      await expectLater(
        handoff.updateMetadata(const <Dialect>[]),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('did not mark'),
          ),
        ),
      );

      expect(handoff.recording.captureReviewed, isFalse);
    });

    for (final (String name, String filepath, String environment)
        in <(String, String, String)>[
      ('empty final path', ' ', 'development'),
      ('empty environment', '/mock/final.wav', ' '),
    ]) {
      test('$name fails before touching persistence', () async {
        final _FakeDraftPersistence persistence = _FakeDraftPersistence();

        await expectLater(
          RecordingDraftHandoffCoordinator(persistence: persistence)
              .persistCapture(
            filepath: filepath,
            startTime: _start,
            recordingParts: <RecordingPartUnready>[_part(0)],
            recordingPartDurations: const <int>[5],
            environment: environment,
          ),
          throwsA(isA<RecordingDraftHandoffException>()),
        );

        expect(persistence.insertCalls, 0);
      });
    }

    test('zero parts fails before touching persistence', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistCapture(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: const <RecordingPartUnready>[],
          recordingPartDurations: const <int>[],
          environment: 'development',
        ),
        throwsA(isA<RecordingDraftHandoffException>()),
      );

      expect(persistence.insertCalls, 0);
    });

    test('part/duration count mismatch fails before persistence', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistCapture(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[_part(0), _part(1)],
          recordingPartDurations: const <int>[5],
          environment: 'development',
        ),
        throwsA(
          isA<RecordingDraftHandoffException>().having(
            (RecordingDraftHandoffException error) => error.message,
            'message',
            contains('Expected 2'),
          ),
        ),
      );

      expect(persistence.insertCalls, 0);
    });

    test('negative part duration fails before persistence', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistCapture(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[_part(0)],
          recordingPartDurations: const <int>[-1],
          environment: 'development',
        ),
        throwsA(
          isA<RecordingDraftHandoffException>().having(
            (RecordingDraftHandoffException error) => error.message,
            'message',
            contains('negative'),
          ),
        ),
      );

      expect(persistence.insertCalls, 0);
    });

    test('an incomplete part fails before persistence', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();
      final RecordingPartUnready incomplete = _part(0)..endTime = null;

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistCapture(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[incomplete],
          recordingPartDurations: const <int>[5],
          environment: 'development',
        ),
        throwsA(
          isA<RecordingDraftHandoffException>()
              .having((error) => error.cause, 'cause', isNotNull),
        ),
      );

      expect(persistence.insertCalls, 0);
    });

    test('duplicate part paths fail before persistence', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence();

      await expectLater(
        RecordingDraftHandoffCoordinator(persistence: persistence)
            .persistCapture(
          filepath: '/mock/final.wav',
          startTime: _start,
          recordingParts: <RecordingPartUnready>[
            _part(0, path: '/mock/repeated.raw'),
            _part(1, path: '/mock/repeated.raw'),
          ],
          recordingPartDurations: const <int>[5, 6],
          environment: 'development',
        ),
        throwsA(
          isA<RecordingDraftHandoffException>().having(
            (RecordingDraftHandoffException error) => error.message,
            'message',
            contains('duplicate path'),
          ),
        ),
      );

      expect(persistence.insertCalls, 0);
    });
  });

  group('mocked persistence identity contract', () {
    for (final (
          String name,
          void Function(Recording, List<RecordingPart>) corrupt,
          Matcher message,
        ) in <(
      String,
      void Function(Recording, List<RecordingPart>),
      Matcher,
    )>[
      (
        'non-positive parent id',
        (Recording recording, _) => recording.id = 0,
        contains('positive local id'),
      ),
      (
        'returned/parent id mismatch',
        (Recording recording, _) => recording.id = 99,
        contains('does not match'),
      ),
      (
        'missing parent upload key',
        (Recording recording, _) => recording.uploadKey = ' ',
        contains('no durable upload key'),
      ),
      (
        'part bound to another parent',
        (_, List<RecordingPart> parts) => parts.first.recordingId = 99,
        contains('another recording'),
      ),
      (
        'non-positive child id',
        (_, List<RecordingPart> parts) => parts.first.id = 0,
        contains('positive local id'),
      ),
      (
        'missing child upload key',
        (_, List<RecordingPart> parts) => parts.first.uploadKey = '',
        contains('no durable upload key'),
      ),
    ]) {
      test('rejects $name before navigation', () async {
        final _FakeDraftPersistence persistence = _FakeDraftPersistence(
          afterIdentityAssigned: corrupt,
        );
        bool navigated = false;

        await expectLater(
          RecordingDraftHandoffCoordinator(persistence: persistence)
              .persistBeforeNavigation(
            filepath: '/mock/final.wav',
            startTime: _start,
            recordingParts: <RecordingPartUnready>[_part(0)],
            recordingPartDurations: const <int>[5],
            environment: 'development',
            navigate: (_) => navigated = true,
          ),
          throwsA(isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            message,
          )),
        );

        expect(navigated, isFalse);
      });
    }

    test('rejects duplicate child ids before navigation', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        afterIdentityAssigned: (_, List<RecordingPart> parts) {
          parts.last.id = parts.first.id;
        },
      );

      await expectLater(
        _persistTwo(persistence),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('duplicate ids'),
          ),
        ),
      );
    });

    test('rejects duplicate child upload keys before navigation', () async {
      final _FakeDraftPersistence persistence = _FakeDraftPersistence(
        afterIdentityAssigned: (_, List<RecordingPart> parts) {
          parts.last.uploadKey = parts.first.uploadKey;
        },
      );

      await expectLater(
        _persistTwo(persistence),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('duplicate upload keys'),
          ),
        ),
      );
    });

    group('cold-start draft recovery (mocked DB, no API)', () {
      test('rehydrates an intact unreviewed aggregate and can finish review',
          () async {
        final RecordingDraftHandoff persisted = await _persistOne();
        final _FakeDraftPersistence recoveryPersistence =
            _FakeDraftPersistence();

        final RecordingDraftHandoff recovered =
            RecordingDraftHandoff.restorePersisted(
          recording: persisted.recording,
          recordingParts: persisted.recordingParts,
          persistence: recoveryPersistence,
        );

        expect(recovered.recording.captureReviewed, isFalse);
        expect(recovered.recordingParts, hasLength(1));
        await recovered.updateMetadata(const <Dialect>[]);
        expect(recoveryPersistence.updateCalls, 1);
        expect(recovered.recording.captureReviewed, isTrue);
      });

      for (final (
        String label,
        void Function(Recording, RecordingPart) corrupt,
        Matcher message,
      ) scenario in <(
        String,
        void Function(Recording, RecordingPart),
        Matcher,
      )>[
        (
          'already reviewed parent',
          (Recording recording, _) => recording.captureReviewed = true,
          contains('not an interrupted draft'),
        ),
        (
          'parent whose upload started',
          (Recording recording, _) => recording.parentUploadAttempted = true,
          contains('already entered an upload'),
        ),
        (
          'incomplete part aggregate',
          (Recording recording, _) => recording.partCount = 2,
          contains('incomplete part aggregate'),
        ),
        (
          'part whose upload started',
          (_, RecordingPart part) => part.uploadAttempted = true,
          contains('already entered an upload'),
        ),
        (
          'missing completed audio path',
          (Recording recording, _) => recording.path = ' ',
          contains('no completed audio path'),
        ),
        (
          'missing part audio path',
          (_, RecordingPart part) => part.path = '',
          contains('no audio path'),
        ),
      ]) {
        test('rejects ${scenario.$1}', () async {
          final RecordingDraftHandoff persisted = await _persistOne();
          scenario.$2(
            persisted.recording,
            persisted.recordingParts.single,
          );

          expect(
            () => RecordingDraftHandoff.restorePersisted(
              recording: persisted.recording,
              recordingParts: persisted.recordingParts,
              persistence: _FakeDraftPersistence(),
            ),
            throwsA(
              isA<StateError>().having(
                (StateError error) => error.message,
                'message',
                scenario.$3,
              ),
            ),
          );
        });
      }
    });
  });
}

final DateTime _start = DateTime.utc(2026, 7, 18, 20);

RecordingPartUnready _part(
  int index, {
  String? path,
}) {
  final DateTime start = _start.add(Duration(seconds: index * 10));
  return RecordingPartUnready(
    startTime: start,
    endTime: start.add(const Duration(seconds: 5)),
    gpsLatitudeStart: 50.0755 + index / 1000,
    gpsLatitudeEnd: 50.0756 + index / 1000,
    gpsLongitudeStart: 14.4378 + index / 1000,
    gpsLongitudeEnd: 14.4379 + index / 1000,
    path: path ?? '/mock/part-$index.raw',
  );
}

RecordingPart _readyPart(int index) {
  final DateTime start = _start.add(Duration(seconds: index * 10));
  return RecordingPart(
    id: index + 100,
    recordingId: 41,
    startTime: start,
    endTime: start.add(const Duration(seconds: 5)),
    gpsLatitudeStart: 50,
    gpsLatitudeEnd: 50,
    gpsLongitudeStart: 14,
    gpsLongitudeEnd: 14,
    path: '/mock/ready-$index.raw',
  );
}

Future<RecordingDraftHandoff> _persistOne({
  _FakeDraftPersistence? persistence,
}) {
  return RecordingDraftHandoffCoordinator(
    persistence: persistence ?? _FakeDraftPersistence(),
  ).persistCapture(
    filepath: '/mock/final.wav',
    startTime: _start,
    recordingParts: <RecordingPartUnready>[_part(0)],
    recordingPartDurations: const <int>[5],
    environment: 'development',
  );
}

Future<RecordingDraftHandoff> _persistTwo(
  _FakeDraftPersistence persistence,
) {
  return RecordingDraftHandoffCoordinator(
    persistence: persistence,
  ).persistCapture(
    filepath: '/mock/final.wav',
    startTime: _start,
    recordingParts: <RecordingPartUnready>[_part(0), _part(1)],
    recordingPartDurations: const <int>[5, 5],
    environment: 'development',
  );
}

class _FakeDraftPersistence implements RecordingDraftPersistence {
  _FakeDraftPersistence({
    this.events,
    this.beforeInsert,
    this.insertError,
    this.deleteFailuresRemaining = 0,
    this.afterIdentityAssigned,
    this.markReviewedOnUpdate = true,
  });

  final List<String>? events;
  final Future<void> Function()? beforeInsert;
  final Object? insertError;
  int deleteFailuresRemaining;
  final void Function(Recording, List<RecordingPart>)? afterIdentityAssigned;
  final bool markReviewedOnUpdate;

  int insertCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  List<Dialect>? insertedDialects;
  ({int? userId, String? mail})? ownerBeforeInsert;
  Recording? updatedRecording;
  List<Dialect>? updatedDialects;
  final List<int> deletedIds = <int>[];

  @override
  Future<int> insertDraft(
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
  ) async {
    insertCalls++;
    if (beforeInsert != null) {
      events?.add('insert-start');
      await beforeInsert!();
    }
    events?.add('insert');
    final Object? failure = insertError;
    if (failure != null) throw failure;

    insertedDialects = List<Dialect>.from(dialects);
    ownerBeforeInsert = (userId: recording.userId, mail: recording.mail);
    recording
      ..id = 41
      ..userId = 7
      ..mail = 'mock@example.test'
      ..uploadKey = 'recording-upload-41';
    for (int index = 0; index < parts.length; index++) {
      parts[index]
        ..id = index + 101
        ..recordingId = 41
        ..uploadKey = 'part-upload-${index + 101}';
    }
    afterIdentityAssigned?.call(recording, parts);
    return 41;
  }

  @override
  Future<void> updateDraft(
    Recording recording,
    List<Dialect> dialects,
  ) async {
    updateCalls++;
    updatedRecording = recording;
    updatedDialects = List<Dialect>.from(dialects);
    if (markReviewedOnUpdate) {
      recording.captureReviewed = true;
    }
  }

  @override
  Future<void> deleteDraft(int recordingId) async {
    deleteCalls++;
    if (deleteFailuresRemaining > 0) {
      deleteFailuresRemaining--;
      throw StateError('mocked delete failed');
    }
    deletedIds.add(recordingId);
  }
}
