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

import 'package:logger/logger.dart';

Logger logger = Logger();

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

/// Searches for the "data" chunk in a WAV file and returns the offset to the audio data.
/// This function finds the first occurrence of the ASCII bytes for "data"
/// and then returns the position after the "data" tag and its 4-byte size field.
int findDataOffset(Uint8List bytes) {
  // "data" in ASCII: [100, 97, 116, 97]
  for (int i = 0; i <= bytes.length - 8; i++) {
    if (bytes[i] == 100 &&
        bytes[i + 1] == 97 &&
        bytes[i + 2] == 116 &&
        bytes[i + 3] == 97) {
      // The next 4 bytes represent the size of the data chunk.
      // The audio data begins after these 8 bytes.
      return i + 8;
    }
  }
  throw Exception("Data chunk not found in WAV file.");
}

/// Creates a new WAV header for the given total data size.
/// You can modify this function to extract more information from the original header if needed.
Uint8List createWavHeader(
  int dataSize,
  int sampleRate,
  int bitRate, {
  int channels = 1,
}) {
  const int maxRiffChunkSize = 0xffffffff;
  const int maxDataSize = maxRiffChunkSize - 36;
  final int paddingLength = dataSize.isOdd ? 1 : 0;
  if (dataSize < 0 ||
      dataSize > maxDataSize ||
      36 + dataSize + paddingLength > maxRiffChunkSize) {
    throw RangeError.range(dataSize, 0, maxDataSize, 'dataSize');
  }
  if (sampleRate <= 0) {
    throw RangeError.value(
      sampleRate,
      'sampleRate',
      'Must be greater than zero.',
    );
  }
  if (sampleRate > 0xffffffff) {
    throw RangeError.range(sampleRate, 1, 0xffffffff, 'sampleRate');
  }
  if (channels <= 0 || channels > 0xffff) {
    throw RangeError.range(channels, 1, 0xffff, 'channels');
  }
  if (bitRate <= 0 || bitRate % (sampleRate * channels) != 0) {
    throw ArgumentError.value(
      bitRate,
      'bitRate',
      'Must contain a whole number of bits per sample.',
    );
  }

  // Calculate the bit depth (bits per sample) from the bit rate.
  // For PCM WAV, bitRate = sampleRate * channels * bitDepth.
  int bitDepth = bitRate ~/ (sampleRate * channels);
  if (bitDepth <= 0 || bitDepth > 0xffff || bitDepth % 8 != 0) {
    throw ArgumentError.value(
      bitDepth,
      'bitDepth',
      'PCM bit depth must be a positive whole number of bytes.',
    );
  }
  int byteRate = sampleRate * channels * bitDepth ~/ 8;
  int blockAlign = channels * bitDepth ~/ 8;
  if (blockAlign > 0xffff) {
    throw RangeError.range(blockAlign, 1, 0xffff, 'blockAlign');
  }
  if (byteRate > 0xffffffff) {
    throw RangeError.range(byteRate, 1, 0xffffffff, 'byteRate');
  }
  if (dataSize % blockAlign != 0) {
    throw ArgumentError.value(
      dataSize,
      'dataSize',
      'Must contain complete PCM sample frames.',
    );
  }
  int chunkSize = 36 + dataSize + paddingLength;

  Uint8List header = Uint8List(44);
  ByteData bd = ByteData.sublistView(header);

  // RIFF header
  header.setRange(0, 4, [82, 73, 70, 70]); // "RIFF"
  bd.setUint32(4, chunkSize, Endian.little);
  header.setRange(8, 12, [87, 65, 86, 69]); // "WAVE"

  // fmt sub-chunk
  header.setRange(12, 16, [102, 109, 116, 32]); // "fmt "
  bd.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  bd.setUint16(20, 1, Endian.little); // AudioFormat (1 = PCM)
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, byteRate, Endian.little);
  bd.setUint16(32, blockAlign, Endian.little);
  bd.setUint16(34, bitDepth, Endian.little);

  // data sub-chunk
  header.setRange(36, 40, [100, 97, 116, 97]); // "data"
  bd.setUint32(40, dataSize, Endian.little);

  return header;
}

final class WavPcmDataRegion {
  const WavPcmDataRegion({
    required this.path,
    required this.dataOffset,
    required this.dataLength,
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
  });

  final String path;
  final int dataOffset;
  final int dataLength;
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
}

