part of 'database_repository.dart';

const RecordingsController _recordingsApi = RecordingsController();
const RecordingPartsController _recordingPartsApi = RecordingPartsController();
const FilteredRecordingsController _filteredRecordingsApi =
    FilteredRecordingsController();

Future<void> _sendRecording(
    Recording recording, List<RecordingPart> recordingParts) async {
  // Compatibility entry point: all uploads must go through the aggregate
  // service so the durable parent lease, frozen request snapshot,
  // idempotency keys, and captured session are enforced.
  await _sendRecordingNew(recording, recordingParts);
}

Future<void> _sendRecordingNew(
    Recording recording, List<RecordingPart> recordingParts) async {
  if (recording.id == null) {
    throw const RecordingUploadValidationException(
      'Recording has no local id.',
    );
  }

  final RecordingUploadService service = RecordingUploadService(
    store: const _SqliteRecordingUploadStore(),
    api: const _BackendRecordingUploadApi(),
    sessions: const _SecureStorageRecordingUploadSessions(),
    policy: const _ConfigRecordingUploadPolicy(),
    files: const _LocalRecordingUploadFileProbe(),
    newLeaseId: () =>
        '${recording.id}:${DateTime.now().microsecondsSinceEpoch}:'
        '${Isolate.current.hashCode}',
  );

  try {
    final RecordingUploadResult result = await service.send(
      recording.id!,
      onProgress: _reportRecordingUploadProgress,
    );

    final Recording? persisted = result.recording;
    if (persisted != null) {
      recording
        ..BEId = persisted.BEId
        ..sent = persisted.sent
        ..sending = persisted.sending
        ..uploadLease = persisted.uploadLease;
    }

    switch (result.status) {
      case RecordingUploadStatus.uploaded:
      case RecordingUploadStatus.alreadySent:
        for (final RecordingPart part in recordingParts) {
          if (part.id != null) {
            UploadProgressBus.markDone(part.id!);
          }
        }
        return;
      case RecordingUploadStatus.busy:
        throw UploadException(
          result.reason ?? 'Recording upload is already in progress.',
          409,
        );
      case RecordingUploadStatus.deferred:
        throw UploadException(
          result.reason ?? 'Recording upload was deferred.',
          503,
        );
    }
  } catch (e, stackTrace) {
    for (final RecordingPart part in recordingParts) {
      if (part.id != null) {
        UploadProgressBus.clear(part.id!);
      }
    }
    logger.e('Error sending recording: $e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    rethrow;
  }
}

void _reportRecordingUploadProgress(
  int partId,
  int sent,
  int total,
) {
  UploadProgressBus.update(partId, sent, total);
  final SendPort? port =
      IsolateNameServer.lookupPortByName('upload_progress_port');
  port?.send(<Object>['update', partId, sent, total]);
}

class _SqliteRecordingUploadStore implements RecordingUploadStore {
  const _SqliteRecordingUploadStore();

  static const Duration _leaseTimeout = Duration(minutes: 5);

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<void> _touchLease(
    DatabaseExecutor db,
    int recordingId,
    String leaseId,
  ) async {
    final int changed = await db.rawUpdate(
      'UPDATE recordings SET uploadLeaseUpdatedAt = ? '
      'WHERE id = ? AND uploadLease = ? AND COALESCE(sending, 0) = 1',
      <Object?>[_now, recordingId, leaseId],
    );
    if (changed != 1) {
      throw StateError('Recording upload lease is no longer current.');
    }
  }

  @override
  Future<bool> tryAcquireRecording(int recordingId, String leaseId) async {
    final Database db = await DatabaseNew.database;
    return db.transaction<bool>((Transaction txn) async {
      final int now = _now;
      final int staleBefore = now - _leaseTimeout.inMilliseconds;
      final int changed = await txn.rawUpdate(
        'UPDATE recordings '
        'SET sending = 1, uploadLease = ?, uploadLeaseUpdatedAt = ? '
        'WHERE id = ? AND ('
        '  COALESCE(sending, 0) = 0 '
        '  OR uploadLease IS NULL '
        '  OR (uploadLeaseUpdatedAt < ? AND uploadLease NOT LIKE ?)'
        ')',
        <Object?>[leaseId, now, recordingId, staleBefore, 'delete:%'],
      );
      if (changed != 1) return false;

      // A previous process may have died while only a child part was marked
      // sending. Acquiring the parent lease makes those child flags stale.
      await txn.rawUpdate(
        'UPDATE recordingParts SET sending = 0 WHERE recordingId = ?',
        <Object?>[recordingId],
      );
      return true;
    });
  }

  @override
  Future<void> renewRecording(int recordingId, String leaseId) async {
    final Database db = await DatabaseNew.database;
    await _touchLease(db, recordingId, leaseId);
  }

  @override
  Future<Recording?> loadRecording(
    int recordingId,
    String leaseId,
  ) async {
    final Database db = await DatabaseNew.database;
    try {
      await _touchLease(db, recordingId, leaseId);
    } on StateError {
      return null;
    }
    final List<Map<String, Object?>> rows = await db.query(
      'recordings',
      where: 'id = ? AND uploadLease = ?',
      whereArgs: <Object?>[recordingId, leaseId],
      limit: 1,
    );
    return rows.isEmpty ? null : Recording.fromJson(rows.first);
  }

  @override
  Future<List<RecordingPart>> loadRecordingParts(
    int recordingId,
    String leaseId,
  ) async {
    final Database db = await DatabaseNew.database;
    await _touchLease(db, recordingId, leaseId);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT p.* FROM recordingParts p '
      'INNER JOIN recordings r ON r.id = p.recordingId '
      'WHERE p.recordingId = ? AND r.uploadLease = ? '
      'ORDER BY p.startTime ASC, p.id ASC',
      <Object?>[recordingId, leaseId],
    );
    return rows.map(RecordingPart.fromJson).toList(growable: false);
  }

  @override
  Future<void> saveRecording(
    Recording recording,
    String leaseId,
  ) async {
    final int? recordingId = recording.id;
    if (recordingId == null) {
      throw const RecordingUploadValidationException(
        'Cannot save a recording without a local id.',
      );
    }
    final Database db = await DatabaseNew.database;
    recording
      ..sending = true
      ..uploadLease = leaseId
      ..uploadLeaseUpdatedAt = _now;
    final int changed = await db.update(
      'recordings',
      recording.toJson(),
      where: 'id = ? AND uploadLease = ?',
      whereArgs: <Object?>[recordingId, leaseId],
    );
    if (changed != 1) {
      throw StateError('Recording upload lease is no longer current.');
    }
  }

  @override
  Future<bool> tryAcquireRecordingPart(
    int recordingId,
    int partId,
    String leaseId,
  ) async {
    final Database db = await DatabaseNew.database;
    return db.transaction<bool>((Transaction txn) async {
      await _touchLease(txn, recordingId, leaseId);
      final int changed = await txn.rawUpdate(
        'UPDATE recordingParts '
        'SET sending = 1 '
        'WHERE id = ? AND recordingId = ? '
        'AND COALESCE(sent, 0) = 0 '
        'AND COALESCE(sending, 0) = 0 '
        'AND EXISTS ('
        '  SELECT 1 FROM recordings r '
        '  WHERE r.id = ? AND r.uploadLease = ?'
        ')',
        <Object?>[partId, recordingId, recordingId, leaseId],
      );
      return changed == 1;
    });
  }

  @override
  Future<void> markRecordingPartAttempted(
    int recordingId,
    int partId,
    String leaseId,
  ) async {
    final Database db = await DatabaseNew.database;
    await _touchLease(db, recordingId, leaseId);
    final int changed = await db.rawUpdate(
      'UPDATE recordingParts SET uploadAttempted = 1 '
      'WHERE id = ? AND recordingId = ? AND COALESCE(sending, 0) = 1 '
      'AND EXISTS ('
      'SELECT 1 FROM recordings r '
      'WHERE r.id = ? AND r.uploadLease = ?'
      ')',
      <Object?>[partId, recordingId, recordingId, leaseId],
    );
    if (changed != 1) {
      throw StateError('Recording upload lease is no longer current.');
    }
  }

  @override
  Future<void> freezeRecordingPartContent(
    int recordingId,
    int partId,
    RecordingUploadFileFingerprint fingerprint,
    String leaseId,
  ) async {
    final Database db = await DatabaseNew.database;
    await _touchLease(db, recordingId, leaseId);
    final String sha256 = fingerprint.sha256.toLowerCase();
    final int changed = await db.rawUpdate(
      'UPDATE recordingParts '
      'SET uploadContentSha256 = ?, uploadContentBytes = ? '
      'WHERE id = ? AND recordingId = ? AND COALESCE(sent, 0) = 0 '
      'AND ('
      '  (uploadContentSha256 IS NULL AND uploadContentBytes IS NULL) '
      '  OR (LOWER(uploadContentSha256) = ? AND uploadContentBytes = ?)'
      ') '
      'AND EXISTS ('
      'SELECT 1 FROM recordings r '
      'WHERE r.id = ? AND r.uploadLease = ?'
      ')',
      <Object?>[
        sha256,
        fingerprint.byteLength,
        partId,
        recordingId,
        sha256,
        fingerprint.byteLength,
        recordingId,
        leaseId,
      ],
    );
    if (changed != 1) {
      throw StateError(
        'Recording part content could not be frozen under the current lease.',
      );
    }
  }

  @override
  Future<void> saveRecordingPart(
    int recordingId,
    RecordingPart part,
    String leaseId,
  ) async {
    final int? partId = part.id;
    if (partId == null) {
      throw const RecordingUploadValidationException(
        'Cannot save a recording part without a local id.',
      );
    }
    final Database db = await DatabaseNew.database;
    await _touchLease(db, recordingId, leaseId);
    final int changed = await db.update(
      'recordingParts',
      part.toJson(),
      where: 'id = ? AND recordingId = ? AND EXISTS ('
          'SELECT 1 FROM recordings r '
          'WHERE r.id = ? AND r.uploadLease = ?'
          ')',
      whereArgs: <Object?>[
        partId,
        recordingId,
        recordingId,
        leaseId,
      ],
    );
    if (changed != 1) {
      throw StateError('Recording upload lease is no longer current.');
    }
  }

  @override
  Future<void> completeRecording(
    Recording recording,
    String leaseId, {
    required int expectedPartsCount,
  }) async {
    final int recordingId = recording.id!;
    final int backendRecordingId = recording.BEId!;
    final Database db = await DatabaseNew.database;

    await db.transaction<void>((Transaction txn) async {
      await _touchLease(txn, recordingId, leaseId);
      final List<Map<String, Object?>> rows = await txn.query(
        'recordingParts',
        where: 'recordingId = ?',
        whereArgs: <Object?>[recordingId],
      );
      final List<RecordingPart> parts =
          rows.map(RecordingPart.fromJson).toList(growable: false);
      final bool complete = parts.length == expectedPartsCount &&
          parts.every(
            (RecordingPart part) =>
                part.sent &&
                part.BEId != null &&
                part.BEId! > 0 &&
                part.backendRecordingId == backendRecordingId,
          );
      if (!complete) {
        throw const RecordingUploadValidationException(
          'Persisted recording parts are not complete.',
        );
      }

      recording
        ..sent = true
        ..sending = false
        ..uploadLease = null;
      final int changed = await txn.update(
        'recordings',
        recording.toJson(),
        where: 'id = ? AND uploadLease = ?',
        whereArgs: <Object?>[recordingId, leaseId],
      );
      if (changed != 1) {
        throw StateError('Recording upload lease is no longer current.');
      }
    });
  }

  @override
  Future<void> releaseRecording(int recordingId, String leaseId) async {
    final Database db = await DatabaseNew.database;
    await db.transaction<void>((Transaction txn) async {
      // Release is deliberately lease-only. The service may have optimistically
      // mutated its in-memory model immediately before a failed completion
      // transaction; writing that snapshot here could falsely persist `sent`.
      final int changed = await txn.rawUpdate(
        'UPDATE recordings '
        'SET sending = 0, uploadLease = NULL, uploadLeaseUpdatedAt = NULL '
        'WHERE id = ? AND uploadLease = ?',
        <Object?>[recordingId, leaseId],
      );
      if (changed != 1) {
        throw StateError('Recording upload lease is no longer current.');
      }
      await txn.rawUpdate(
        'UPDATE recordingParts SET sending = 0 WHERE recordingId = ?',
        <Object?>[recordingId],
      );
    });
  }
}

