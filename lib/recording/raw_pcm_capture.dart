/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:io';

typedef RawPcmStreamStarter = Future<Stream<List<int>>> Function();

const Duration defaultRawPcmDrainTimeout = Duration(seconds: 5);
const Duration defaultRawPcmAbortTimeout = Duration(seconds: 1);

abstract interface class RawPcmWriter {
  Future<void> write(List<int> bytes);

  Future<void> flush();

  Future<void> close();
}

abstract interface class RawPcmFileAllocator {
  /// Returns an open writer when [path] was reserved exclusively.
  ///
  /// A `null` result means that the path already exists and another
  /// candidate must be tried.
  Future<RawPcmWriter?> tryReserveExclusive(String path);
}

class ReservedRawPcmFile {
  final String path;
  final RawPcmWriter writer;

  const ReservedRawPcmFile({
    required this.path,
    required this.writer,
  });
}

class IoRawPcmFileAllocator implements RawPcmFileAllocator {
  const IoRawPcmFileAllocator();

  @override
  Future<RawPcmWriter?> tryReserveExclusive(String path) async {
    final File file = File(path);
    try {
      await file.create(recursive: true, exclusive: true);
    } on FileSystemException {
      if (await file.exists()) {
        return null;
      }
      rethrow;
    }

    // The file has already been created exclusively. Append mode preserves
    // that reservation and avoids a second create/truncate operation.
    final RandomAccessFile handle =
        await file.open(mode: FileMode.writeOnlyAppend);
    return _IoRawPcmWriter(handle);
  }
}

class _IoRawPcmWriter implements RawPcmWriter {
  final RandomAccessFile _handle;

  _IoRawPcmWriter(this._handle);

  @override
  Future<void> write(List<int> bytes) => _handle.writeFrom(bytes);

  @override
  Future<void> flush() => _handle.flush();

  @override
  Future<void> close() => _handle.close();
}

Future<ReservedRawPcmFile> reserveUnusedRawPcmFile({
  required String Function() nextCandidate,
  RawPcmFileAllocator allocator = const IoRawPcmFileAllocator(),
  Set<String> excludedPaths = const <String>{},
  int maxAttempts = 100,
}) async {
  if (maxAttempts <= 0) {
    throw RangeError.value(
      maxAttempts,
      'maxAttempts',
      'Must be greater than zero.',
    );
  }

  for (int attempt = 0; attempt < maxAttempts; attempt += 1) {
    final String candidate = nextCandidate();
    if (candidate.isEmpty || excludedPaths.contains(candidate)) {
      continue;
    }

    final RawPcmWriter? writer = await allocator.tryReserveExclusive(candidate);
    if (writer != null) {
      return ReservedRawPcmFile(path: candidate, writer: writer);
    }
  }

  throw StateError(
    'Could not reserve a distinct raw recording path after '
    '$maxAttempts attempts.',
  );
}

class RawPcmCaptureAbortedException implements Exception {
  final String path;

  const RawPcmCaptureAbortedException(this.path);

  @override
  String toString() => 'Raw PCM capture was aborted for $path.';
}

class RawPcmCaptureDrainTimeoutException implements TimeoutException {
  final String path;
  final bool cleanupTimedOut;

  @override
  final Duration duration;

  const RawPcmCaptureDrainTimeoutException(
    this.path,
    this.duration, {
    required this.cleanupTimedOut,
  });

  @override
  String get message =>
      'Raw PCM stream for $path did not close after recorder stop.';

  @override
  String toString() =>
      'RawPcmCaptureDrainTimeoutException after $duration: $message';
}

class RawPcmCaptureAbortTimeoutException implements TimeoutException {
  final String path;

  @override
  final Duration duration;

  const RawPcmCaptureAbortTimeoutException(this.path, this.duration);

  @override
  String get message => 'Raw PCM cleanup for $path did not complete.';

  @override
  String toString() =>
      'RawPcmCaptureAbortTimeoutException after $duration: $message';
}

class ContainerizedAudioStreamException implements FormatException {
  final String container;

  const ContainerizedAudioStreamException(this.container);

  @override
  String get message =>
      'Expected raw PCM bytes, but the recorder streamed a $container header.';

  @override
  dynamic get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => 'ContainerizedAudioStreamException: $message';
}

/// Owns one raw PCM stream and its exclusively reserved output file.
///
/// Writes are serialized by the `StreamIterator` loop. [finish] is the drain
/// barrier: it completes only after the source closes, every queued write is
/// done, and the file has been flushed and closed. Capture errors are retained
/// and rethrown from [finish], so callers can safely preserve the raw file.
class RawPcmCapture {
  final String path;
  final RawPcmWriter _writer;
  final StreamIterator<List<int>> _iterator;
  final _ContainerHeaderProbe _headerProbe = _ContainerHeaderProbe();

