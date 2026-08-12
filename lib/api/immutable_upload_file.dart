import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A permanent pre-network rejection: the local source no longer matches the
/// fingerprint that was durably frozen for this idempotency key.
///
/// Operational failures while creating, writing, opening, or deleting the
/// private stage deliberately keep their native I/O exception type so callers
/// can retry them instead of misclassifying them as bad recording content.
class ImmutableUploadSourceException implements IOException {
  const ImmutableUploadSourceException(
    this.message,
    this.path, [
    this.cause,
  ]);

  final String message;
  final String path;
  final Object? cause;

  @override
  String toString() {
    final String suffix = cause == null ? '' : ' ($cause)';
    return 'ImmutableUploadSourceException: $message, path = $path$suffix';
  }
}

/// A replayable multipart source whose bytes and length cannot depend on the
/// original recording path after the snapshot has been created.
abstract interface class ReplayableUploadFile {
  String get filename;

  int get byteLength;

  /// Returns a new, single-subscription stream for one HTTP request.
  ///
  /// Callers must consume requests sequentially. This is exactly what the
  /// one-redirect upload flow does: the first response is received before a
  /// replay stream is requested.
  Stream<List<int>> openRead();
}

class UploadSourceVersion {
  const UploadSourceVersion({
    required this.isFile,
    required this.size,
    required this.modified,
    required this.changed,
  });

  final bool isFile;
  final int size;
  final DateTime modified;
  final DateTime changed;

  bool matches(UploadSourceVersion? other) {
    return other != null &&
        isFile == other.isFile &&
        size == other.size &&
        modified == other.modified &&
        changed == other.changed;
  }
}

class UploadStageLocation {
  const UploadStageLocation({
    required this.rootPath,
    required this.filePath,
  });

  final String rootPath;
  final String filePath;
}

abstract interface class UploadSnapshotReadHandle {
  Future<void> setPosition(int position);

  Future<List<int>> read(int byteCount);

  Future<void> close();
}

/// File operations are injectable so snapshot behavior can be tested without
/// touching a real database, API, network, or filesystem.
abstract interface class UploadFileStagingOperations {
  Future<void> deleteStaleStages({required DateTime olderThan});

  Future<UploadSourceVersion?> stat(String path);

  Stream<List<int>> openRead(String path);

  Future<UploadStageLocation> createPrivateStage();

  Future<void> writeStream(String path, Stream<List<int>> bytes);

  Future<UploadSnapshotReadHandle> openReadHandle(String path);

  Future<void> deleteStage(UploadStageLocation location);
}

class IoUploadFileStagingOperations implements UploadFileStagingOperations {
  const IoUploadFileStagingOperations();

  static const String _stagePrefix = 'strnadi-upload-';
  static const int _maximumCleanupEntries = 128;
  static Future<void>? _processCleanup;

  @override
  Future<void> deleteStaleStages({required DateTime olderThan}) {
    return _processCleanup ??= _deleteStaleStages(olderThan);
  }

  Future<void> _deleteStaleStages(DateTime olderThan) async {
    var inspected = 0;
    try {
      await for (final FileSystemEntity entity
          in Directory.systemTemp.list(followLinks: false)) {
        if (inspected >= _maximumCleanupEntries) break;
        inspected++;
        if (entity is! Directory ||
            !_lastPathComponent(entity.path).startsWith(_stagePrefix)) {
          continue;
        }
        try {
          final FileStat stat = await entity.stat();
          if (stat.modified.toUtc().isBefore(olderThan.toUtc())) {
            await entity.delete(recursive: true);
          }
        } catch (_) {
          // A stale orphan is ancillary to the current upload.
        }
      }
    } catch (_) {
      // Temp-directory enumeration must never block a current upload.
    }
  }

