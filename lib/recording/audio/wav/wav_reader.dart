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
import 'segment_file_operations.dart';

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
    throw FormatException('WAV file $path is truncated at byte $start.');
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
    final int chunkLength = ByteData.sublistView(
      chunkHeader,
    ).getUint32(4, Endian.little);
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