class _BackendRecordingUploadApi implements RecordingUploadApi {
  const _BackendRecordingUploadApi();

  static final RecordingPartMultipartUploader _partUploader =
      RecordingPartMultipartUploader(
    onCleanupError: _reportRecordingUploadStageCleanupError,
  );

  @override
  Future<int> createRecording({
    required Recording recording,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
  }) async {
    final Map<String, Object?> body =
        recording.toBEJsonWithDeviceId(recording.uploadDeviceId);
    final Response<dynamic> response = await _recordingsApi.createRecording(
      body,
      accessToken: session.accessToken,
      idempotencyKey: idempotencyKey,
      host: session.backendHost,
      beforePost: beforePost,
    );
    _requireSuccess(response, 'create recording');
    return _readBackendId(response.data, 'recording');
  }

  @override
  Future<int> uploadRecordingPart({
    required RecordingPart part,
    required RecordingUploadSession session,
    required String idempotencyKey,
    required Future<void> Function() beforePost,
    RecordingPartUploadProgress? onProgress,
  }) async {
    try {
      final String? expectedSha256 = part.uploadContentSha256;
      final int? expectedByteLength = part.uploadContentBytes;
      if (expectedSha256 == null || expectedByteLength == null) {
        throw RecordingUploadValidationException(
          'Recording part ${part.id} has no frozen upload fingerprint.',
        );
      }

      final Response<dynamic> response = await _partUploader.upload(
        filePath: part.path!,
        expectedSha256: expectedSha256,
        expectedByteLength: expectedByteLength,
        backendRecordingId: part.backendRecordingId,
        startDate: part.startTime,
        endDate: part.endTime,
        gpsLatitudeStart: part.gpsLatitudeStart,
        gpsLatitudeEnd: part.gpsLatitudeEnd,
        gpsLongitudeStart: part.gpsLongitudeStart,
        gpsLongitudeEnd: part.gpsLongitudeEnd,
        accessToken: session.accessToken,
        idempotencyKey: idempotencyKey,
        host: session.backendHost,
        onSendProgress: onProgress,
        beforePost: beforePost,
      );
      _requireSuccess(response, 'upload recording part');
      return _readBackendId(response.data, 'recording part');
    } on ImmutableUploadSourceException {
      throw RecordingUploadValidationException(
        'Recording part ${part.id} no longer matches its frozen upload '
        'content.',
      );
    }
  }