  @override
  Future<UploadSourceVersion?> stat(String path) async {
    try {
      final FileStat stat = await File(path).stat();
      return UploadSourceVersion(
        isFile: stat.type == FileSystemEntityType.file,
        size: stat.size,
        modified: stat.modified,
        changed: stat.changed,
      );
    } on FileSystemException {
      return null;
    }
  }

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  Future<UploadStageLocation> createPrivateStage() async {
    final Directory directory =
        await Directory.systemTemp.createTemp('strnadi-upload-');
    final File file = File('${directory.path}/snapshot');
    try {
      await file.create(exclusive: true);
      return UploadStageLocation(
        rootPath: directory.path,
        filePath: file.path,
      );
    } catch (error, stackTrace) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {
        // Preserve the stage-creation failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> writeStream(String path, Stream<List<int>> bytes) async {
    final RandomAccessFile output =
        await File(path).open(mode: FileMode.writeOnly);
    try {
      await for (final List<int> chunk in bytes) {
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }

  @override
  Future<UploadSnapshotReadHandle> openReadHandle(String path) async {
    return _IoUploadSnapshotReadHandle(
      await File(path).open(mode: FileMode.read),
    );
  }

  @override
  Future<void> deleteStage(UploadStageLocation location) async {
    final Directory directory = Directory(location.rootPath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _IoUploadSnapshotReadHandle implements UploadSnapshotReadHandle {
  _IoUploadSnapshotReadHandle(this._file);

  final RandomAccessFile _file;

  @override
  Future<void> setPosition(int position) async {
    await _file.setPosition(position);
  }

  @override
  Future<List<int>> read(int byteCount) => _file.read(byteCount);

  @override
  Future<void> close() => _file.close();
}

/// Copies a recording to a private temporary file while hashing it.
///
/// The returned snapshot owns an already-open read handle. Replays therefore
/// read the same staged inode, even if the original path is replaced or edited
/// after validation. Only a bounded chunk is held in memory at any time.
class ImmutableUploadSnapshotFactory {
  const ImmutableUploadSnapshotFactory({
    this.operations = const IoUploadFileStagingOperations(),
    this.staleStageLifetime = const Duration(hours: 24),
    this.now = _currentTime,
  });

  final UploadFileStagingOperations operations;
  final Duration staleStageLifetime;
  final DateTime Function() now;

  Future<ImmutableUploadFileSnapshot> stage({
    required String sourcePath,
    required String expectedSha256,
    required int expectedByteLength,
    void Function(Object error, StackTrace stackTrace)? onCleanupError,
  }) async {
    try {
      await operations.deleteStaleStages(
        olderThan: now().toUtc().subtract(staleStageLifetime),
      );
    } catch (_) {
      // Crash-leftover cleanup is best effort and must not block this upload.
    }

    final String normalizedHash = expectedSha256.trim().toLowerCase();
    if (sourcePath.trim().isEmpty ||
        expectedByteLength <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw ImmutableUploadSourceException(
        'The recording upload fingerprint is invalid.',
        sourcePath,
      );
    }

    final UploadSourceVersion? before = await operations.stat(sourcePath);
    if (before == null || !before.isFile || before.size != expectedByteLength) {
      throw ImmutableUploadSourceException(
        'The recording changed before an immutable upload snapshot could be '
        'created.',
        sourcePath,
      );
    }

    UploadStageLocation? location;
    try {
      location = await operations.createPrivateStage();
      final _SingleDigestSink digestOutput = _SingleDigestSink();
      final ByteConversionSink digestInput =
          sha256.startChunkedConversion(digestOutput);
      var copiedBytes = 0;

      Stream<List<int>> verifiedSource() async* {
        try {
          await for (final List<int> chunk in operations.openRead(sourcePath)) {
            if (chunk.isEmpty) continue;
            copiedBytes += chunk.length;
            if (copiedBytes > expectedByteLength) {
              throw ImmutableUploadSourceException(
                'The recording grew while its upload snapshot was being made.',
                sourcePath,
              );
            }
            digestInput.add(chunk);
            yield chunk;
          }
        } on ImmutableUploadSourceException {
          rethrow;
        } on FileSystemException catch (error) {
          throw ImmutableUploadSourceException(
            'The recording became unreadable while its upload snapshot was '
            'being made.',
            sourcePath,
            error,
          );
        }
      }

      try {
        await operations.writeStream(location.filePath, verifiedSource());
      } finally {
        digestInput.close();
      }

      final UploadSourceVersion? after = await operations.stat(sourcePath);
      final String? copiedHash = digestOutput.value?.toString().toLowerCase();
      if (!before.matches(after) ||
          copiedBytes != expectedByteLength ||
          copiedHash != normalizedHash) {
        throw ImmutableUploadSourceException(
          'The recording changed while its immutable upload snapshot was '
          'being made.',
          sourcePath,
        );
      }

      final UploadSourceVersion? staged =
          await operations.stat(location.filePath);
      if (staged == null ||
          !staged.isFile ||
          staged.size != expectedByteLength) {
        throw FileSystemException(
          'The immutable recording upload snapshot is incomplete.',
          sourcePath,
        );
      }

      final UploadSnapshotReadHandle handle =
          await operations.openReadHandle(location.filePath);
      return ImmutableUploadFileSnapshot._(
        filename: _uploadFilename(sourcePath),
        byteLength: expectedByteLength,
        handle: handle,
        location: location,
        operations: operations,
      );
    } catch (error, stackTrace) {
      if (location != null) {
        try {
          await operations.deleteStage(location);
        } catch (cleanupError, cleanupStackTrace) {
          try {
            onCleanupError?.call(cleanupError, cleanupStackTrace);
          } catch (_) {
            // Reporting must not replace the source/staging failure.
          }
          // Preserve the fingerprint/copy/open failure.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

class ImmutableUploadFileSnapshot implements ReplayableUploadFile {
  ImmutableUploadFileSnapshot._({
    required this.filename,
    required this.byteLength,
    required UploadSnapshotReadHandle handle,
    required UploadStageLocation location,
    required UploadFileStagingOperations operations,
  })  : _handle = handle,
        _location = location,
        _operations = operations;

  static const int _chunkSize = 64 * 1024;

  @override
  final String filename;

  @override
  final int byteLength;

  final UploadSnapshotReadHandle _handle;
  final UploadStageLocation _location;
  final UploadFileStagingOperations _operations;
  bool _active = false;
  bool _disposed = false;

  @override
  Stream<List<int>> openRead() async* {
    if (_disposed) {
      throw StateError('The immutable upload snapshot was already disposed.');
    }
    if (_active) {
      throw StateError(
        'Immutable upload snapshot streams must be consumed sequentially.',
      );
    }
    _active = true;
    try {
      await _handle.setPosition(0);
      var remaining = byteLength;
      while (remaining > 0) {
        final List<int> chunk =
            await _handle.read(remaining < _chunkSize ? remaining : _chunkSize);
        if (chunk.isEmpty) {
          throw FileSystemException(
            'The immutable upload snapshot ended unexpectedly.',
            _location.filePath,
          );
        }
        remaining -= chunk.length;
        yield chunk;
      }
    } finally {
      _active = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await _handle.close();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }

    try {
      await _operations.deleteStage(_location);
    } catch (error, stackTrace) {
      if (closeError == null) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (closeError != null) {
      Error.throwWithStackTrace(closeError, closeStackTrace!);
    }
  }
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    if (value != null) {
      throw StateError('The upload digest was produced more than once.');
    }
    value = data;
  }

  @override
  void close() {}
}

String _uploadFilename(String sourcePath) {
  final String normalized = sourcePath.replaceAll(r'\', '/');
  final int separator = normalized.lastIndexOf('/');
  var filename =
      (separator < 0 ? normalized : normalized.substring(separator + 1)).trim();
  if (filename.isEmpty) return 'recording-part.wav';
  filename = filename.replaceAll(RegExp(r'[\r\n"]'), '_');
  if (filename.length > 200) {
    filename = filename.substring(filename.length - 200);
  }
  return filename;
}

String _lastPathComponent(String path) {
  final String normalized = path.replaceAll(r'\', '/');
  final int separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

DateTime _currentTime() => DateTime.now();