bool _matchesAscii(Uint8List bytes, int offset, String value) {
  if (offset < 0 || offset + value.length > bytes.length) {
    return false;
  }
  for (int index = 0; index < value.length; index += 1) {
    if (bytes[offset + index] != value.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

Future<Uint8List> _readExactRange(
  SegmentFileOperations fileOperations,
  String path, {
  required int start,
  required int length,
}) async {
  final Uint8List bytes = await fileOperations.readRange(
    path,
    start: start,
    length: length,
  );
  if (bytes.length != length) {
    throw FormatException(
      'WAV file $path is truncated at byte $start.',
    );
  }
  return bytes;
}

Future<WavPcmDataRegion> readWavPcmDataRegion(
  SegmentFileOperations fileOperations,
  String path,
) async {
  final int fileLength = await fileOperations.length(path);
  if (fileLength < 12) {
    throw FormatException('WAV file $path is shorter than its RIFF header.');
  }

  final Uint8List riffHeader = await _readExactRange(
    fileOperations,
    path,
    start: 0,
    length: 12,
  );
  if (!_matchesAscii(riffHeader, 0, 'RIFF') ||
      !_matchesAscii(riffHeader, 8, 'WAVE')) {
    throw FormatException('File $path is not a RIFF/WAVE file.');
  }

  final int riffLength =
      ByteData.sublistView(riffHeader).getUint32(4, Endian.little) + 8;
  if (riffLength < 12 || riffLength > fileLength) {
    throw FormatException(
      'WAV file $path has an invalid or truncated RIFF length.',
    );
  }

  int? audioFormat;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? byteRate;
  int? declaredBlockAlign;
  int? dataOffset;
  int? dataLength;
  int chunkOffset = 12;

  while (chunkOffset + 8 <= riffLength) {
    final Uint8List chunkHeader = await _readExactRange(
      fileOperations,
      path,
      start: chunkOffset,
      length: 8,
    );
    final int chunkLength =
        ByteData.sublistView(chunkHeader).getUint32(4, Endian.little);
    final int payloadOffset = chunkOffset + 8;
    final int payloadEnd = payloadOffset + chunkLength;
    if (payloadEnd > riffLength) {
      throw FormatException(
        'WAV file $path contains a truncated chunk at byte $chunkOffset.',
      );
    }
    final int paddedEnd = payloadEnd + (chunkLength.isOdd ? 1 : 0);
    if (paddedEnd > riffLength) {
      throw FormatException(
        'WAV file $path is missing padding after an odd-sized chunk.',
      );
    }

    if (_matchesAscii(chunkHeader, 0, 'fmt ')) {
      if (chunkLength < 16) {
        throw FormatException('WAV file $path has an invalid fmt chunk.');
      }
      final Uint8List formatBytes = await _readExactRange(
        fileOperations,
        path,
        start: payloadOffset,
        length: 16,
      );
      final ByteData formatData = ByteData.sublistView(formatBytes);
      audioFormat = formatData.getUint16(0, Endian.little);
      channels = formatData.getUint16(2, Endian.little);
      sampleRate = formatData.getUint32(4, Endian.little);
      byteRate = formatData.getUint32(8, Endian.little);
      declaredBlockAlign = formatData.getUint16(12, Endian.little);
      bitsPerSample = formatData.getUint16(14, Endian.little);
    } else if (_matchesAscii(chunkHeader, 0, 'data') && dataOffset == null) {
      dataOffset = payloadOffset;
      dataLength = chunkLength;
    }

    if (audioFormat != null &&
        channels != null &&
        sampleRate != null &&
        byteRate != null &&
        declaredBlockAlign != null &&
        bitsPerSample != null &&
        dataOffset != null &&
        dataLength != null) {
      break;
    }

    chunkOffset = paddedEnd;
  }

  if (audioFormat == null ||
      channels == null ||
      sampleRate == null ||
      byteRate == null ||
      declaredBlockAlign == null ||
      bitsPerSample == null) {
    throw FormatException('WAV file $path has no usable fmt chunk.');
  }
  if (dataOffset == null || dataLength == null) {
    throw FormatException('WAV file $path has no data chunk.');
  }
  if (audioFormat != 1) {
    throw FormatException(
      'WAV file $path uses unsupported non-PCM format $audioFormat.',
    );
  }
  if (channels <= 0 ||
      sampleRate <= 0 ||
      bitsPerSample <= 0 ||
      bitsPerSample % 8 != 0) {
    throw FormatException('WAV file $path has invalid PCM format metadata.');
  }
  final int blockAlign = channels * bitsPerSample ~/ 8;
  if (blockAlign > 0xffff ||
      declaredBlockAlign != blockAlign ||
      sampleRate * blockAlign > 0xffffffff ||
      byteRate != sampleRate * blockAlign) {
    throw FormatException('WAV file $path has inconsistent PCM byte rates.');
  }
  if (dataLength % blockAlign != 0) {
    throw FormatException(
      'WAV file $path ends with an incomplete PCM sample frame.',
    );
  }

  return WavPcmDataRegion(
    path: path,
    dataOffset: dataOffset,
    dataLength: dataLength,
    audioFormat: audioFormat,
    channels: channels,
    sampleRate: sampleRate,
    bitsPerSample: bitsPerSample,
  );
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
  final int sampleRate =
      sampleRateHint == 0 ? first.sampleRate : sampleRateHint;
  final int bitDepth =
      bitsPerSampleHint == 0 ? first.bitsPerSample : bitsPerSampleHint;
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