  @override
  Future<bool> recordingPartExists({
    required RecordingPart part,
    required RecordingUploadSession session,
  }) async {
    final int? backendRecordingId = part.backendRecordingId;
    final int? backendPartId = part.BEId;
    if (backendRecordingId == null ||
        backendRecordingId <= 0 ||
        backendPartId == null ||
        backendPartId <= 0) {
      throw const RecordingUploadValidationException(
        'Recording-part reconciliation requires valid backend identities.',
      );
    }

    final Response<dynamic> response = await _recordingsApi.fetchRecordingById(
      backendRecordingId,
      includeParts: true,
      accessToken: session.accessToken,
      host: session.backendHost,
    );
    final int status = response.statusCode ?? 500;
    if (status == 200) {
      return recordingPayloadConfirmsPartExists(
        response.data,
        expectedRecordingId: backendRecordingId,
        expectedPartId: backendPartId,
      );
    }
    if (status == 204 || status == 404) return false;
    throw UploadException(
      'Failed to reconcile recording part.',
      status,
    );
  }

  void _requireSuccess(Response<dynamic> response, String operation) {
    final int status = response.statusCode ?? 500;
    if (status < 200 || status >= 300) {
      throw UploadException('Failed to $operation.', status);
    }
  }

  int _readBackendId(dynamic data, String entity) {
    return readPositiveUploadResponseId(
      data,
      entity: entity,
      mapKeys: const <String>['id', 'recordingId', 'partId', 'data'],
    );
  }
}

