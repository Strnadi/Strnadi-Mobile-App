part of 'database_repository.dart';

Future<int> _downloadRecordingByLocalId(
  int localRecordingId, {
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
}) {
  return _recordingDownloadService().downloadByLocalId(
    localRecordingId,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
}

Future<int> _downloadRecordingByBackendId(
  int backendRecordingId, {
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
}) {
  return _recordingDownloadService().downloadByBackendId(
    backendRecordingId,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );
}

RecordingDownloadService _recordingDownloadService() {
  const _SecureStorageRecordingUploadSessions sessions =
      _SecureStorageRecordingUploadSessions();
  return RecordingDownloadService(
    store: const _DatabaseRecordingDownloadStore(sessions),
    api: const _ControllerRecordingDownloadApi(),
    sessions: sessions,
    files: const _IoRecordingDownloadFiles(),
  );
}

class _DatabaseRecordingDownloadStore implements RecordingDownloadStore {
  const _DatabaseRecordingDownloadStore(this._sessions);

  final RecordingUploadSessionProvider _sessions;

  @override
  Future<RecordingDownloadTarget?> findByLocalId(
    int localId,
    RecordingUploadSession session,
  ) {
    return _find(
      where: 'id = ? AND env = ?',
      whereArgs: <Object?>[localId, session.environment],
      session: session,
    );
  }

  @override
  Future<RecordingDownloadTarget?> findByBackendId(
    int backendId,
    RecordingUploadSession session,
  ) {
    return _find(
      where: 'BEId = ? AND env = ?',
      whereArgs: <Object?>[backendId, session.environment],
      session: session,
    );
  }

  Future<RecordingDownloadTarget?> _find({
    required String where,
    required List<Object?> whereArgs,
    required RecordingUploadSession session,
  }) async {
    validateRecordingUploadSession(session);
    await _requireRecordingSessionCurrent(_sessions, session);
    final Database db = await DatabaseNew.database;
    final List<Map<String, Object?>> rows = await db.query(
      'recordings',
      columns: <String>[
        'id',
        'BEId',
        'env',
        'userId',
        'mail',
        'partCount',
        'downloaded',
        'path',
      ],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    await _requireRecordingSessionCurrent(_sessions, session);
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    final int? localId = row['id'] as int?;
    final int? backendId = row['BEId'] as int?;
    if (localId == null || backendId == null) {
      throw FetchException('Recording has no durable download identity.', 409);
    }
    return RecordingDownloadTarget(
      localId: localId,
      backendId: backendId,
      environment: row['env'] as String? ?? '',
      ownerUserId: row['userId'] as int?,
      ownerEmail: row['mail'] as String?,
      expectedPartCount: row['partCount'] as int?,
      downloaded: row['downloaded'] == 1 || row['downloaded'] == true,
      path: row['path'] as String?,
    );
  }

  @override
  Future<List<RecordingDownloadPart>> loadParts(
    RecordingDownloadTarget target,
    RecordingUploadSession session,
  ) async {
    await _requireRecordingSessionCurrent(_sessions, session);
    final Database db = await DatabaseNew.database;
    final List<Map<String, Object?>> rows = await db.query(
      'recordingParts',
      columns: <String>[
        'id',
        'BEId',
        'recordingId',
        'backendRecordingId',
        'startTime',
        'path',
        'length',
      ],
      where: 'recordingId = ?',
      whereArgs: <Object?>[target.localId],
      orderBy: 'startTime ASC, id ASC',
    );
    await _requireRecordingSessionCurrent(_sessions, session);
    return rows.map((Map<String, Object?> row) {
      final int? localId = row['id'] as int?;
      final int? backendId = row['BEId'] as int?;
      final int? localRecordingId = row['recordingId'] as int?;
      final int? backendRecordingId = row['backendRecordingId'] as int?;
      if (localId == null ||
          backendId == null ||
          localRecordingId == null ||
          backendRecordingId == null) {
        throw FetchException(
          'Recording part has no durable download identity.',
          409,
        );
      }
      return RecordingDownloadPart(
        localId: localId,
        backendId: backendId,
        localRecordingId: localRecordingId,
        backendRecordingId: backendRecordingId,
        previousPath: row['path'] as String?,
        previousByteLength: row['length'] as int?,
      );
    }).toList(growable: false);
  }

  @override
  Future<bool> commitDownload(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  ) async {
    validateRecordingUploadSession(session);
    final RecordingDownloadTarget target = commit.target;
    if (target.environment != session.environment) {
      throw const RecordingUploadSessionChangedException();
    }
    await _requireRecordingSessionCurrent(_sessions, session);
    final Database db = await DatabaseNew.database;
    await _requireRecordingSessionCurrent(_sessions, session);
    return db.transaction<bool>((Transaction txn) async {
      final List<Map<String, Object?>> parentRows = await txn.query(
        'recordings',
        columns: const <String>['id'],
        where: 'id = ? AND BEId = ? AND env = ? '
            'AND userId IS ? AND mail IS ? '
            'AND COALESCE(downloaded, 0) = ? AND path IS ? '
            'AND (uploadLease IS NULL OR TRIM(uploadLease) = ?)',
        whereArgs: <Object?>[
          target.localId,
          target.backendId,
          target.environment,
          target.ownerUserId,
          target.ownerEmail,
          target.downloaded ? 1 : 0,
          target.path,
          '',
        ],
        limit: 1,
      );
      if (parentRows.length != 1) {
        throw const RecordingUploadSessionChangedException();
      }

      final List<Map<String, Object?>> currentPartRows = await txn.query(
        'recordingParts',
        columns: const <String>[
          'id',
          'BEId',
          'backendRecordingId',
        ],
        where: 'recordingId = ?',
        whereArgs: <Object?>[target.localId],
      );
      final Set<String> currentPartIdentities = currentPartRows
          .map(
            (Map<String, Object?> row) =>
                '${row['id']}:${row['BEId']}:${row['backendRecordingId']}',
          )
          .toSet();
      final Set<String> committedPartIdentities = commit.parts
          .map(
            (RecordingDownloadedPart part) =>
                '${part.localId}:${part.backendId}:${target.backendId}',
          )
          .toSet();
      if (currentPartRows.length != commit.parts.length ||
          currentPartIdentities.length != currentPartRows.length ||
          committedPartIdentities.length != commit.parts.length ||
          !currentPartIdentities.containsAll(committedPartIdentities)) {
        throw StateError(
          'Recording part identities changed before download commit.',
        );
      }

      for (final RecordingDownloadedPart part in commit.parts) {
        final int changed = await txn.update(
          'recordingParts',
          <String, Object?>{
            'path': part.path,
            'length': part.byteLength,
          },
          where: 'id = ? AND BEId = ? AND recordingId = ? '
              'AND backendRecordingId = ? AND COALESCE(sent, 0) = 1',
          whereArgs: <Object?>[
            part.localId,
            part.backendId,
            target.localId,
            target.backendId,
          ],
        );
        if (changed != 1) {
          throw StateError(
            'Recording part identity changed before download commit.',
          );
        }
      }

      final int parentChanged = await txn.update(
        'recordings',
        <String, Object?>{
          'path': commit.recordingPath,
          'downloaded': 1,
        },
        where: 'id = ? AND BEId = ? AND env = ? '
            'AND userId IS ? AND mail IS ? '
            'AND COALESCE(downloaded, 0) = ? AND path IS ? '
            'AND (uploadLease IS NULL OR TRIM(uploadLease) = ?)',
        whereArgs: <Object?>[
          target.localId,
          target.backendId,
          target.environment,
          target.ownerUserId,
          target.ownerEmail,
          target.downloaded ? 1 : 0,
          target.path,
          '',
        ],
      );
      if (parentChanged != 1) {
        throw const RecordingUploadSessionChangedException();
      }
      return true;
    });
  }

  @override
  Future<RecordingDownloadCommitState> reconcileDownloadCommit(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  ) async {
    validateRecordingUploadSession(session);
    final RecordingDownloadTarget target = commit.target;
    if (target.environment != session.environment) {
      return RecordingDownloadCommitState.unknown;
    }

    final Database db = await DatabaseNew.database;
    final List<Map<String, Object?>> parentRows = await db.query(
      'recordings',
      columns: const <String>[
        'id',
        'BEId',
        'env',
        'userId',
        'mail',
        'downloaded',
        'path',
      ],
      where: 'id = ?',
      whereArgs: <Object?>[target.localId],
      limit: 1,
    );
    if (parentRows.length != 1) {
      return RecordingDownloadCommitState.unknown;
    }
    final Map<String, Object?> parent = parentRows.single;
    if (parent['id'] != target.localId ||
        parent['BEId'] != target.backendId ||
        parent['env'] != target.environment ||
        parent['userId'] != target.ownerUserId ||
        parent['mail'] != target.ownerEmail) {
      return RecordingDownloadCommitState.unknown;
    }

    final List<Map<String, Object?>> partRows = await db.query(
      'recordingParts',
      columns: const <String>[
        'id',
        'BEId',
        'recordingId',
        'backendRecordingId',
        'path',
        'length',
      ],
      where: 'recordingId = ?',
      whereArgs: <Object?>[target.localId],
    );
    if (partRows.length != commit.parts.length) {
      return RecordingDownloadCommitState.unknown;
    }
    final Map<int, Map<String, Object?>> rowsByLocalId =
        <int, Map<String, Object?>>{};
    for (final Map<String, Object?> row in partRows) {
      final Object? rawId = row['id'];
      if (rawId is! int || rowsByLocalId.containsKey(rawId)) {
        return RecordingDownloadCommitState.unknown;
      }
      rowsByLocalId[rawId] = row;
    }

    bool partsCommitted = true;
    bool partsAbsent = true;
    for (final RecordingDownloadedPart part in commit.parts) {
      final Map<String, Object?>? row = rowsByLocalId[part.localId];
      if (row == null ||
          row['BEId'] != part.backendId ||
          row['recordingId'] != target.localId ||
          row['backendRecordingId'] != target.backendId) {
        return RecordingDownloadCommitState.unknown;
      }
      partsCommitted = partsCommitted &&
          row['path'] == part.path &&
          row['length'] == part.byteLength;
      partsAbsent = partsAbsent &&
          row['path'] == part.previousPath &&
          row['length'] == part.previousByteLength;
    }

    final bool parentDownloaded =
        parent['downloaded'] == 1 || parent['downloaded'] == true;
    final bool parentCommitted =
        parentDownloaded && parent['path'] == commit.recordingPath;
    final bool parentAbsent =
        parentDownloaded == target.downloaded && parent['path'] == target.path;
    if (parentCommitted && partsCommitted) {
      return RecordingDownloadCommitState.committed;
    }
    if (parentAbsent && partsAbsent) {
      return RecordingDownloadCommitState.absent;
    }
    return RecordingDownloadCommitState.unknown;
  }
}

class _ControllerRecordingDownloadApi implements RecordingDownloadApi {
  const _ControllerRecordingDownloadApi();

  @override
  Future<List<int>> downloadPart({
    required int backendRecordingId,
    required int backendPartId,
    required RecordingUploadSession session,
    CancelToken? cancelToken,
    RecordingPartDownloadProgress? onProgress,
  }) async {
    final Response<List<int>> response =
        await _recordingPartsApi.downloadPartSound(
      backendPartId,
      accessToken: session.accessToken,
      host: session.backendHost,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
    if (response.statusCode != 200 || response.data == null) {
      throw FetchException(
        'Failed to download a recording part.',
        response.statusCode ?? 500,
      );
    }
    return response.data!;
  }
}

class _IoRecordingDownloadFiles implements RecordingDownloadFiles {
  const _IoRecordingDownloadFiles();

  @override
  Future<bool> isReadable(String path) async {
    final File file = File(path);
    if (!await file.exists()) return false;
    RandomAccessFile? handle;
    bool readable = false;
    try {
      handle = await file.open(mode: FileMode.read);
      readable = await handle.length() > 0;
    } on FileSystemException {
      readable = false;
    } finally {
      try {
        await handle?.close();
      } on FileSystemException {
        readable = false;
      }
    }
    return readable;
  }

  @override
  Future<String> reservePath({
    required int localRecordingId,
    required int backendRecordingId,
    int? backendPartId,
  }) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    for (int attempt = 0; attempt < 4; attempt++) {
      final String kind =
          backendPartId == null ? 'recording-download' : 'recording-part';
      final String path = '${directory.path}/$kind-'
          '${_newUploadKey('staged')}'
          '-l$localRecordingId-b$backendRecordingId'
          '${backendPartId == null ? '' : '-p$backendPartId'}.wav';
      final File file = File(path);
      try {
        await file.create(recursive: true, exclusive: true);
        return path;
      } on FileSystemException {
        if (!await file.exists()) rethrow;
      }
    }
    throw FileSystemException('Could not reserve a unique download path.');
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> concatenate(
    List<String> partPaths,
    String outputPath,
  ) {
    return concatWavFiles(
      partPaths,
      outputPath,
      outputAlreadyReserved: true,
    );
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
