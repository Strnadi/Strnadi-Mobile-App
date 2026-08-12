import 'package:dio/dio.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

typedef RecordingDownloadProgress = void Function(double progress);
typedef RecordingPartDownloadProgress = void Function(
  int received,
  int total,
);

class RecordingDownloadTarget {
  const RecordingDownloadTarget({
    required this.localId,
    required this.backendId,
    required this.environment,
    required this.ownerUserId,
    required this.ownerEmail,
    required this.expectedPartCount,
    required this.downloaded,
    required this.path,
  });

  final int localId;
  final int backendId;
  final String environment;
  final int? ownerUserId;
  final String? ownerEmail;
  final int? expectedPartCount;
  final bool downloaded;
  final String? path;
}

class RecordingDownloadPart {
  const RecordingDownloadPart({
    required this.localId,
    required this.backendId,
    required this.localRecordingId,
    required this.backendRecordingId,
    required this.previousPath,
    required this.previousByteLength,
  });

  final int localId;
  final int backendId;
  final int localRecordingId;
  final int backendRecordingId;
  final String? previousPath;
  final int? previousByteLength;
}

class RecordingDownloadedPart {
  const RecordingDownloadedPart({
    required this.localId,
    required this.backendId,
    required this.path,
    required this.byteLength,
    required this.previousPath,
    required this.previousByteLength,
  });

  final int localId;
  final int backendId;
  final String path;
  final int byteLength;
  final String? previousPath;
  final int? previousByteLength;
}

class RecordingDownloadCommit {
  const RecordingDownloadCommit({
    required this.target,
    required this.parts,
    required this.recordingPath,
  });

  final RecordingDownloadTarget target;
  final List<RecordingDownloadedPart> parts;
  final String recordingPath;
}

enum RecordingDownloadCommitState {
  committed,
  absent,
  unknown,
}

class RecordingDownloadCommitStateUnknownException implements Exception {
  const RecordingDownloadCommitStateUnknownException({
    required this.commitFailure,
    this.reconciliationFailure,
  });

  final Object commitFailure;
  final Object? reconciliationFailure;

  @override
  String toString() => 'RecordingDownloadCommitStateUnknownException';
}

abstract interface class RecordingDownloadStore {
  Future<RecordingDownloadTarget?> findByLocalId(
    int localId,
    RecordingUploadSession session,
  );

  Future<RecordingDownloadTarget?> findByBackendId(
    int backendId,
    RecordingUploadSession session,
  );

  Future<List<RecordingDownloadPart>> loadParts(
    RecordingDownloadTarget target,
    RecordingUploadSession session,
  );

  /// Atomically persists every part path and the concatenated parent path.
  ///
  /// Returning `true` acknowledges that the complete transaction committed.
  /// Returning `false` means no staged file may be retained.
  Future<bool> commitDownload(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  );

  /// Determines the exact durable state after an unacknowledged commit.
  ///
  /// Implementations must compare the parent and complete part identity/path
  /// set against both the pre-commit and requested post-commit snapshots.
  Future<RecordingDownloadCommitState> reconcileDownloadCommit(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  );
}

abstract interface class RecordingDownloadApi {
  Future<List<int>> downloadPart({
    required int backendRecordingId,
    required int backendPartId,
    required RecordingUploadSession session,
    CancelToken? cancelToken,
    RecordingPartDownloadProgress? onProgress,
  });
}

abstract interface class RecordingDownloadFiles {
  Future<bool> isReadable(String path);

  /// Reserves an exclusively owned, empty staging path.
  Future<String> reservePath({
    required int localRecordingId,
    required int backendRecordingId,
    int? backendPartId,
  });

  Future<void> writeBytes(String path, List<int> bytes);

  /// Concatenates into an already reserved output path.
  Future<void> concatenate(List<String> partPaths, String outputPath);

  Future<void> deleteIfExists(String path);
}

class RecordingDownloadService {
  const RecordingDownloadService({
    required RecordingDownloadStore store,
    required RecordingDownloadApi api,
    required RecordingUploadSessionProvider sessions,
    required RecordingDownloadFiles files,
  })  : _store = store,
        _api = api,
        _sessions = sessions,
        _files = files;