void _reportRecordingUploadStageCleanupError(
  Object _,
  StackTrace stackTrace,
) {
  const String message = 'Recording upload temporary stage cleanup failed.';
  logger.w(message);
  unawaited(
    Sentry.captureException(
      StateError(message),
      stackTrace: stackTrace,
    ),
  );
}

class _SecureStorageRecordingUploadSessions
    implements RecordingUploadSessionProvider {
  const _SecureStorageRecordingUploadSessions();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<RecordingUploadSession?> capture() {
    return captureActivatedRecordingUploadSession(
      captureActivatedSession: activatedAuthSessions.capture,
      readOptionalDeviceId: () => _storage.read(key: 'fcmToken'),
      environment: Config.hostEnvironment.name,
      backendHost: Config.host,
    );
  }

  @override
  Future<bool> isCurrent(RecordingUploadSession session) async {
    final bool sameLogicalSession = await activatedAuthSessions.isCurrent(
      ActivatedAuthSessionSnapshot(
        accessToken: session.accessToken,
        userId: session.userId,
        subject: session.accountEmail ?? '',
        sessionId: session.logicalSessionId,
        verified: true,
      ),
    );
    return sameLogicalSession &&
        Config.hostEnvironment.name == session.environment &&
        Config.host == session.backendHost;
  }
}

