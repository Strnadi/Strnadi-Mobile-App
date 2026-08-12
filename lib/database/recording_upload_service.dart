import 'dart:async';

import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/exceptions.dart';

typedef RecordingUploadProgress = void Function(
  int partId,
  int sent,
  int total,
);
typedef RecordingPartUploadProgress = void Function(int sent, int total);

bool _isInvalidUploadLeaseId(String leaseId) {
  final String normalized = leaseId.trim().toLowerCase();
  return normalized.isEmpty || normalized.startsWith('delete:');
}

class RecordingUploadSession {
  const RecordingUploadSession({
    required this.userId,
    required this.accessToken,
    required this.logicalSessionId,
    required this.environment,
    required this.backendHost,
    this.accountEmail,
    this.deviceId,
  });

  final String userId;
  final String accessToken;
  final String logicalSessionId;
  final String environment;
  final String backendHost;
  final String? accountEmail;
  final String? deviceId;
}

abstract interface class RecordingUploadSessionProvider {
  Future<RecordingUploadSession?> capture();

  Future<bool> isCurrent(RecordingUploadSession session);
}

abstract interface class RecordingUploadPolicy {
  Future<bool> canUpload();
}

abstract interface class RecordingUploadFileProbe {
  Future<RecordingUploadFileFingerprint?> inspect(String path);
}

final class RecordingUploadFileFingerprint {
  const RecordingUploadFileFingerprint({
    required this.sha256,
    required this.byteLength,
  });

  final String sha256;
  final int byteLength;

  bool matches(RecordingUploadFileFingerprint other) {
    return byteLength == other.byteLength &&
        sha256.toLowerCase() == other.sha256.toLowerCase();
  }
}

/// Captures an upload session only from the atomic activated-auth marker.
///
/// The push token is optional metadata. Its storage read must neither run for
/// logged-out/unverified users nor prevent a valid recording upload when the
/// optional keychain entry is temporarily unavailable.
Future<RecordingUploadSession?> captureActivatedRecordingUploadSession({
  required Future<ActivatedAuthSessionSnapshot?> Function()
      captureActivatedSession,
  required Future<String?> Function() readOptionalDeviceId,
  required String environment,
  required String backendHost,
}) async {
  final ActivatedAuthSessionSnapshot? activated =
      await captureActivatedSession();
  if (activated == null || !activated.verified) return null;

  String? deviceId;
  try {
    deviceId = await readOptionalDeviceId();
  } catch (_) {
    deviceId = null;
  }
  return RecordingUploadSession(
    userId: activated.userId,
    accessToken: activated.accessToken,
    logicalSessionId: activated.sessionId,
    environment: environment,
    accountEmail: activated.subject,
    deviceId: deviceId,
    backendHost: backendHost,
  );
}

abstract interface class RecordingUploadApi {
  Future<int> createRecording({
    required Recording recording,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
  });

  Future<int> uploadRecordingPart({
    required RecordingPart part,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
    RecordingPartUploadProgress? onProgress,
  });

  Future<bool> recordingPartExists({
    required RecordingPart part,
    required RecordingUploadSession session,
  });
}

abstract interface class RecordingUploadStore {
  Future<bool> tryAcquireRecording(int recordingId, String leaseId);

  Future<void> renewRecording(int recordingId, String leaseId);

  Future<Recording?> loadRecording(int recordingId, String leaseId);

  Future<List<RecordingPart>> loadRecordingParts(
    int recordingId,
    String leaseId,
  );

  Future<void> saveRecording(Recording recording, String leaseId);

  Future<bool> tryAcquireRecordingPart(
    int recordingId,
    int partId,
    String leaseId,
  );

  Future<void> markRecordingPartAttempted(
    int recordingId,
    int partId,
    String leaseId,
  );

  Future<void> freezeRecordingPartContent(
    int recordingId,
    int partId,
    RecordingUploadFileFingerprint fingerprint,
    String leaseId,
  );

  Future<void> saveRecordingPart(
    int recordingId,
    RecordingPart part,
    String leaseId,
  );

  Future<void> completeRecording(
    Recording recording,
    String leaseId, {
    required int expectedPartsCount,
  });

  /// Releases only transient workflow state owned by [leaseId].
  ///
  /// Implementations must not persist an in-memory [Recording] snapshot here:
  /// the caller may have optimistically mutated it immediately before a failed
  /// completion commit.
  Future<void> releaseRecording(int recordingId, String leaseId);
}

enum RecordingUploadStatus {
  uploaded,
  alreadySent,
  busy,
  deferred,
}

class RecordingUploadResult {
  const RecordingUploadResult({
    required this.status,
    this.recording,
    this.reason,
  });