  final RecordingDownloadStore _store;
  final RecordingDownloadApi _api;
  final RecordingUploadSessionProvider _sessions;
  final RecordingDownloadFiles _files;

  Future<int> downloadByLocalId(
    int localId, {
    RecordingDownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (localId <= 0) {
      throw FetchException('Recording has an invalid local id.', 400);
    }
    return _download(
      lookup: (RecordingUploadSession session) =>
          _store.findByLocalId(localId, session),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<int> downloadByBackendId(
    int backendId, {
    RecordingDownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (backendId <= 0) {
      throw FetchException('Recording has an invalid backend id.', 400);
    }
    return _download(
      lookup: (RecordingUploadSession session) =>
          _store.findByBackendId(backendId, session),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  Future<int> _download({
    required Future<RecordingDownloadTarget?> Function(
      RecordingUploadSession session,
    ) lookup,
    RecordingDownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    _throwIfCancelled(cancelToken);
    final RecordingUploadSession? session = await _sessions.capture();
    if (session == null) {
      throw FetchException('A verified session is required to download.', 401);
    }
    validateRecordingUploadSession(session);
    await _requireCurrent(session);
    _throwIfCancelled(cancelToken);

    final RecordingDownloadTarget? target = await lookup(session);
    if (target == null) {
      throw FetchException('Recording was not found for download.', 404);
    }
    _validateTarget(target, session);
    await _requireCurrent(session);
    _throwIfCancelled(cancelToken);

    if (target.downloaded && (target.path?.trim().isNotEmpty ?? false)) {
      final bool readable = await _files.isReadable(target.path!);
      await _requireCurrent(session);
      _throwIfCancelled(cancelToken);
      if (readable) {
        _notify(onProgress, 1);
        return target.localId;
      }
    }

    final List<RecordingDownloadPart> parts =
        await _store.loadParts(target, session);
    _validateParts(target, parts);
    await _requireCurrent(session);
    _throwIfCancelled(cancelToken);

    final List<String> stagedPaths = <String>[];
    final List<RecordingDownloadedPart> downloadedParts =
        <RecordingDownloadedPart>[];
    bool retainStagedFiles = false;
    try {
      _notify(onProgress, 0);
      for (int index = 0; index < parts.length; index++) {
        final RecordingDownloadPart part = parts[index];
        double partProgress = 0;
        _notifyPartProgress(
          onProgress,
          completedParts: index,
          partProgress: partProgress,
          partCount: parts.length,
        );

        final List<int> bytes = await _api.downloadPart(
          backendRecordingId: target.backendId,
          backendPartId: part.backendId,
          session: session,
          cancelToken: cancelToken,
          onProgress: (int received, int total) {
            if (total <= 0) return;
            partProgress = (received / total).clamp(0, 1).toDouble();
            _notifyPartProgress(
              onProgress,
              completedParts: index,
              partProgress: partProgress,
              partCount: parts.length,
            );
          },
        );
        _throwIfCancelled(cancelToken);
        await _requireCurrent(session);

        final String partPath = await _files.reservePath(
          localRecordingId: target.localId,
          backendRecordingId: target.backendId,
          backendPartId: part.backendId,
        );
        stagedPaths.add(partPath);
        await _files.writeBytes(partPath, bytes);
        _throwIfCancelled(cancelToken);
        await _requireCurrent(session);

        downloadedParts.add(
          RecordingDownloadedPart(
            localId: part.localId,
            backendId: part.backendId,
            path: partPath,
            byteLength: bytes.length,
            previousPath: part.previousPath,
            previousByteLength: part.previousByteLength,
          ),
        );
        _notifyPartProgress(
          onProgress,
          completedParts: index + 1,
          partProgress: 0,
          partCount: parts.length,
        );
      }

      final String outputPath = await _files.reservePath(
        localRecordingId: target.localId,
        backendRecordingId: target.backendId,
      );
      stagedPaths.add(outputPath);
      await _files.concatenate(
        downloadedParts
            .map((RecordingDownloadedPart part) => part.path)
            .toList(growable: false),
        outputPath,
      );
      _throwIfCancelled(cancelToken);
      await _requireCurrent(session);

      final RecordingDownloadCommit commit = RecordingDownloadCommit(
        target: target,
        parts: List<RecordingDownloadedPart>.unmodifiable(downloadedParts),
        recordingPath: outputPath,
      );
      bool acknowledged = false;
      Object? commitFailure;
      StackTrace? commitFailureStackTrace;
      try {
        acknowledged = await _store.commitDownload(commit, session);
      } catch (error, stackTrace) {
        commitFailure = error;
        commitFailureStackTrace = stackTrace;
      }

      if (commitFailure != null) {
        late final RecordingDownloadCommitState reconciledState;
        try {
          reconciledState = await _store.reconcileDownloadCommit(
            commit,
            session,
          );
        } catch (reconciliationFailure, reconciliationStackTrace) {
          retainStagedFiles = true;
          Error.throwWithStackTrace(
            RecordingDownloadCommitStateUnknownException(
              commitFailure: commitFailure,
              reconciliationFailure: reconciliationFailure,
            ),
            reconciliationStackTrace,
          );
        }
        switch (reconciledState) {
          case RecordingDownloadCommitState.committed:
            acknowledged = true;
            break;
          case RecordingDownloadCommitState.absent:
            Error.throwWithStackTrace(
              commitFailure,
              commitFailureStackTrace!,
            );
          case RecordingDownloadCommitState.unknown:
            retainStagedFiles = true;
            throw RecordingDownloadCommitStateUnknownException(
              commitFailure: commitFailure,
            );
        }
      }

      if (!acknowledged) {
        throw StateError('Recording download commit was not acknowledged.');
      }
      retainStagedFiles = true;
      await _requireCurrent(session);
      _notify(onProgress, 1);
      return target.localId;
    } finally {
      if (!retainStagedFiles) {
        for (final String path in stagedPaths.reversed) {
          try {
            await _files.deleteIfExists(path);
          } catch (_) {
            // Preserve the original download, cancellation, or commit error.
          }
        }
      }
    }
  }

  Future<void> _requireCurrent(RecordingUploadSession session) async {
    if (!await _sessions.isCurrent(session)) {
      throw const RecordingUploadSessionChangedException();
    }
  }

  void _validateTarget(
    RecordingDownloadTarget target,
    RecordingUploadSession session,
  ) {
    if (target.localId <= 0 ||
        target.backendId <= 0 ||
        target.environment != session.environment) {
      throw const RecordingUploadSessionChangedException();
    }
  }

  void _validateParts(
    RecordingDownloadTarget target,
    List<RecordingDownloadPart> parts,
  ) {
    if (parts.isEmpty) {
      throw FetchException('Recording has no downloadable parts.', 422);
    }
    final int? expectedPartCount = target.expectedPartCount;
    if (expectedPartCount != null &&
        expectedPartCount > 0 &&
        expectedPartCount != parts.length) {
      throw FetchException(
        'Recording part count does not match its durable metadata.',
        409,
      );
    }
    final Set<int> localIds = <int>{};
    final Set<int> backendIds = <int>{};
    for (final RecordingDownloadPart part in parts) {
      if (part.localId <= 0 ||
          part.backendId <= 0 ||
          part.localRecordingId != target.localId ||
          part.backendRecordingId != target.backendId ||
          !localIds.add(part.localId) ||
          !backendIds.add(part.backendId)) {
        throw FetchException('Recording part identity is inconsistent.', 409);
      }
    }
  }

  void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) {
      throw cancelToken!.cancelError!;
    }
  }

  void _notify(RecordingDownloadProgress? onProgress, double progress) {
    if (onProgress == null) return;
    try {
      onProgress(progress.clamp(0, 1).toDouble());
    } catch (_) {
      // UI progress is advisory and must never alter download durability.
    }
  }

  void _notifyPartProgress(
    RecordingDownloadProgress? onProgress, {
    required int completedParts,
    required double partProgress,
    required int partCount,
  }) {
    _notify(
      onProgress,
      (completedParts + partProgress) / partCount,
    );
  }
}
