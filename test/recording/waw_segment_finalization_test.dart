import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/fileSize.dart';
import 'package:strnadi/recording/waw.dart';

class _FakeSegmentFileOperations implements SegmentFileOperations {
  _FakeSegmentFileOperations({
    required Map<String, List<int>> files,
    this.readChunkSize = 2,
    this.failAfterWriteChunks,
    this.fileAliases = const <String, String>{},
    this.streamBytesToOmit = const <String, int>{},
    this.failDeletes = const <String>{},
  }) : files = files.map(
          (path, bytes) => MapEntry(path, Uint8List.fromList(bytes)),
        );

  final Map<String, Uint8List> files;
  final int readChunkSize;
  final int? failAfterWriteChunks;
  final Map<String, String> fileAliases;
  final Map<String, int> streamBytesToOmit;
  final Set<String> failDeletes;
  final List<String> deletedPaths = <String>[];
  final List<int> rangeReadLengths = <int>[];
  int largestStreamedReadChunk = 0;
  int createCalls = 0;
  int writeCalls = 0;

  @override
  Future<void> createExclusive(String path) async {
    createCalls += 1;
    if (files.containsKey(path)) {
      throw StateError('Fake output already exists: $path');
    }
    files[path] = Uint8List(0);
  }

  @override
  Future<void> deleteIfExists(String path) async {
    deletedPaths.add(path);
    if (failDeletes.contains(path)) {
      throw StateError('simulated cleanup failure');
    }
    files.remove(path);
  }

  @override
  Future<int> length(String path) async {
    final Uint8List? bytes = files[path];
    if (bytes == null) {
      throw StateError('Missing fake file: $path');
    }
    return bytes.length;
  }

  @override
  Future<bool> refersToSameFile(String firstPath, String secondPath) async {
    String resolve(String path) => fileAliases[path] ?? path;
    return resolve(firstPath) == resolve(secondPath);
  }

  @override
  Stream<List<int>> readChunks(
    String path, {
    required int start,
    required int end,
  }) async* {
    final Uint8List? bytes = files[path];
    if (bytes == null) {
      throw StateError('Missing fake file: $path');
    }
    int boundedEnd = end < bytes.length ? end : bytes.length;
    final int omittedBytes = streamBytesToOmit[path] ?? 0;
    if (omittedBytes > 0) {
      final int shortenedEnd = boundedEnd - omittedBytes;
      boundedEnd = shortenedEnd > start ? shortenedEnd : start;
    }
    for (int offset = start; offset < boundedEnd; offset += readChunkSize) {
      final int chunkEnd = offset + readChunkSize < boundedEnd
          ? offset + readChunkSize
          : boundedEnd;
      final Uint8List chunk = Uint8List.fromList(
        bytes.sublist(offset, chunkEnd),
      );
      if (chunk.length > largestStreamedReadChunk) {
        largestStreamedReadChunk = chunk.length;
      }
      yield chunk;
    }
  }

  @override
  Future<Uint8List> readRange(
    String path, {
    required int start,
    required int length,
  }) async {
    final Uint8List? bytes = files[path];
    if (bytes == null) {
      throw StateError('Missing fake file: $path');
    }
    rangeReadLengths.add(length);
    if (start >= bytes.length) {
      return Uint8List(0);
    }
    final int end =
        start + length < bytes.length ? start + length : bytes.length;
    return Uint8List.fromList(bytes.sublist(start, end));
  }

  @override
  Future<void> writeChunks(String path, Stream<List<int>> chunks) async {
    writeCalls += 1;
    if (!files.containsKey(path)) {
      throw StateError('Fake output was not reserved: $path');
    }
    final BytesBuilder output = BytesBuilder(copy: false);
    int writtenChunks = 0;
    await for (final List<int> chunk in chunks) {
      output.add(chunk);
      files[path] = output.toBytes();
      writtenChunks += 1;
      if (failAfterWriteChunks != null &&
          writtenChunks >= failAfterWriteChunks!) {
        throw StateError('simulated write failure');
      }
    }
    files[path] = output.toBytes();
  }
}

