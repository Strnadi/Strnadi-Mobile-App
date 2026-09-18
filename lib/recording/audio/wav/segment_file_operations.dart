/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
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
import 'dart:io';
import 'dart:typed_data';

abstract interface class SegmentFileOperations {
  Future<int> length(String path);

  Future<bool> refersToSameFile(String firstPath, String secondPath);

  Future<void> createExclusive(String path);

  Future<Uint8List> readRange(
    String path, {
    required int start,
    required int length,
  });

  Stream<List<int>> readChunks(
    String path, {
    required int start,
    required int end,
  });

  Future<void> writeChunks(String path, Stream<List<int>> chunks);

  Future<void> deleteIfExists(String path);
}

class IoSegmentFileOperations implements SegmentFileOperations {
  const IoSegmentFileOperations();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<bool> refersToSameFile(String firstPath, String secondPath) async {
    if (File(firstPath).absolute.path == File(secondPath).absolute.path) {
      return true;
    }
    try {
      return await FileSystemEntity.identical(firstPath, secondPath);
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> createExclusive(String path) async {
    await File(path).create(recursive: true, exclusive: true);
  }

  @override
  Stream<List<int>> readChunks(
    String path, {
    required int start,
    required int end,
  }) {
    return File(path).openRead(start, end);
  }

  @override
  Future<Uint8List> readRange(
    String path, {
    required int start,
    required int length,
  }) async {
    if (start < 0) {
      throw RangeError.value(start, 'start', 'Must not be negative.');
    }
    if (length < 0) {
      throw RangeError.value(length, 'length', 'Must not be negative.');
    }

    final RandomAccessFile input = await File(path).open();
    try {
      await input.setPosition(start);
      return Uint8List.fromList(await input.read(length));
    } finally {
      await input.close();
    }
  }

  @override
  Future<void> writeChunks(String path, Stream<List<int>> chunks) async {
    final File outputFile = File(path);

    RandomAccessFile? output;
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      output = await outputFile.open(mode: FileMode.write);
      await for (final List<int> chunk in chunks) {
        if (chunk.isNotEmpty) {
          await output.writeFrom(chunk);
        }
      }
      await output.flush();
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    }

    if (output != null) {
      try {
        await output.close();
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final File file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
