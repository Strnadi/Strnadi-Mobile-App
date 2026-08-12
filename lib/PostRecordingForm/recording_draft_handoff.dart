import 'dart:async';

import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/dialects/ModelHandler.dart';

/// Persistence boundary for the recorder-to-form handoff.
///
/// Tests provide an in-memory fake. The production implementation below is the
/// only place where this handoff workflow reaches the SQLite repository.
abstract interface class RecordingDraftPersistence {
  Future<int> insertDraft(
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
  );

  Future<void> updateDraft(
    Recording recording,
    List<Dialect> dialects,
  );

  Future<void> deleteDraft(int recordingId);
}

class DatabaseRecordingDraftPersistence implements RecordingDraftPersistence {
  const DatabaseRecordingDraftPersistence();

  @override
  Future<int> insertDraft(
    Recording recording,
    List<RecordingPart> parts,
    List<Dialect> dialects,
  ) {
    return DatabaseNew.insertRecordingDraft(recording, parts, dialects);
  }

  @override
  Future<void> updateDraft(
    Recording recording,
    List<Dialect> dialects,
  ) {
    return DatabaseNew.updateRecordingDraft(recording, dialects);
  }

  @override
  Future<void> deleteDraft(int recordingId) {
    return DatabaseNew.deleteRecordingFromCache(recordingId);
  }
}

/// A durable aggregate which may safely be handed from the recorder to the
/// metadata form.
///
/// Reaching this type means the parent and every recording part were committed
/// together and have stable local/upload identities. If the process terminates
/// while the form is open, SQLite still owns the media paths and the recording
/// remains recoverable from local recordings.
class RecordingDraftHandoff {
  RecordingDraftHandoff._({
    required this.recording,
    required List<RecordingPart> recordingParts,
    required RecordingDraftPersistence persistence,
  })  : recordingParts = List<RecordingPart>.unmodifiable(recordingParts),
        _persistence = persistence;

  final Recording recording;
  final List<RecordingPart> recordingParts;
  final RecordingDraftPersistence _persistence;

  bool _discarded = false;

  bool get isDiscarded => _discarded;

  /// Rehydrates an interrupted pre-upload draft from already persisted rows.
  ///
  /// The recovery path is deliberately strict: only an intact, unreviewed
  /// aggregate whose upload has never started may return to the metadata form.
  /// Anything ambiguous remains non-uploadable.
  factory RecordingDraftHandoff.restorePersisted({
    required Recording recording,
    required List<RecordingPart> recordingParts,
    RecordingDraftPersistence persistence =
        const DatabaseRecordingDraftPersistence(),
  }) {
    final int recordingId = _requirePositiveId(
      recording.id,
      'persisted recording',
    );
    _validatePersistedAggregate(
      recordingId: recordingId,
      recording: recording,
      parts: recordingParts,
    );
    _validateRecoverableDraft(
      recording: recording,
      parts: recordingParts,
    );
    return RecordingDraftHandoff._(
      recording: recording,
      recordingParts: recordingParts,
      persistence: persistence,
    );
  }

  Future<void> updateMetadata(List<Dialect> dialects) async {
    if (_discarded) {
      throw StateError('A discarded recording draft cannot be updated.');
    }
    await _persistence.updateDraft(recording, dialects);
    if (!recording.captureReviewed) {
      throw StateError(
        'The persistence layer did not mark the recording as reviewed.',
      );
    }
  }

  /// Removes the durable rows and their owned media through the same
  /// persistence boundary. A failed deletion remains retryable.
  Future<void> discard() async {
    if (_discarded) return;
    final int recordingId = _requirePositiveId(
      recording.id,
      'recording draft',
    );
    await _persistence.deleteDraft(recordingId);
    _discarded = true;
  }
}

/// Builds and durably commits the recording aggregate before navigation.
class RecordingDraftHandoffCoordinator {
  const RecordingDraftHandoffCoordinator({
    required RecordingDraftPersistence persistence,
  }) : _persistence = persistence;

  factory RecordingDraftHandoffCoordinator.database() {
    return const RecordingDraftHandoffCoordinator(
      persistence: DatabaseRecordingDraftPersistence(),
    );
  }

  final RecordingDraftPersistence _persistence;

  Future<RecordingDraftHandoff> persistCapture({
    required String filepath,
    required DateTime startTime,
    required List<RecordingPartUnready> recordingParts,
    required List<int> recordingPartDurations,
    required String environment,
    String device = '',
  }) async {
    final String durablePath = filepath.trim();
    if (durablePath.isEmpty) {
      throw const RecordingDraftHandoffException(
        'The completed recording has no file path.',
      );
    }
    final String durableEnvironment = environment.trim();
    if (durableEnvironment.isEmpty) {
      throw const RecordingDraftHandoffException(
        'The completed recording has no environment.',
      );
    }
    if (recordingParts.isEmpty) {
      throw const RecordingDraftHandoffException(
        'The completed recording has no parts.',
      );
    }
    if (recordingParts.length != recordingPartDurations.length) {
      throw RecordingDraftHandoffException(
        'Expected ${recordingParts.length} part durations but received '
        '${recordingPartDurations.length}.',
      );
    }

    final List<RecordingPart> readyParts = <RecordingPart>[];
    final Set<String> paths = <String>{};
    for (int index = 0; index < recordingParts.length; index++) {
      final int duration = recordingPartDurations[index];
      if (duration < 0) {
        throw RecordingDraftHandoffException(
          'Recording part $index has a negative duration.',
        );
      }

      late final RecordingPart part;
      try {
        part = RecordingPart.fromUnready(recordingParts[index]);
      } catch (error) {
        throw RecordingDraftHandoffException(
          'Recording part $index is incomplete.',
          cause: error,
        );
      }
      final String partPath = (part.path ?? '').trim();
      if (!paths.add(partPath)) {
        throw RecordingDraftHandoffException(
          'Recording parts contain the duplicate path $partPath.',
        );
      }
      part.length = duration;
      readyParts.add(part);
    }

    final Recording recording = Recording(
      createdAt: startTime.isBefore(readyParts.first.startTime)
          ? startTime
          : readyParts.first.startTime,
      mail: '',
      estimatedBirdsCount: 1,
      device: device,
      byApp: true,
      note: '',
      path: durablePath,
      downloaded: true,
      captureReviewed: false,
      partCount: readyParts.length,
      env: durableEnvironment,
      totalSeconds: recordingPartDurations
          .fold<int>(
            0,
            (int total, int duration) => total + duration,
          )
          .toDouble(),
    );

    final int recordingId = await _persistence.insertDraft(
      recording,
      readyParts,
      const <Dialect>[],
    );
    recording.id ??= recordingId;
    for (final RecordingPart part in readyParts) {
      part.recordingId ??= recordingId;
    }
    _validatePersistedAggregate(
      recordingId: recordingId,
      recording: recording,
      parts: readyParts,
    );

    return RecordingDraftHandoff._(
      recording: recording,
      recordingParts: readyParts,
      persistence: _persistence,
    );
  }