Future<void> _requireRecordingSessionCurrent(
  RecordingUploadSessionProvider sessionProvider,
  RecordingUploadSession session,
) async {
  if (!await sessionProvider.isCurrent(session)) {
    throw const RecordingUploadSessionChangedException();
  }
}

class _ConfigRecordingUploadPolicy implements RecordingUploadPolicy {
  const _ConfigRecordingUploadPolicy();

  @override
  Future<bool> canUpload() => Config.canUpload;
}

class _LocalRecordingUploadFileProbe implements RecordingUploadFileProbe {
  const _LocalRecordingUploadFileProbe();

  @override
  Future<RecordingUploadFileFingerprint?> inspect(String path) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) return null;

    try {
      final File file = File(normalizedPath);
      final FileStat before = await file.stat();
      if (before.type != FileSystemEntityType.file || before.size <= 0) {
        return null;
      }
      final WavPcmDataRegion region = await readWavPcmDataRegion(
        const IoSegmentFileOperations(),
        normalizedPath,
      );
      if (region.dataLength <= 0) return null;

      final Digest digest = await sha256.bind(file.openRead()).first;
      final FileStat after = await file.stat();
      if (after.type != FileSystemEntityType.file ||
          after.size != before.size ||
          after.modified != before.modified) {
        return null;
      }
      return RecordingUploadFileFingerprint(
        sha256: digest.toString(),
        byteLength: after.size,
      );
    } catch (_) {
      return null;
    }
  }
}

Future<bool> _handleDeletedPath(RecordingPart recordingPart) async {
  if (recordingPart.BEId == null || recordingPart.backendRecordingId == null) {
    return false;
  }

  final response = await _recordingPartsApi.fetchPart(
    recordingPart.backendRecordingId!,
    recordingPart.BEId!,
  );

  if (response.statusCode != null &&
      response.statusCode! >= 200 &&
      response.statusCode! < 300) {
    logger.i(
        'Recording part id: ${recordingPart.id} found on backend, marking as sent.');
    final Directory tempDir = await getApplicationDocumentsDirectory();
    final String partFilePath =
        '${tempDir.path}/recording_${recordingPart.backendRecordingId}_${recordingPart.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
    final File file = await File(partFilePath).create();
    final dynamic data = response.data;
    if (data is List<int>) {
      await file.writeAsBytes(data);
    } else if (data is String) {
      await file.writeAsString(data);
    } else {
      await file.writeAsString(data.toString());
    }
    recordingPart.path = partFilePath;
    recordingPart.sent = true;
    recordingPart.sending = false;
    await DatabaseNew._updateRecordingPartRemoteCacheState(recordingPart);
    return true;
  }

  return false;
}

Future<void> _sendRecordingPart(RecordingPart recordingPart) async {
  await _sendRecordingPartNew(recordingPart);
}

Future<void> _sendRecordingPartNew(RecordingPart recordingPart,
    {UploadProgress? onProgress}) async {
  final int? recordingId = recordingPart.recordingId;
  if (recordingId == null || recordingId <= 0) {
    throw const RecordingUploadValidationException(
      'Direct part upload requires a valid local recording parent.',
    );
  }

  final Recording? recording =
      await DatabaseNew.getRecordingFromDbById(recordingId);
  if (recording == null) {
    throw const RecordingUploadValidationException(
      'Direct part upload cannot proceed without its local recording parent.',
    );
  }

  if (onProgress != null) {
    logger.i(
      'Legacy per-part progress callback replaced by aggregate upload '
      'progress for recording $recordingId.',
    );
  }
  await _sendRecordingNew(recording, const <RecordingPart>[]);
}

