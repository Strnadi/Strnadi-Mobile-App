import 'dart:io';
import 'dart:typed_data';
import 'package:logger/logger.dart';

Logger logger = Logger();

/// Searches for the "data" chunk in a WAV file and returns the offset to the audio data.
/// This function finds the first occurrence of the ASCII bytes for "data"
/// and then returns the position after the "data" tag and its 4-byte size field.
int findDataOffset(Uint8List bytes) {
  // "data" in ASCII: [100, 97, 116, 97]
  for (int i = 0; i < bytes.length - 8; i++) {
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
Uint8List createWavHeader(int dataSize, int sampleRate, int bitRate) {
  int channels = 1;
  // Calculate the bit depth (bits per sample) from the bit rate.
  // For PCM WAV, bitRate = sampleRate * channels * bitDepth.
  int bitDepth = bitRate ~/ (sampleRate * channels);
  int byteRate = sampleRate * channels * bitDepth ~/ 8;
  int blockAlign = channels * bitDepth ~/ 8;
  int chunkSize = 36 + dataSize;

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

/// Concatenates WAV files by automatically determining where the audio data begins.
Future<void> concatWavFiles(
    List<String> filePaths, String outputPath, int sampleRate, int bitRate) async {
  if (filePaths.isEmpty) return;

  // Process the first file.
  Uint8List firstFileBytes = await File(filePaths[0]).readAsBytes();
  int dataOffset = findDataOffset(firstFileBytes);
  // Keep the header from the first file (everything before the data chunk).
  Uint8List firstHeader = firstFileBytes.sublist(0, dataOffset);
  // Get the raw audio data from the first file.
  List<int> concatenatedData = firstFileBytes.sublist(dataOffset).toList(growable: true);

  // Process remaining files.
  for (int i = 1; i < filePaths.length; i++) {
    Uint8List bytes = await File(filePaths[i]).readAsBytes();
    int offset = findDataOffset(bytes);
    concatenatedData.addAll(bytes.sublist(offset));
  }

  // Option 1: Use a custom header creation function.
  Uint8List newHeader = createWavHeader(concatenatedData.length, sampleRate, bitRate);
  // Option 2: Or, if you want to preserve some fields from the first header,
  // you could merge them programmatically.

  // Write the new header and the concatenated audio data to the output file.
  final outputFile = File(outputPath);
  await outputFile.writeAsBytes(newHeader + concatenatedData);
  logger.i('WAV files concatenated successfully. to $outputPath');
}