  final RecordingUploadStatus status;
  final Recording? recording;
  final String? reason;
}

class RecordingWorkflowLeaseContext {
  RecordingWorkflowLeaseContext._({
    required this.recording,
    required this.session,
    required Future<void> Function() renew,
  }) : _renew = renew;

  final Recording recording;
  final RecordingUploadSession session;
  final Future<void> Function() _renew;

  Future<void> renew() => _renew();
}

class RecordingWorkflowLeaseService {
  const RecordingWorkflowLeaseService({
    required RecordingUploadStore store,
    required RecordingUploadSessionProvider sessions,
    Duration leaseHeartbeatInterval = const Duration(minutes: 1),
  })  : _store = store,
        _sessions = sessions,
        _leaseHeartbeatInterval = leaseHeartbeatInterval;

  final RecordingUploadStore _store;
  final RecordingUploadSessionProvider _sessions;
  final Duration _leaseHeartbeatInterval;

  Future<T> run<T>({
    required int recordingId,
    required String leaseId,
    required Future<T> Function(RecordingWorkflowLeaseContext context)
        operation,
  }) async {
    if (recordingId <= 0 || _isInvalidUploadLeaseId(leaseId)) {
      throw const RecordingUploadValidationException(
        'A workflow lease requires valid, non-reserved identifiers.',
      );
    }
    if (_leaseHeartbeatInterval <= Duration.zero) {
      throw ArgumentError.value(
        _leaseHeartbeatInterval,
        'leaseHeartbeatInterval',
        'must be greater than zero',
      );
    }

    final RecordingUploadSession? session = await _sessions.capture();
    if (session == null) {
      throw const RecordingUploadSessionChangedException();
    }
    validateRecordingUploadSession(session);

    bool acquired = false;
    bool acquisitionAttempted = false;
    bool acquisitionOutcomeKnown = false;
    Timer? heartbeatTimer;
    Future<void>? pendingHeartbeat;
    Object? heartbeatFailure;
    StackTrace? heartbeatFailureStackTrace;
    bool heartbeatLeaseLost = false;
    Object? failure;
    StackTrace? failureStackTrace;
    T? result;

    Future<void> renewHeartbeat() async {
      if (heartbeatLeaseLost) {
        Error.throwWithStackTrace(
          heartbeatFailure!,
          heartbeatFailureStackTrace!,
        );
      }

      Future<void>? heartbeat = pendingHeartbeat;
      if (heartbeat == null) {
        late final Future<void> scheduled;
        scheduled = (() async {
          try {
            try {
              // Keep ownership alive even when the captured login has just
              // changed. The operation must fail, but deletion must not
              // overlap an already-running remote request while it unwinds.
              await _store.renewRecording(recordingId, leaseId);
            } catch (error, stackTrace) {
              heartbeatLeaseLost = true;
              heartbeatFailure ??= error;
              heartbeatFailureStackTrace ??= stackTrace;
              return;
            }
            try {
              if (!await _sessions.isCurrent(session)) {
                throw const RecordingUploadSessionChangedException();
              }
            } catch (error, stackTrace) {
              heartbeatFailure ??= error;
              heartbeatFailureStackTrace ??= stackTrace;
            }
          } finally {
            if (identical(pendingHeartbeat, scheduled)) {
              pendingHeartbeat = null;
            }
          }
        })();
        pendingHeartbeat = scheduled;
        heartbeat = scheduled;
      }

      await heartbeat;
      if (heartbeatFailure != null) {
        Error.throwWithStackTrace(
          heartbeatFailure!,
          heartbeatFailureStackTrace!,
        );
      }
    }

    void scheduleHeartbeat() {
      if (pendingHeartbeat != null || heartbeatLeaseLost) return;
      unawaited(renewHeartbeat().catchError((Object _) {}));
    }

    try {
      acquisitionAttempted = true;
      final bool acquisitionResult =
          await _store.tryAcquireRecording(recordingId, leaseId);
      acquisitionOutcomeKnown = true;
      acquired = acquisitionResult;
      if (!acquired) {
        throw UploadException(
          'Recording is busy with another upload or deletion workflow.',
          409,
        );
      }
      final Recording? recording =
          await _store.loadRecording(recordingId, leaseId);
      if (recording == null) {
        throw const RecordingUploadValidationException(
          'Recording disappeared after the workflow lease was acquired.',
        );
      }
      if (recording.id != recordingId) {
        throw const RecordingUploadValidationException(
          'Loaded recording does not match the acquired workflow lease.',
        );
      }
      if (!recording.captureReviewed) {
        throw const RecordingUploadValidationException(
          'Recording capture has not been reviewed.',
        );
      }
      validateRecordingSessionBinding(recording, session);
      if (!await _sessions.isCurrent(session)) {
        throw const RecordingUploadSessionChangedException();
      }

      heartbeatTimer = Timer.periodic(
        _leaseHeartbeatInterval,
        (_) => scheduleHeartbeat(),
      );
      result = await operation(
        RecordingWorkflowLeaseContext._(
          recording: recording,
          session: session,
          renew: renewHeartbeat,
        ),
      );
      // Fast operations may finish before the periodic timer fires. Renewing
      // here verifies both lease ownership and the captured logical session
      // before reporting success.
      await renewHeartbeat();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    heartbeatTimer?.cancel();
    final Future<void>? heartbeat = pendingHeartbeat;
    if (heartbeat != null) {
      await heartbeat;
    }
    if (failure == null && heartbeatFailure != null) {
      failure = heartbeatFailure;
      failureStackTrace = heartbeatFailureStackTrace;
    }

    final bool acquisitionMayHaveCommitted =
        acquisitionAttempted && !acquisitionOutcomeKnown;
    if (acquired || acquisitionMayHaveCommitted) {
      try {
        await _store.releaseRecording(recordingId, leaseId);
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
    return result as T;
  }
}

class RecordingUploadValidationException implements Exception {
  const RecordingUploadValidationException(this.message);

  final String message;

  @override
  String toString() => 'RecordingUploadValidationException: $message';
}

class RecordingUploadSessionChangedException implements Exception {
  const RecordingUploadSessionChangedException();

  @override
  String toString() => 'RecordingUploadSessionChangedException';
}

void validateRecordingSessionBinding(
  Recording recording,
  RecordingUploadSession session,
) {
  if (recording.env != session.environment) {
    throw const RecordingUploadSessionChangedException();
  }

  final int? ownerId = recording.userId;
  final int sessionUserId = int.parse(session.userId.trim());
  if (ownerId != null && ownerId != sessionUserId) {
    throw const RecordingUploadSessionChangedException();
  }

  final String? ownerEmail = recording.mail?.trim();
  if (ownerEmail != null && ownerEmail.isNotEmpty) {
    final String? sessionEmail = session.accountEmail?.trim();
    if (sessionEmail == null ||
        sessionEmail.isEmpty ||
        sessionEmail.toLowerCase() != ownerEmail.toLowerCase()) {
      throw const RecordingUploadSessionChangedException();
    }
  }
}

void validateRecordingUploadSession(RecordingUploadSession session) {
  final int? userId = int.tryParse(session.userId.trim());
  if (userId == null ||
      userId <= 0 ||
      session.accessToken.trim().isEmpty ||
      session.logicalSessionId.trim().isEmpty ||
      session.environment.trim().isEmpty ||
      session.backendHost.trim().isEmpty) {
    throw const RecordingUploadSessionChangedException();
  }
}

class RecordingUploadService {
  RecordingUploadService({
    required RecordingUploadStore store,
    required RecordingUploadApi api,
    required RecordingUploadSessionProvider sessions,
    required RecordingUploadPolicy policy,
    required RecordingUploadFileProbe files,
    required String Function() newLeaseId,
    Duration leaseHeartbeatInterval = const Duration(minutes: 1),
  })  : _store = store,
        _api = api,
        _sessions = sessions,
        _policy = policy,
        _files = files,
        _newLeaseId = newLeaseId,
        _leaseHeartbeatInterval = leaseHeartbeatInterval {
    if (leaseHeartbeatInterval <= Duration.zero) {
      throw ArgumentError.value(
        leaseHeartbeatInterval,
        'leaseHeartbeatInterval',
        'must be greater than zero',
      );
    }
  }

  final RecordingUploadStore _store;
  final RecordingUploadApi _api;
  final RecordingUploadSessionProvider _sessions;
  final RecordingUploadPolicy _policy;
  final RecordingUploadFileProbe _files;
  final String Function() _newLeaseId;
  final Duration _leaseHeartbeatInterval;

  Future<RecordingUploadResult> send(
    int recordingId, {
    RecordingUploadProgress? onProgress,
  }) async {
    if (recordingId <= 0) {
      throw RecordingUploadValidationException(
        'Recording id must be a positive integer.',
      );
    }

    final String leaseId = _newLeaseId();
    if (_isInvalidUploadLeaseId(leaseId)) {
      throw const RecordingUploadValidationException(
        'Upload lease id must not be empty or use a reserved prefix.',
      );
    }

    Recording? recording;
    bool acquired = false;
    try {
      acquired = await _store.tryAcquireRecording(recordingId, leaseId);
      if (!acquired) {
        return const RecordingUploadResult(
          status: RecordingUploadStatus.busy,
          reason: 'Recording is already being uploaded.',
        );
      }

      recording = await _store.loadRecording(recordingId, leaseId);
      if (recording == null) {
        throw const RecordingUploadValidationException(
          'Recording was not found after acquiring its upload lease.',
        );
      }
      if (recording.id != recordingId) {
        throw const RecordingUploadValidationException(
          'Loaded recording does not match the acquired recording id.',
        );
      }
      if (!recording.captureReviewed) {
        await _store.releaseRecording(recordingId, leaseId);
        recording
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
        return RecordingUploadResult(
          status: RecordingUploadStatus.deferred,
          recording: recording,
          reason: 'Recording capture must be reviewed before upload.',
        );
      }
      final List<RecordingPart> parts =
          await _store.loadRecordingParts(recordingId, leaseId);
      _validateAggregate(recording, parts);
      final int expectedPartsCount = _expectedPartsCount(recording, parts);

      if (!await _policy.canUpload()) {
        await _store.releaseRecording(recordingId, leaseId);
        recording
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
        return RecordingUploadResult(
          status: RecordingUploadStatus.deferred,
          recording: recording,
          reason: 'Uploads are currently disabled by network policy.',
        );
      }

      final RecordingUploadSession? session = await _sessions.capture();
      if (session == null) {
        await _store.releaseRecording(recordingId, leaseId);
        recording
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
        return RecordingUploadResult(
          status: RecordingUploadStatus.deferred,
          recording: recording,
          reason: 'An authenticated session is required.',
        );
      }

      validateRecordingUploadSession(session);
      _validateRecordingSession(recording, session);
      await _ensureSessionCurrent(session);
      final String? sessionEmail = session.accountEmail?.trim();
      bool sessionBindingChanged = false;
      if (recording.mail == null || recording.mail!.trim().isEmpty) {
        if (sessionEmail == null || sessionEmail.isEmpty) {
          throw const RecordingUploadSessionChangedException();
        }
        recording.mail = sessionEmail;
        sessionBindingChanged = true;
      }
      final int sessionUserId = int.parse(session.userId.trim());
      if (recording.userId == null) {
        recording.userId = sessionUserId;
        sessionBindingChanged = true;
      }
      if (sessionBindingChanged) {
        await _store.saveRecording(recording, leaseId);
        await _ensureSessionCurrent(session);
      }

      if (recording.sent && _isCompletedAggregate(recording, parts)) {
        await _store.releaseRecording(recordingId, leaseId);
        recording
          ..sending = false
          ..uploadLease = null
          ..uploadLeaseUpdatedAt = null;
        return RecordingUploadResult(
          status: RecordingUploadStatus.alreadySent,
          recording: recording,
        );
      }
      if (recording.sent) {
        // A parent can only be considered sent when its complete persisted
        // aggregate proves it. Clear a stale optimistic flag before repair.
        recording.sent = false;
        await _store.saveRecording(recording, leaseId);
      }

      // Validate every part that is known to require a local upload before
      // creating a remote parent or sending an earlier part. Without this
      // aggregate preflight, a missing middle or final file could leave an
      // avoidable incomplete parent (and already-uploaded prefix) behind.
      //
      // A part with a backend id is deliberately excluded: reconciliation can
      // prove that the remote part already exists, in which case no local file
      // is required. If reconciliation later proves it absent, _sendPart
      // performs the file check before issuing its replacement POST.
      final Map<int, RecordingUploadFileFingerprint> preflightedPartFiles =
          await _preflightRequiredPartFiles(
        parts,
        recordingId: recordingId,
        leaseId: leaseId,
      );
      if (recording.BEId == null && recording.parentUploadAttempted) {
        // A retry does not persist the already-frozen parent again, so it
        // needs an explicit post-preflight session check before replaying the
        // parent request.
        await _ensureSessionCurrent(session);
      }

      if (recording.BEId == null) {
        if (!recording.parentUploadAttempted) {
          final String? capturedDeviceId = session.deviceId?.trim();
          recording
            // A legacy/local draft can have no configured count. Freeze the
            // validated initial row count into the first parent request so its
            // durable retry body cannot later drift.
            ..partCount = expectedPartsCount
            ..parentUploadAttempted = true
            ..uploadDeviceId =
                capturedDeviceId == null || capturedDeviceId.isEmpty
                    ? null
                    : capturedDeviceId;
          // Freeze all request fields that can vary at runtime before the
          // first POST. A retry with the same idempotency key must have the
          // exact same request body.
          await _store.saveRecording(recording, leaseId);
          await _ensureSessionCurrent(session);
        }
        final Recording requestRecording = recording;
        final int backendRecordingId = await _runWithLeaseHeartbeat<int>(
          recordingId: recordingId,
          leaseId: leaseId,
          operation: () => _api.createRecording(
            recording: requestRecording,
            session: session,
            idempotencyKey: _recordingIdempotencyKey(requestRecording),
            beforePost: () => _ensureSessionCurrent(session),
          ),
        );
        _validateBackendId(backendRecordingId, 'recording');
        recording.BEId = backendRecordingId;

        // The remote parent id must be durable before any part can be sent.
        await _store.saveRecording(recording, leaseId);
      } else {
        _validateBackendId(recording.BEId!, 'recording');
      }

      for (final RecordingPart part in parts) {
        await _sendPart(
          recording: recording,
          part: part,
          session: session,
          leaseId: leaseId,
          preflightedPartFiles: preflightedPartFiles,
          onProgress: onProgress,
        );
      }

      await _ensureSessionCurrent(session);

      // Reload from the store so a silent/failed part transition, missing row,
      // or concurrent mutation cannot be hidden by in-memory model state.
      final List<RecordingPart> persistedParts =
          await _store.loadRecordingParts(recordingId, leaseId);
      _validateCompletedParts(
        recording,
        persistedParts,
        expectedPartsCount,
      );

      recording
        ..sent = true
        ..sending = false;
      await _store.completeRecording(
        recording,
        leaseId,
        expectedPartsCount: expectedPartsCount,
      );

      return RecordingUploadResult(
        status: RecordingUploadStatus.uploaded,
        recording: recording,
      );
    } catch (error, stackTrace) {
      if (acquired || recording == null) {
        try {
          await _store.releaseRecording(recordingId, leaseId);
        } catch (_) {
          // Preserve the primary API/DB/session failure. Startup reconciliation
          // can recover a lease whose cleanup write also failed.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _sendPart({
    required Recording recording,
    required RecordingPart part,
    required RecordingUploadSession session,
    required String leaseId,
    required Map<int, RecordingUploadFileFingerprint> preflightedPartFiles,
    RecordingUploadProgress? onProgress,
  }) async {
    final int recordingId = recording.id!;
    final int partId = part.id!;
    final int backendRecordingId = recording.BEId!;

    if (part.sent) {
      _validateCompletedPart(recording, part);
      return;
    }
    final int? linkedBackendRecordingId = part.backendRecordingId;
    if (linkedBackendRecordingId != null &&
        linkedBackendRecordingId != backendRecordingId &&
        (part.BEId != null || part.uploadAttempted)) {
      throw RecordingUploadValidationException(
        'Recording part $partId belongs to backend recording '
        '${part.backendRecordingId}, expected $backendRecordingId.',
      );
    }

    final bool acquired = await _store.tryAcquireRecordingPart(
      recordingId,
      partId,
      leaseId,
    );
    if (!acquired) {
      throw RecordingUploadValidationException(
        'Recording part $partId is busy or no longer eligible for upload.',
      );
    }

    final bool backendParentBindingMissing = part.backendRecordingId == null;
    bool attemptMarkerMayHaveCommitted = false;
    part
      ..recordingId = recordingId
      ..sending = true
      ..backendRecordingId = backendRecordingId;

    try {
      await _ensureSessionCurrent(session);

      if (part.BEId != null && backendParentBindingMissing) {
        // Legacy rows can retain a remote part id without the remote parent
        // needed to query it. Bind and durably persist the known current
        // parent before reconciliation; otherwise the adapter must treat the
        // lookup as absent and can duplicate an already-existing remote part.
        await _store.saveRecordingPart(recordingId, part, leaseId);
        await _ensureSessionCurrent(session);
      }

      // A backend id with a false local sent flag can happen when the app
      // stopped between remote success and the final local state transition.
      // Reconcile it before issuing another POST.
      if (part.BEId != null) {
        _validateBackendId(part.BEId!, 'recording part');
        final bool exists = await _runWithLeaseHeartbeat<bool>(
          recordingId: recordingId,
          leaseId: leaseId,
          operation: () => _api.recordingPartExists(
            part: part,
            session: session,
          ),
        );
        if (exists) {
          part
            ..sent = true
            ..sending = false;
          await _store.saveRecordingPart(recordingId, part, leaseId);
          return;
        }

        part
          ..BEId = null
          // A legacy row can have a stale backend part id without its owning
          // backend parent. Once reconciliation proves that id absent, bind
          // the replacement request to the current parent before persisting
          // or posting it.
          ..backendRecordingId = backendRecordingId;
        await _store.saveRecordingPart(recordingId, part, leaseId);
      }

      _validatePartRequest(part);
      await _verifyPartContentBeforeUpload(
        recordingId: recordingId,
        part: part,
        leaseId: leaseId,
        preflightedFingerprint: preflightedPartFiles[partId],
      );

      await _ensureSessionCurrent(session);
      if (!part.uploadAttempted) {
        // Freeze the durable request fields before the first byte can leave.
        // Public request-field editors reject changes once this marker is set;
        // cache-only path recovery uses a separate guarded persistence path.
        attemptMarkerMayHaveCommitted = true;
        await _store.markRecordingPartAttempted(
          recordingId,
          partId,
          leaseId,
        );
        part.uploadAttempted = true;
        attemptMarkerMayHaveCommitted = false;
      }
      // The marker persistence is an await boundary. Logout, account switch,
      // or environment switch can happen while the durable write is in
      // flight, so revalidate the exact captured logical session before any
      // part bytes are handed to the API.
      await _ensureSessionCurrent(session);
      final int backendPartId = await _runWithLeaseHeartbeat<int>(
        recordingId: recordingId,
        leaseId: leaseId,
        operation: () => _api.uploadRecordingPart(
          part: part,
          session: session,
          idempotencyKey: _partIdempotencyKey(recording, part),
          beforePost: () => _ensureSessionCurrent(session),
          onProgress: onProgress == null
              ? null
              : (int sent, int total) {
                  try {
                    onProgress(partId, sent, total);
                  } catch (_) {
                    // Progress is observational. A UI/port listener must not
                    // turn a successful remote upload into a failed retry.
                  }
                },
        ),
      );
      _validateBackendId(backendPartId, 'recording part');

      part
        ..BEId = backendPartId
        ..sent = true
        ..sending = false;

      // Persist the remote id immediately. A later failure can then reconcile
      // instead of duplicating the part.
      await _store.saveRecordingPart(recordingId, part, leaseId);
    } catch (error, stackTrace) {
      part.sending = false;
      if (!attemptMarkerMayHaveCommitted) {
        try {
          await _store.saveRecordingPart(recordingId, part, leaseId);
        } catch (_) {
          // Do not replace the causal API/DB error with cleanup failure.
        }
      }
      // If the marker write itself threw, its commit state is unknowable.
      // Avoid overwriting a possibly committed true value with this stale
      // in-memory false snapshot. Aggregate lease release clears `sending`
      // without changing the durable attempt marker.
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<Map<int, RecordingUploadFileFingerprint>> _preflightRequiredPartFiles(
    List<RecordingPart> parts, {
    required int recordingId,
    required String leaseId,
  }) async {
    final Map<int, RecordingUploadFileFingerprint> fingerprints =
        <int, RecordingUploadFileFingerprint>{};
    for (final RecordingPart part in parts) {
      if (part.sent || part.BEId != null) continue;

      final int partId = part.id!;
      final String path = part.path!;
      final RecordingUploadFileFingerprint fingerprint =
          await _inspectValidPartFile(partId, path);
      await _freezeOrVerifyPartContent(
        recordingId: recordingId,
        part: part,
        fingerprint: fingerprint,
        leaseId: leaseId,
      );
      fingerprints[partId] = fingerprint;
    }
    return Map<int, RecordingUploadFileFingerprint>.unmodifiable(fingerprints);
  }

  Future<void> _verifyPartContentBeforeUpload({
    required int recordingId,
    required RecordingPart part,
    required String leaseId,
    required RecordingUploadFileFingerprint? preflightedFingerprint,
  }) async {
    final int partId = part.id!;
    final RecordingUploadFileFingerprint current =
        await _inspectValidPartFile(partId, part.path!);
    if (preflightedFingerprint != null &&
        !preflightedFingerprint.matches(current)) {
      throw RecordingUploadValidationException(
        'Recording part $partId changed after upload preflight.',
      );
    }
    await _freezeOrVerifyPartContent(
      recordingId: recordingId,
      part: part,
      fingerprint: current,
      leaseId: leaseId,
    );
  }

  Future<RecordingUploadFileFingerprint> _inspectValidPartFile(
    int partId,
    String path,
  ) async {
    final RecordingUploadFileFingerprint? fingerprint =
        await _files.inspect(path);
    if (fingerprint == null ||
        fingerprint.byteLength <= 0 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(fingerprint.sha256)) {
      throw RecordingUploadValidationException(
        'Recording part $partId has no readable local file or valid WAV '
        'content.',
      );
    }
    return fingerprint;
  }

  Future<void> _freezeOrVerifyPartContent({
    required int recordingId,
    required RecordingPart part,
    required RecordingUploadFileFingerprint fingerprint,
    required String leaseId,
  }) async {
    final int partId = part.id!;
    final String? storedHash = part.uploadContentSha256?.trim();
    final int? storedBytes = part.uploadContentBytes;
    final bool hasHash = storedHash?.isNotEmpty ?? false;
    final bool hasBytes = storedBytes != null;

    if (hasHash != hasBytes ||
        (hasHash && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(storedHash!)) ||
        (hasBytes && storedBytes <= 0)) {
      throw RecordingUploadValidationException(
        'Recording part $partId has an invalid frozen content fingerprint.',
      );
    }

    if (hasHash) {
      final RecordingUploadFileFingerprint stored =
          RecordingUploadFileFingerprint(
        sha256: storedHash!,
        byteLength: storedBytes!,
      );
      if (!stored.matches(fingerprint)) {
        throw RecordingUploadValidationException(
          'Recording part $partId content changed after its upload request '
          'was frozen.',
        );
      }
      return;
    }

    await _store.freezeRecordingPartContent(
      recordingId,
      partId,
      fingerprint,
      leaseId,
    );
    part
      ..uploadContentSha256 = fingerprint.sha256.toLowerCase()
      ..uploadContentBytes = fingerprint.byteLength;
  }

  Future<T> _runWithLeaseHeartbeat<T>({
    required int recordingId,
    required String leaseId,
    required Future<T> Function() operation,
  }) async {
    Future<void>? pendingRenewal;
    Object? renewalError;
    StackTrace? renewalStackTrace;

    void scheduleRenewal() {
      if (pendingRenewal != null || renewalError != null) return;

      late final Future<void> renewal;
      renewal = (() async {
        try {
          await _store.renewRecording(recordingId, leaseId);
        } catch (error, stackTrace) {
          renewalError ??= error;
          renewalStackTrace ??= stackTrace;
        }
      })()
          .whenComplete(() {
        if (identical(pendingRenewal, renewal)) {
          pendingRenewal = null;
        }
      });
      pendingRenewal = renewal;
    }

    final Timer timer = Timer.periodic(
      _leaseHeartbeatInterval,
      (_) => scheduleRenewal(),
    );

    T result;
    try {
      result = await operation();
    } catch (error, stackTrace) {
      timer.cancel();
      final Future<void>? renewal = pendingRenewal;
      if (renewal != null) {
        await renewal;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    timer.cancel();
    final Future<void>? renewal = pendingRenewal;
    if (renewal != null) {
      await renewal;
    }
    if (renewalError != null) {
      Error.throwWithStackTrace(renewalError!, renewalStackTrace!);
    }

    // Also renew after fast requests. Besides keeping the timestamp fresh,
    // this proves that the lease was not stolen while the request was live.
    await _store.renewRecording(recordingId, leaseId);
    return result;
  }

  void _validateAggregate(
    Recording recording,
    List<RecordingPart> parts,
  ) {
    if (recording.id == null || recording.id! <= 0) {
      throw const RecordingUploadValidationException(
        'Recording has no valid local id.',
      );
    }
    if (parts.isEmpty) {
      throw const RecordingUploadValidationException(
        'A recording cannot be uploaded without recording parts.',
      );
    }
    if (recording.uploadKey == null || recording.uploadKey!.trim().isEmpty) {
      throw const RecordingUploadValidationException(
        'Recording has no durable upload key.',
      );
    }
    if ((recording.partCount ?? 0) < 0) {
      throw const RecordingUploadValidationException(
        'Recording has an invalid expected part count.',
      );
    }

    final int expected = _expectedPartsCount(recording, parts);
    if (parts.length != expected) {
      throw RecordingUploadValidationException(
        'Expected $expected recording parts but found ${parts.length}.',
      );
    }

    final Set<int> partIds = <int>{};
    final Set<String> partUploadKeys = <String>{};
    final Set<int> backendPartIds = <int>{};
    for (final RecordingPart part in parts) {
      final int? partId = part.id;
      if (partId == null || partId <= 0) {
        throw const RecordingUploadValidationException(
          'Every recording part must have a positive local id.',
        );
      }
      if (!partIds.add(partId)) {
        throw RecordingUploadValidationException(
          'Duplicate local recording part id $partId.',
        );
      }
      if (part.recordingId != recording.id) {
        throw RecordingUploadValidationException(
          'Recording part $partId belongs to a different recording.',
        );
      }
      final String uploadKey = (part.uploadKey ?? '').trim();
      if (uploadKey.isEmpty) {
        throw RecordingUploadValidationException(
          'Recording part $partId has no durable upload key.',
        );
      }
      if (!partUploadKeys.add(uploadKey)) {
        throw RecordingUploadValidationException(
          'Recording parts have a duplicate durable upload key.',
        );
      }

      final int? backendPartId = part.BEId;
      if (backendPartId != null) {
        if (backendPartId <= 0) {
          throw RecordingUploadValidationException(
            'Recording part $partId has an invalid backend id.',
          );
        }
        if (!backendPartIds.add(backendPartId)) {
          throw RecordingUploadValidationException(
            'Recording parts have a duplicate backend id.',
          );
        }
      }

      if (!part.sent && backendPartId == null) {
        _validatePartRequest(part);
      }
    }
  }

  void _validatePartRequest(RecordingPart part) {
    final int? partId = part.id;
    final String? path = part.path;
    if (path == null || path.trim().isEmpty) {
      throw RecordingUploadValidationException(
        'Recording part $partId has no readable local file.',
      );
    }
    if (!part.startTime.isBefore(part.endTime)) {
      throw RecordingUploadValidationException(
        'Recording part $partId has an invalid time range.',
      );
    }

    _validateCoordinate(
      part.gpsLatitudeStart,
      minimum: -90,
      maximum: 90,
      partId: partId,
      field: 'start latitude',
    );
    _validateCoordinate(
      part.gpsLatitudeEnd,
      minimum: -90,
      maximum: 90,
      partId: partId,
      field: 'end latitude',
    );
    _validateCoordinate(
      part.gpsLongitudeStart,
      minimum: -180,
      maximum: 180,
      partId: partId,
      field: 'start longitude',
    );
    _validateCoordinate(
      part.gpsLongitudeEnd,
      minimum: -180,
      maximum: 180,
      partId: partId,
      field: 'end longitude',
    );
  }

  void _validateCoordinate(
    double value, {
    required double minimum,
    required double maximum,
    required int? partId,
    required String field,
  }) {
    if (!value.isFinite || value < minimum || value > maximum) {
      throw RecordingUploadValidationException(
        'Recording part $partId has an invalid GPS $field.',
      );
    }
  }

  int _expectedPartsCount(
    Recording recording,
    List<RecordingPart> parts,
  ) {
    final int configured = recording.partCount ?? 0;
    return configured > 0 ? configured : parts.length;
  }

  void _validateCompletedParts(
    Recording recording,
    List<RecordingPart> parts,
    int expectedPartsCount,
  ) {
    if (parts.length != expectedPartsCount) {
      throw RecordingUploadValidationException(
        'Completion expected $expectedPartsCount parts but found '
        '${parts.length}.',
      );
    }
    final Set<int> backendPartIds = <int>{};
    for (final RecordingPart part in parts) {
      _validateCompletedPart(recording, part);
      if (!backendPartIds.add(part.BEId!)) {
        throw const RecordingUploadValidationException(
          'Completed recording parts have duplicate backend ids.',
        );
      }
    }
  }

  void _validateCompletedPart(Recording recording, RecordingPart part) {
    if (!part.sent) {
      throw RecordingUploadValidationException(
        'Recording part ${part.id} is still unsent.',
      );
    }
    final int? backendPartId = part.BEId;
    if (backendPartId == null || backendPartId <= 0) {
      throw RecordingUploadValidationException(
        'Recording part ${part.id} has no valid backend id.',
      );
    }
    if (part.backendRecordingId != recording.BEId) {
      throw RecordingUploadValidationException(
        'Recording part ${part.id} belongs to backend recording '
        '${part.backendRecordingId}, expected ${recording.BEId}.',
      );
    }
  }

  bool _isCompletedAggregate(
    Recording recording,
    List<RecordingPart> parts,
  ) {
    final int? backendRecordingId = recording.BEId;
    if (backendRecordingId == null || backendRecordingId <= 0) return false;
    final Set<int> backendPartIds = <int>{};
    for (final RecordingPart part in parts) {
      final int? backendPartId = part.BEId;
      if (!part.sent ||
          backendPartId == null ||
          backendPartId <= 0 ||
          part.backendRecordingId != backendRecordingId ||
          !backendPartIds.add(backendPartId)) {
        return false;
      }
    }
    return true;
  }

  void _validateBackendId(int id, String entity) {
    if (id <= 0) {
      throw UploadException(
        'Backend returned an invalid $entity id.',
        502,
      );
    }
  }

  void _validateRecordingSession(
    Recording recording,
    RecordingUploadSession session,
  ) {
    validateRecordingSessionBinding(recording, session);
  }

  Future<void> _ensureSessionCurrent(
    RecordingUploadSession session,
  ) async {
    if (!await _sessions.isCurrent(session)) {
      throw const RecordingUploadSessionChangedException();
    }
  }

  String _recordingIdempotencyKey(Recording recording) {
    return 'recording:${recording.uploadKey}';
  }

  String _partIdempotencyKey(
    Recording recording,
    RecordingPart part,
  ) {
    return 'recording-part:${part.uploadKey}';
  }
}