Future<void> _updateRecordingBE(Recording recording) async {
  final int? recordingId = recording.id;
  final int? requestedBackendId = recording.BEId;
  if (recordingId == null ||
      recordingId <= 0 ||
      requestedBackendId == null ||
      requestedBackendId <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot update backend metadata without complete recording identities.',
    );
  }

  await DatabaseNew.runWithRecordingWorkflowLease<void>(
    recordingId: recordingId,
    leaseId: 'metadata:$recordingId:${DateTime.now().microsecondsSinceEpoch}:'
        '${Isolate.current.hashCode}',
    operation: (RecordingWorkflowLeaseContext context) async {
      final Recording persisted = context.recording;
      if (persisted.BEId != requestedBackendId) {
        throw const RecordingUploadValidationException(
          'Backend metadata target changed before the update began.',
        );
      }

      // Revalidate the captured logical session immediately before the PATCH.
      // The request uses that session's immutable token and host instead of
      // mutable global auth/config state.
      await context.renew();
      final Response<dynamic> response = await _recordingsApi.updateRecording(
        requestedBackendId,
        <String, Object?>{
          'name': persisted.name,
          'note': persisted.note,
          'estimatedBirdsCount': persisted.estimatedBirdsCount,
          'device': persisted.device,
        },
        accessToken: context.session.accessToken,
        host: context.session.backendHost,
      );

      final int status = response.statusCode ?? 500;
      if (status < 200 || status >= 300) {
        throw UploadException(
          'Failed to update recording on backend',
          status,
        );
      }
      logger.i(
        'Recording BEId $requestedBackendId successfully updated on backend.',
      );
    },
  );
}

Future<void> _fetchRecordingsFromBE() async {
  DatabaseNew.fetching = true;
  DatabaseNew.fetchedRecordings = null;
  DatabaseNew.fetchedRecordingParts = null;
  DatabaseNew._fetchedRecordingSession = null;
  try {
    const _SecureStorageRecordingUploadSessions sessionProvider =
        _SecureStorageRecordingUploadSessions();
    final RecordingUploadSession? session = await sessionProvider.capture();
    if (session == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }
    validateRecordingUploadSession(session);
    final int? numericUserId = int.tryParse(session.userId.trim());
    if (numericUserId == null || numericUserId <= 0) {
      throw FetchException(
        'Failed to fetch recordings from backend: invalid userId',
        401,
      );
    }
    await _requireRecordingSessionCurrent(sessionProvider, session);

    final Response<dynamic> response =
        await _recordingsApi.fetchRecordingsForUser(
      session.userId,
      accessToken: session.accessToken,
      host: session.backendHost,
    );
    await _requireRecordingSessionCurrent(sessionProvider, session);

    if (response.statusCode == 200) {
      final dynamic decoded = response.data is String
          ? json.decode(response.data as String)
          : response.data;
      final List<dynamic> body = decoded as List<dynamic>;
      final List<Recording> recordings =
          List<Recording>.generate(body.length, (i) {
        return Recording.fromBEJson(
          body[i],
          numericUserId,
          environment: session.environment,
        )..mail = session.accountEmail;
      });
      final List<RecordingPart> parts = <RecordingPart>[];

      for (int i = 0; i < body.length; i++) {
        for (int j = 0; j < body[i]['parts'].length; j++) {
          final RecordingPart part =
              RecordingPart.fromBEJson(body[i]['parts'][j], body[i]['id']);
          parts.add(part);
          logger.i('Added part with ID: ${part.id} and BEID: ${part.BEId}');
        }
      }

      DatabaseNew.fetchedRecordings = recordings;
      DatabaseNew.fetchedRecordingParts = parts;
      DatabaseNew._fetchedRecordingSession = session;

      final List<Recording> localRecordings =
          await DatabaseNew._getRecordingsForCapturedSession(session);
      final Set<int?> beIds = recordings.map((r) => r.BEId).toSet();

      for (final local in localRecordings) {
        await _requireRecordingSessionCurrent(sessionProvider, session);
        if (local.sent && !beIds.contains(local.BEId)) {
          if (local.id == null) continue;
          final bool hasLocalMedia = local.downloaded ||
              (local.path != null && local.path!.isNotEmpty);
          if (hasLocalMedia) {
            // Keep cached foreign recordings for Settings cache manager,
            // but remove them from "My recordings" scope.
            local.mail = '';
            await DatabaseNew.updateRecordingOwnerMail(local.id!, '');
            logger.i(
                'Recording id ${local.id} detached from current user scope (not found in current user backend list).');
          } else {
            await DatabaseNew.deleteRecordingFromCache(local.id!);
            logger.i(
                'Recording id ${local.id} deleted locally (no longer on backend).');
          }
        }
      }

      for (final beRec in recordings) {
        await _requireRecordingSessionCurrent(sessionProvider, session);
        try {
          final Recording local =
              localRecordings.firstWhere((r) => r.BEId == beRec.BEId);
          final bool needsUpdate = local.name != beRec.name ||
              local.note != beRec.note ||
              local.estimatedBirdsCount != beRec.estimatedBirdsCount ||
              local.device != beRec.device ||
              local.byApp != beRec.byApp;
          if (needsUpdate) {
            local.name = beRec.name;
            local.note = beRec.note;
            local.estimatedBirdsCount = beRec.estimatedBirdsCount;
            local.device = beRec.device;
            local.byApp = beRec.byApp;
            await DatabaseNew.updateRecording(local);
            logger.i('Recording id ${local.id} updated to match backend data.');
          }
        } catch (_) {
          // no local match
        }
      }
      await _requireRecordingSessionCurrent(sessionProvider, session);
    } else if (response.statusCode == 204) {
      DatabaseNew.fetchedRecordings = <Recording>[];
      DatabaseNew.fetchedRecordingParts = <RecordingPart>[];
      DatabaseNew._fetchedRecordingSession = session;
      logger.i('No recordings found on backend.');
    } else {
      throw FetchException('Failed to fetch recordings from backend',
          response.statusCode ?? 500);
    }
  } finally {
    DatabaseNew.fetching = false;
  }
}