void main() {
  group('calculateWavDuration', () {
    test('uses validated PCM metadata from an in-memory WAV', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'duration.wav': _wav(<int>[1, 2, 3, 4], sampleRate: 2),
        },
      );

      expect(
        await calculateWavDuration(
          'duration.wav',
          fileOperations: files,
        ),
        1,
      );
    });

    test(
        'handles RIFF metadata chunks instead of scanning eight bytes at a time',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'metadata.wav': _wavWithMetadata(
            <int>[1, 2, 3, 4],
            sampleRate: 2,
          ),
        },
      );

      expect(
        await calculateWavDuration(
          'metadata.wav',
          fileOperations: files,
        ),
        1,
      );
    });

    test('returns null for inconsistent or truncated PCM metadata', () async {
      final Uint8List corrupt = _wav(
        <int>[1, 2, 3, 4],
        sampleRate: 2,
      );
      ByteData.sublistView(corrupt).setUint32(28, 999, Endian.little);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'corrupt.wav': corrupt},
      );

      expect(
        await calculateWavDuration(
          'corrupt.wav',
          fileOperations: files,
        ),
        isNull,
      );
    });
  });

  group('writeFinalizedWavSegment', () {
    test('writes a valid distinct WAV and leaves raw input for caller commit',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'raw.pcm': <int>[1, 2, 3, 4],
        },
      );

      await writeFinalizedWavSegment(
        rawInputPath: 'raw.pcm',
        outputPath: 'final.wav',
        sampleRate: 48000,
        bitRate: 768000,
        fileOperations: files,
      );

      expect(files.files['raw.pcm'], <int>[1, 2, 3, 4]);
      final Uint8List finalized = files.files['final.wav']!;
      expect(finalized.length, 48);
      expect(String.fromCharCodes(finalized.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(finalized.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(finalized.sublist(36, 40)), 'data');
      expect(finalized.sublist(44), <int>[1, 2, 3, 4]);
      expect(files.deletedPaths, isEmpty);
      expect(files.largestStreamedReadChunk, lessThanOrEqualTo(2));
      expect(files.rangeReadLengths, isEmpty);
    });

    test('removes partial output and preserves raw input when writing fails',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'raw.pcm': <int>[9, 8, 7, 6],
        },
        failAfterWriteChunks: 2,
      );

      await expectLater(
        writeFinalizedWavSegment(
          rawInputPath: 'raw.pcm',
          outputPath: 'partial.wav',
          sampleRate: 48000,
          bitRate: 768000,
          fileOperations: files,
        ),
        throwsA(isA<StateError>()),
      );

      expect(files.files['raw.pcm'], <int>[9, 8, 7, 6]);
      expect(files.files.containsKey('partial.wav'), isFalse);
      expect(files.deletedPaths, <String>['partial.wav']);
    });

    test('rejects destructive in-place finalization', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'same-path.wav': <int>[1],
        },
      );

      await expectLater(
        writeFinalizedWavSegment(
          rawInputPath: 'same-path.wav',
          outputPath: 'same-path.wav',
          sampleRate: 48000,
          bitRate: 768000,
          fileOperations: files,
        ),
        throwsArgumentError,
      );

      expect(files.files['same-path.wav'], <int>[1]);
    });

    test('adds RIFF padding after an odd 8-bit PCM payload', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'raw.pcm': <int>[7],
        },
      );

      await writeFinalizedWavSegment(
        rawInputPath: 'raw.pcm',
        outputPath: 'final.wav',
        sampleRate: 48000,
        bitRate: 384000,
        fileOperations: files,
      );

      final Uint8List finalized = files.files['final.wav']!;
      final ByteData header = ByteData.sublistView(finalized);
      expect(header.getUint32(4, Endian.little), finalized.length - 8);
      expect(header.getUint32(40, Endian.little), 1);
      expect(finalized.sublist(44), <int>[7, 0]);
      expect(files.files['raw.pcm'], <int>[7]);
    });

    test('does not truncate or delete a pre-existing output', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'raw.pcm': <int>[1, 2],
          'existing.wav': <int>[99, 98],
        },
      );

      await expectLater(
        writeFinalizedWavSegment(
          rawInputPath: 'raw.pcm',
          outputPath: 'existing.wav',
          sampleRate: 48000,
          bitRate: 768000,
          fileOperations: files,
        ),
        throwsA(isA<StateError>()),
      );

      expect(files.files['raw.pcm'], <int>[1, 2]);
      expect(files.files['existing.wav'], <int>[99, 98]);
      expect(files.writeCalls, 0);
      expect(files.deletedPaths, isEmpty);
    });

    test('preserves the write error and raw data if partial cleanup fails',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'raw.pcm': <int>[1, 2, 3, 4],
        },
        failAfterWriteChunks: 2,
        failDeletes: <String>{'partial.wav'},
      );

      await expectLater(
        writeFinalizedWavSegment(
          rawInputPath: 'raw.pcm',
          outputPath: 'partial.wav',
          sampleRate: 48000,
          bitRate: 768000,
          fileOperations: files,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'simulated write failure',
          ),
        ),
      );

      expect(files.files['raw.pcm'], <int>[1, 2, 3, 4]);
      expect(files.files['partial.wav'], isNotEmpty);
      expect(files.deletedPaths, <String>['partial.wav']);
    });
  });

  group('concatWavFiles', () {
    test('rejects an empty segment list without reserving an output', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: const <String, List<int>>{},
      );

      await expectLater(
        concatWavFiles(
          const <String>[],
          'combined.wav',
          fileOperations: files,
        ),
        throwsArgumentError,
      );

      expect(files.createCalls, 0);
      expect(files.writeCalls, 0);
      expect(files.files.containsKey('combined.wav'), isFalse);
    });

    test('streams compatible segment data into one WAV with bounded reads',
        () async {
      final Uint8List first = _wav(<int>[1, 2, 3, 4]);
      final Uint8List second = _wav(<int>[5, 6, 7, 8, 9, 10]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'first.wav': first,
          'second.wav': second,
        },
        readChunkSize: 2,
      );

      await concatWavFiles(
        <String>['first.wav', 'second.wav'],
        'combined.wav',
        fileOperations: files,
      );

      final Uint8List combined = files.files['combined.wav']!;
      expect(String.fromCharCodes(combined.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(combined.sublist(36, 40)), 'data');
      expect(
        ByteData.sublistView(combined).getUint32(40, Endian.little),
        10,
      );
      expect(
        combined.sublist(44),
        <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
      );
      expect(files.rangeReadLengths, isNotEmpty);
      expect(files.rangeReadLengths.every((length) => length <= 16), isTrue);
      expect(files.largestStreamedReadChunk, lessThanOrEqualTo(2));
    });

    test('writes into an exclusively pre-reserved download output', () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'part.wav': _wav(<int>[1, 2, 3, 4]),
          'reserved.wav': const <int>[],
        },
      );

      await concatWavFiles(
        <String>['part.wav'],
        'reserved.wav',
        outputAlreadyReserved: true,
        fileOperations: files,
      );

      expect(files.createCalls, 0);
      expect(files.writeCalls, 1);
      expect(files.files['reserved.wav']!.sublist(44), <int>[1, 2, 3, 4]);
    });

    test('skips metadata chunks and copies only the declared audio payload',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'metadata.wav': _wavWithMetadata(<int>[4, 3, 2, 1]),
        },
      );

      await concatWavFiles(
        <String>['metadata.wav'],
        'combined.wav',
        fileOperations: files,
      );

      expect(
        files.files['combined.wav']!.sublist(44),
        <int>[4, 3, 2, 1],
      );
      expect(files.rangeReadLengths.every((length) => length <= 16), isTrue);
    });

    test('pads an odd-length PCM payload without inflating its data size',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          '8-bit.wav': _wav(<int>[7], bitDepth: 8),
        },
      );

      await concatWavFiles(
        <String>['8-bit.wav'],
        'combined.wav',
        fileOperations: files,
      );

      final Uint8List combined = files.files['combined.wav']!;
      final ByteData header = ByteData.sublistView(combined);
      expect(header.getUint32(4, Endian.little), combined.length - 8);
      expect(header.getUint32(40, Endian.little), 1);
      expect(combined.sublist(44), <int>[7, 0]);
    });

    test('rejects an odd-sized source chunk with no RIFF padding', () async {
      final Uint8List padded = _wav(<int>[7], bitDepth: 8);
      final Uint8List missingPadding = Uint8List.fromList(
        padded.sublist(0, padded.length - 1),
      );
      ByteData.sublistView(missingPadding).setUint32(
        4,
        missingPadding.length - 8,
        Endian.little,
      );
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'missing-padding.wav': missingPadding},
      );

      await expectLater(
        concatWavFiles(
          <String>['missing-padding.wav'],
          'combined.wav',
          fileOperations: files,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(files.createCalls, 0);
      expect(files.writeCalls, 0);
    });

    test('rejects an aggregate path that aliases an input before writing',
        () async {
      final Uint8List input = _wav(<int>[1, 2]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'segment.wav': input},
      );

      await expectLater(
        concatWavFiles(
          <String>['segment.wav'],
          'segment.wav',
          fileOperations: files,
        ),
        throwsArgumentError,
      );

      expect(files.files['segment.wav'], input);
      expect(files.writeCalls, 0);
      expect(files.deletedPaths, isEmpty);
    });

    test('rejects a filesystem alias before opening the aggregate', () async {
      final Uint8List input = _wav(<int>[1, 2]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'segment.wav': input},
        fileAliases: <String, String>{
          'segment.wav': 'physical-file',
          'segment-alias.wav': 'physical-file',
        },
      );

      await expectLater(
        concatWavFiles(
          <String>['segment.wav'],
          'segment-alias.wav',
          fileOperations: files,
        ),
        throwsArgumentError,
      );

      expect(files.files['segment.wav'], input);
      expect(files.writeCalls, 0);
      expect(files.deletedPaths, isEmpty);
    });

    test('removes a partial aggregate and preserves every input on failure',
        () async {
      final Uint8List first = _wav(<int>[1, 2, 3, 4]);
      final Uint8List second = _wav(<int>[5, 6, 7, 8]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'first.wav': first,
          'second.wav': second,
        },
        failAfterWriteChunks: 3,
      );

      await expectLater(
        concatWavFiles(
          <String>['first.wav', 'second.wav'],
          'partial.wav',
          fileOperations: files,
        ),
        throwsA(isA<StateError>()),
      );

      expect(files.files['first.wav'], first);
      expect(files.files['second.wav'], second);
      expect(files.files.containsKey('partial.wav'), isFalse);
      expect(files.deletedPaths, <String>['partial.wav']);
    });

    test('removes partial output when a source shrinks during streaming',
        () async {
      final Uint8List input = _wav(<int>[1, 2, 3, 4]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'segment.wav': input},
        streamBytesToOmit: <String, int>{'segment.wav': 1},
      );

      await expectLater(
        concatWavFiles(
          <String>['segment.wav'],
          'partial.wav',
          fileOperations: files,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(files.files['segment.wav'], input);
      expect(files.files.containsKey('partial.wav'), isFalse);
      expect(files.deletedPaths, <String>['partial.wav']);
    });

    test('rejects a truncated source before reserving an output', () async {
      final Uint8List complete = _wav(<int>[1, 2, 3, 4]);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          'truncated.wav': complete.sublist(0, complete.length - 1),
        },
      );

      await expectLater(
        concatWavFiles(
          <String>['truncated.wav'],
          'combined.wav',
          fileOperations: files,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(files.createCalls, 0);
      expect(files.writeCalls, 0);
      expect(files.files.containsKey('combined.wav'), isFalse);
    });

    test('rejects corrupt PCM byte-rate metadata before writing', () async {
      final Uint8List corrupt = _wav(<int>[1, 2, 3, 4]);
      ByteData.sublistView(corrupt).setUint32(28, 1, Endian.little);
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{'corrupt.wav': corrupt},
      );

      await expectLater(
        concatWavFiles(
          <String>['corrupt.wav'],
          'combined.wav',
          fileOperations: files,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(files.createCalls, 0);
      expect(files.writeCalls, 0);
      expect(files.files.containsKey('combined.wav'), isFalse);
    });

    test('rejects incompatible segment formats without creating output',
        () async {
      final _FakeSegmentFileOperations files = _FakeSegmentFileOperations(
        files: <String, List<int>>{
          '48k.wav': _wav(<int>[1, 2], sampleRate: 48000),
          '44k.wav': _wav(<int>[3, 4], sampleRate: 44100),
        },
      );

      await expectLater(
        concatWavFiles(
          <String>['48k.wav', '44k.wav'],
          'combined.wav',
          fileOperations: files,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(files.files.containsKey('combined.wav'), isFalse);
      expect(files.writeCalls, 0);
    });
  });

  group('createWavHeader bounds', () {
    test('rejects sample rates that do not fit uint32', () {
      expect(
        () => createWavHeader(2, 0x100000000, 0x100000000 * 16),
        throwsRangeError,
      );
    });

    test('rejects block alignment that does not fit uint16', () {
      expect(
        () => createWavHeader(
          131070,
          1,
          1 * 0xffff * 16,
          channels: 0xffff,
        ),
        throwsRangeError,
      );
    });

    test('rejects byte rates that do not fit uint32', () {
      expect(
        () => createWavHeader(2, 0xffffffff, 0xffffffff * 16),
        throwsRangeError,
      );
    });
  });
}

Uint8List _wav(
  List<int> payload, {
  int sampleRate = 48000,
  int bitDepth = 16,
}) {
  final Uint8List header = createWavHeader(
    payload.length,
    sampleRate,
    sampleRate * bitDepth,
  );
  return Uint8List.fromList(<int>[
    ...header,
    ...payload,
    if (payload.length.isOdd) 0,
  ]);
}

Uint8List _wavWithMetadata(
  List<int> payload, {
  int sampleRate = 48000,
  int bitDepth = 16,
}) {
  final Uint8List canonical = _wav(
    payload,
    sampleRate: sampleRate,
    bitDepth: bitDepth,
  );
  final List<int> fmtChunk = canonical.sublist(12, 36);
  final List<int> junkPayload = <int>[9, 8, 7, 6];
  final List<int> trailingPayload = <int>[5, 5];
  final BytesBuilder body = BytesBuilder(copy: false)
    ..add(fmtChunk)
    ..add('JUNK'.codeUnits)
    ..add(_littleEndianUint32(junkPayload.length))
    ..add(junkPayload)
    ..add('data'.codeUnits)
    ..add(_littleEndianUint32(payload.length))
    ..add(payload)
    ..add('LIST'.codeUnits)
    ..add(_littleEndianUint32(trailingPayload.length))
    ..add(trailingPayload);
  final Uint8List bodyBytes = body.toBytes();
  final Uint8List riffHeader = Uint8List(12)
    ..setRange(0, 4, 'RIFF'.codeUnits)
    ..setRange(8, 12, 'WAVE'.codeUnits);
  ByteData.sublistView(riffHeader).setUint32(
    4,
    bodyBytes.length + 4,
    Endian.little,
  );
  return Uint8List.fromList(<int>[...riffHeader, ...bodyBytes]);
}

Uint8List _littleEndianUint32(int value) {
  final Uint8List bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
  return bytes;
}
