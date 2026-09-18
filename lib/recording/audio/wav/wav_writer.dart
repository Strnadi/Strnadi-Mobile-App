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
import 'dart:typed_data';
import 'package:strnadi/logging/app_logger.dart';
import 'segment_file_operations.dart';
import 'wav_header.dart';
import 'wav_reader.dart';

final logger = AppLogger(scope: 'recording.waw');

/// Writes a complete WAV to [outputPath] without modifying [rawInputPath].
///
/// A partially written output is removed on failure, leaving the raw PCM input
/// intact so the caller can retry. The caller owns committing metadata and
/// removing the raw input after this future succeeds.
Future<void> writeFinalizedWavSegment({
  required String rawInputPath,
  required String outputPath,
  required int sampleRate,
  required int bitRate,
  SegmentFileOperations fileOperations = const IoSegmentFileOperations(),
}) async {
  if (rawInputPath == outputPath ||
      await fileOperations.refersToSameFile(rawInputPath, outputPath)) {
    throw ArgumentError.value(
      outputPath,
      'outputPath',
      'The finalized WAV must use a path distinct from the raw input.',
    );
  }

  final int rawLength = await fileOperations.length(rawInputPath);
  final Uint8List header = createWavHeader(rawLength, sampleRate, bitRate);

  Stream<List<int>> finalizedChunks() async* {
    yield header;
    yield* _readExactChunks(
      fileOperations,
      rawInputPath,
      start: 0,
      length: rawLength,
    );
    if (rawLength.isOdd) {
      yield const <int>[0];
    }
  }

  await fileOperations.createExclusive(outputPath);
  try {
    await fileOperations.writeChunks(outputPath, finalizedChunks());
  } catch (error, stackTrace) {
    try {
      await fileOperations.deleteIfExists(outputPath);
    } catch (_) {
      // Preserve the original write error. The raw input is still untouched.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Stream<List<int>> _readExactChunks(
  SegmentFileOperations fileOperations,
  String path, {
  required int start,
  required int length,
}) async* {
  int remaining = length;
  await for (final List<int> chunk in fileOperations.readChunks(
    path,
    start: start,
    end: start + length,
  )) {
    if (chunk.isEmpty) {
      continue;
    }
    if (chunk.length > remaining) {
      throw FormatException(
        'File $path produced more bytes than its declared range.',
      );
    }
    remaining -= chunk.length;
    yield chunk;
  }

  if (remaining != 0) {
    throw FormatException(
      'File $path ended $remaining bytes before its declared range.',
    );
  }
}

Future<void> concatWavFiles(
  List<String> filePaths,
  String outputPath, {
  int sampleRateHint = 0,
  int bitsPerSampleHint = 0,
  bool outputAlreadyReserved = false,
  SegmentFileOperations fileOperations = const IoSegmentFileOperations(),
}) async {
  logger.i('Concatenating WAV files');

  if (filePaths.isEmpty) {
    throw ArgumentError.value(
      filePaths,
      'filePaths',
      'At least one WAV segment is required.',
    );
  }
  for (final String inputPath in filePaths) {
    if (inputPath == outputPath ||
        await fileOperations.refersToSameFile(inputPath, outputPath)) {
      throw ArgumentError.value(
        outputPath,
        'outputPath',
        'The concatenated WAV must not overwrite one of its input segments.',
      );
    }
  }

  final List<WavPcmDataRegion> regions = <WavPcmDataRegion>[];
  for (final String path in filePaths) {
    regions.add(await readWavPcmDataRegion(fileOperations, path));
  }

  final WavPcmDataRegion first = regions.first;
  final int sampleRate = sampleRateHint == 0
      ? first.sampleRate
      : sampleRateHint;
  final int bitDepth = bitsPerSampleHint == 0
      ? first.bitsPerSample
      : bitsPerSampleHint;
  final int channels = first.channels;
  int totalDataLength = 0;

  for (final WavPcmDataRegion region in regions) {
    if (region.audioFormat != first.audioFormat ||
        region.channels != channels ||
        region.sampleRate != sampleRate ||
        region.bitsPerSample != bitDepth) {
      throw FormatException(
        'WAV segment ${region.path} does not match the recording format.',
      );
    }
    totalDataLength += region.dataLength;
  }

  final Uint8List header = createWavHeader(
    totalDataLength,
    sampleRate,
    sampleRate * channels * bitDepth,
    channels: channels,
  );

  Stream<List<int>> outputChunks() async* {
    yield header;
    for (final WavPcmDataRegion region in regions) {
      yield* _readExactChunks(
        fileOperations,
        region.path,
        start: region.dataOffset,
        length: region.dataLength,
      );
    }
    if (totalDataLength.isOdd) {
      yield const <int>[0];
    }
  }

  if (!outputAlreadyReserved) {
    await fileOperations.createExclusive(outputPath);
  }
  try {
    await fileOperations.writeChunks(outputPath, outputChunks());
  } catch (error, stackTrace) {
    try {
      await fileOperations.deleteIfExists(outputPath);
    } catch (_) {
      // Preserve the original streaming failure. Input segments are untouched.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
  logger.i('WAV file written.');
}