Future<void> _fetchFilteredPartsForRecordingsFromBE(List<Recording> recs,
    {bool verified = false, RecordingUploadSession? capturedSession}) async {
  const _SecureStorageRecordingUploadSessions sessionProvider =
      _SecureStorageRecordingUploadSessions();
  final RecordingUploadSession? session =
      capturedSession ?? await sessionProvider.capture();
  if (session == null) {
    throw const RecordingUploadSessionChangedException();
  }
  validateRecordingUploadSession(session);
  await _requireRecordingSessionCurrent(sessionProvider, session);

  DatabaseNew.fetchedFilteredRecordingParts = <FilteredRecordingPart>[];
  DatabaseNew.fetchedDetectedDialects = <DetectedDialect>[];

  for (final rec in recs) {
    await _requireRecordingSessionCurrent(sessionProvider, session);
    if (rec.env != session.environment) {
      throw const RecordingUploadSessionChangedException();
    }
    if (rec.BEId == null) continue;
    try {
      final resp = await _filteredRecordingsApi.fetchFilteredParts(
        recordingId: rec.BEId!,
        verified: verified,
        accessToken: session.accessToken,
        host: session.backendHost,
      );
      await _requireRecordingSessionCurrent(sessionProvider, session);

      if (resp.statusCode == 200) {
        final dynamic decoded =
            resp.data is String ? json.decode(resp.data as String) : resp.data;
        final List<dynamic> arr = decoded as List<dynamic>;
        for (final item in arr) {
          if (item is! Map) continue;
          final map = item.cast<String, Object?>();
          final frp = FilteredRecordingPart.fromBEJson(map);
          DatabaseNew.fetchedFilteredRecordingParts!.add(frp);

          final dynList = map['detectedDialects'];
          if (dynList is List) {
            for (final d in dynList) {
              if (d is Map) {
                final dd = DetectedDialect.fromBEJson(
                  d.cast<String, Object?>(),
                  parentFilteredPartBEID: frp.BEId ?? 0,
                )..recordingBEID = frp.recordingBEID;
                DatabaseNew.fetchedDetectedDialects!.add(dd);
              }
            }
          }
        }
      } else if (resp.statusCode == 204) {
        // none for this recording
      } else {
        logger.w(
            'Failed to fetch filtered parts for recording ${rec.BEId}: ${resp.statusCode}');
      }
    } catch (e, st) {
      if (e is RecordingUploadSessionChangedException) {
        rethrow;
      }
      logger.e('Error fetching filtered parts for recording ${rec.BEId}: $e',
          error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }
  }
  await _requireRecordingSessionCurrent(sessionProvider, session);
}

Future<RecordingPart?> _getRecordingPartByBEID(int id) async {
  try {
    final resp = await _recordingsApi.fetchRecordingPartSummary(id);
    if (resp.statusCode == 200) {
      logger.i('sending req was succesfull');
      final dynamic data =
          resp.data is String ? json.decode(resp.data as String) : resp.data;
      return RecordingPart.fromBEJson(data['parts'][0], id);
    }

    logger.i('Recording-part request failed (${resp.statusCode}).');
    return null;
  } catch (_) {
    return null;
  }
}

Future<int?> _fetchRecordingFromBE(int id) async {
  if (id <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot fetch a recording without a positive backend id.',
    );
  }

  const _SecureStorageRecordingUploadSessions sessionProvider =
      _SecureStorageRecordingUploadSessions();
  final RecordingUploadSession? session = await sessionProvider.capture();
  if (session == null) {
    throw FetchException('Failed to fetch recording from backend', 401);
  }
  validateRecordingUploadSession(session);
  final int? capturedUserId = int.tryParse(session.userId.trim());
  if (capturedUserId == null || capturedUserId <= 0) {
    throw const RecordingUploadSessionChangedException();
  }
  await _requireRecordingSessionCurrent(sessionProvider, session);

  final Response<dynamic> response = await _recordingsApi.fetchRecordingById(
    id,
    includeParts: true,
    accessToken: session.accessToken,
    host: session.backendHost,
  );
  await _requireRecordingSessionCurrent(sessionProvider, session);

  if (response.statusCode != 200) {
    logger.w('Could not download recording $id (${response.statusCode}).');
    if (response.statusCode == 404) return null;
    throw FetchException(
      'Failed to fetch recording from backend',
      response.statusCode ?? 500,
    );
  }

  final dynamic decoded = response.data is String
      ? jsonDecode(response.data as String)
      : response.data;
  final Map<String, dynamic> body = (decoded as Map).cast<String, dynamic>();
  final int? responseRecordingId = DatabaseNew._readInt(
    body,
    const <String>['id'],
  );
  if (responseRecordingId != id) {
    throw const RecordingUploadValidationException(
      'Fetched recording identity does not match the requested recording.',
    );
  }
  final int? responseOwnerId = body['userId'] == null
      ? null
      : DatabaseNew._readInt(body, const <String>['userId']);
  if (body['userId'] != null &&
      (responseOwnerId == null || responseOwnerId <= 0)) {
    throw const RecordingUploadValidationException(
      'Fetched recording has an invalid owner identity.',
    );
  }

  final List<dynamic> partsArr = (body['parts'] as List?) ?? const [];
  final List<RecordingPart> parts = partsArr
      .map<RecordingPart>((row) => RecordingPart.fromBEJson(
            (row as Map).cast<String, dynamic>(),
            id,
          ))
      .toList(growable: false);

  final Recording recording = Recording.fromBEJson(
    body,
    responseOwnerId,
    environment: session.environment,
  )..mail = recordingBelongsToCapturedAccount(
      sent: true,
      ownerUserId: responseOwnerId,
      capturedUserId: capturedUserId,
    )
        ? session.accountEmail
        : '';

  await _requireRecordingSessionCurrent(sessionProvider, session);
  final int localId = await DatabaseNew.insertRecording(
    recording,
    capturedSession: session,
  );
  await _requireRecordingSessionCurrent(sessionProvider, session);

  if (localId > 0) {
    for (final RecordingPart part in parts) {
      part.recordingId = localId;
    }
  }

  for (final RecordingPart part in parts) {
    await _requireRecordingSessionCurrent(sessionProvider, session);
    await DatabaseNew.insertRecordingPart(
      part,
      capturedEnvironment: session.environment,
    );
  }
  await _requireRecordingSessionCurrent(sessionProvider, session);

  return localId;
}
