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