  /// Convenience wrapper which structurally prevents opening the form before
  /// the durable insert has completed.
  Future<void> persistBeforeNavigation({
    required String filepath,
    required DateTime startTime,
    required List<RecordingPartUnready> recordingParts,
    required List<int> recordingPartDurations,
    required String environment,
    String device = '',
    required FutureOr<void> Function(RecordingDraftHandoff handoff) navigate,
  }) async {
    final RecordingDraftHandoff handoff = await persistCapture(
      filepath: filepath,
      startTime: startTime,
      recordingParts: recordingParts,
      recordingPartDurations: recordingPartDurations,
      environment: environment,
      device: device,
    );
    await navigate(handoff);
  }
}

class RecordingDraftHandoffException implements Exception {
  const RecordingDraftHandoffException(
    this.message, {
    this.cause,
  });

  final String message;
  final Object? cause;

  @override
  String toString() {
    final Object? nestedCause = cause;
    return nestedCause == null
        ? 'RecordingDraftHandoffException: $message'
        : 'RecordingDraftHandoffException: $message ($nestedCause)';
  }
}

void _validatePersistedAggregate({
  required int recordingId,
  required Recording recording,
  required List<RecordingPart> parts,
}) {
  final int durableRecordingId =
      _requirePositiveId(recordingId, 'persisted recording');
  final int aggregateRecordingId =
      _requirePositiveId(recording.id, 'persisted recording');
  if (aggregateRecordingId != durableRecordingId) {
    throw StateError(
      'The persisted recording identity does not match the returned id.',
    );
  }
  if ((recording.uploadKey ?? '').trim().isEmpty) {
    throw StateError('The persisted recording has no durable upload key.');
  }

  final Set<int> partIds = <int>{};
  final Set<String> partUploadKeys = <String>{};
  for (final RecordingPart part in parts) {
    if (part.recordingId != durableRecordingId) {
      throw StateError(
        'A persisted recording part belongs to another recording.',
      );
    }
    final int partId = _requirePositiveId(part.id, 'persisted recording part');
    if (!partIds.add(partId)) {
      throw StateError('Persisted recording parts contain duplicate ids.');
    }
    final String uploadKey = (part.uploadKey ?? '').trim();
    if (uploadKey.isEmpty) {
      throw StateError(
        'A persisted recording part has no durable upload key.',
      );
    }
    if (!partUploadKeys.add(uploadKey)) {
      throw StateError(
        'Persisted recording parts contain duplicate upload keys.',
      );
    }
  }
}

void _validateRecoverableDraft({
  required Recording recording,
  required List<RecordingPart> parts,
}) {
  if (recording.captureReviewed) {
    throw StateError('A reviewed recording is not an interrupted draft.');
  }
  if ((recording.path ?? '').trim().isEmpty) {
    throw StateError('The interrupted draft has no completed audio path.');
  }
  if (recording.env.trim().isEmpty) {
    throw StateError('The interrupted draft has no environment.');
  }
  if (recording.sent ||
      recording.sending ||
      recording.BEId != null ||
      recording.parentUploadAttempted ||
      (recording.uploadLease ?? '').trim().isNotEmpty) {
    throw StateError('The interrupted draft has already entered an upload.');
  }
  if (parts.isEmpty || recording.partCount != parts.length) {
    throw StateError('The interrupted draft has an incomplete part aggregate.');
  }

  for (final RecordingPart part in parts) {
    if ((part.path ?? '').trim().isEmpty) {
      throw StateError('An interrupted recording part has no audio path.');
    }
    if (!part.startTime.isBefore(part.endTime)) {
      throw StateError('An interrupted recording part has invalid timestamps.');
    }
    if ((part.length ?? -1) < 0) {
      throw StateError('An interrupted recording part has no valid duration.');
    }
    if (part.sent ||
        part.sending ||
        part.BEId != null ||
        part.backendRecordingId != null ||
        part.uploadAttempted) {
      throw StateError(
        'An interrupted recording part has already entered an upload.',
      );
    }
  }
}

int _requirePositiveId(Object? value, String label) {
  final int? id = value is int ? value : int.tryParse(value?.toString() ?? '');
  if (id == null || id <= 0) {
    throw StateError('The $label has no positive local id.');
  }
  return id;
}