  late final Future<void> _consumeFuture;
  Object? _failure;
  StackTrace? _failureStackTrace;
  bool _aborted = false;
  Future<void>? _abortFuture;

  RawPcmCapture._({
    required this.path,
    required RawPcmWriter writer,
    required Stream<List<int>> stream,
  })  : _writer = writer,
        _iterator = StreamIterator<List<int>>(stream) {
    _consumeFuture = _consume();
  }

  static Future<RawPcmCapture> start({
    required ReservedRawPcmFile reservedFile,
    required RawPcmStreamStarter startStream,
  }) async {
    try {
      final Stream<List<int>> stream = await startStream();
      return RawPcmCapture._(
        path: reservedFile.path,
        writer: reservedFile.writer,
        stream: stream,
      );
    } catch (error, stackTrace) {
      try {
        await reservedFile.writer.close();
      } catch (_) {
        // Preserve the recorder/start error and the exclusively reserved file.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _consume() async {
    try {
      while (await _iterator.moveNext()) {
        final List<int> chunk = _iterator.current;
        if (chunk.isEmpty) {
          continue;
        }
        _headerProbe.add(chunk);
        await _writer.write(chunk);
      }
      await _writer.flush();
    } catch (error, stackTrace) {
      _failure ??= error;
      _failureStackTrace ??= stackTrace;
      try {
        await _iterator.cancel();
      } catch (_) {
        // Preserve the first stream/write failure.
      }
    } finally {
      try {
        await _writer.close();
      } catch (error, stackTrace) {
        _failure ??= error;
        _failureStackTrace ??= stackTrace;
      }
    }
  }

  Future<void> finish({
    Duration timeout = defaultRawPcmDrainTimeout,
    Duration abortTimeout = defaultRawPcmAbortTimeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Must be greater than zero.',
      );
    }
    if (abortTimeout <= Duration.zero) {
      throw ArgumentError.value(
        abortTimeout,
        'abortTimeout',
        'Must be greater than zero.',
      );
    }

    try {
      await _consumeFuture.timeout(timeout);
    } on TimeoutException {
      bool cleanupTimedOut = false;
      try {
        await abort(timeout: abortTimeout);
      } on RawPcmCaptureAbortTimeoutException {
        cleanupTimedOut = true;
      }
      throw RawPcmCaptureDrainTimeoutException(
        path,
        timeout,
        cleanupTimedOut: cleanupTimedOut,
      );
    }
    if (_aborted) {
      throw RawPcmCaptureAbortedException(path);
    }
    final Object? failure = _failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, _failureStackTrace!);
    }
  }

  /// Cancels the source and drains any write that was already in progress.
  ///
  /// An aborted capture can never be finalized as a valid segment.
  Future<void> abort({
    Duration timeout = defaultRawPcmAbortTimeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Must be greater than zero.',
      );
    }

    final Future<void> cleanup = _abortFuture ??= _performAbort();
    try {
      await cleanup.timeout(timeout);
    } on TimeoutException {
      throw RawPcmCaptureAbortTimeoutException(path, timeout);
    }
  }

  Future<void> _performAbort() async {
    _aborted = true;
    try {
      await _iterator.cancel();
    } catch (error, stackTrace) {
      _failure ??= error;
      _failureStackTrace ??= stackTrace;
    }
    await _consumeFuture;
  }
}

class _ContainerHeaderProbe {
  final List<int> _prefix = <int>[];
  bool _validated = false;

  void add(List<int> bytes) {
    if (_validated) return;

    final int remaining = 12 - _prefix.length;
    if (remaining > 0) {
      _prefix.addAll(bytes.take(remaining));
    }

    if (_hasAsciiAt(_prefix, 0, 'caff')) {
      throw const ContainerizedAudioStreamException('CAF');
    }

    if (_prefix.length < 12) return;
    _validated = true;

    if (_hasAsciiAt(_prefix, 0, 'RIFF') && _hasAsciiAt(_prefix, 8, 'WAVE')) {
      throw const ContainerizedAudioStreamException('WAV');
    }
    if (_hasAsciiAt(_prefix, 0, 'FORM') &&
        (_hasAsciiAt(_prefix, 8, 'AIFF') || _hasAsciiAt(_prefix, 8, 'AIFC'))) {
      throw const ContainerizedAudioStreamException('AIFF');
    }
  }
}

bool _hasAsciiAt(List<int> bytes, int offset, String value) {
  if (bytes.length < offset + value.length) return false;
  for (int index = 0; index < value.length; index += 1) {
    if (bytes[offset + index] != value.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}
