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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/raw_pcm_capture.dart';
import 'package:strnadi/recording/waw.dart';

void main() {
  group('raw PCM path reservation', () {
    test('skips excluded and colliding candidates atomically', () async {
      final _FakeAllocator allocator = _FakeAllocator(
        collisions: <String>{'collision.raw'},
      );
      final Iterator<String> candidates = <String>[
        'excluded.raw',
        'collision.raw',
        'reserved.raw',
      ].iterator;

      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () {
          candidates.moveNext();
          return candidates.current;
        },
        allocator: allocator,
        excludedPaths: <String>{'excluded.raw'},
      );

      expect(reserved.path, 'reserved.raw');
      expect(allocator.attempts, <String>['collision.raw', 'reserved.raw']);
    });

    test('real allocator never overwrites a pre-existing raw file', () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('raw-reservation-');
      addTearDown(() => directory.delete(recursive: true));
      final File existing = File('${directory.path}/existing.raw');
      await existing.writeAsBytes(<int>[9, 9, 9]);
      final String newPath = '${directory.path}/new.raw';
      final Iterator<String> candidates = <String>[
        existing.path,
        newPath,
      ].iterator;

      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () {
          candidates.moveNext();
          return candidates.current;
        },
      );
      await reserved.writer.close();

      expect(reserved.path, newPath);
      expect(await existing.readAsBytes(), <int>[9, 9, 9]);
      expect(await File(newPath).exists(), isTrue);
    });

    test('fails deterministically when candidates cannot be reserved',
        () async {
      await expectLater(
        reserveUnusedRawPcmFile(
          nextCandidate: () => 'taken.raw',
          allocator: _FakeAllocator(collisions: <String>{'taken.raw'}),
          maxAttempts: 2,
        ),
        throwsStateError,
      );
    });
  });

  group('RawPcmCapture', () {
    test('serializes writes and finish waits for the final write to drain',
        () async {
      final StreamController<List<int>> source = StreamController<List<int>>();
      final Completer<void> firstWriteGate = Completer<void>();
      final _FakeWriter writer = _FakeWriter(
        writeGates: <Completer<void>>[firstWriteGate],
      );
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: writer,
        ),
        startStream: () async => source.stream,
      );

      source.add(<int>[1, 2]);
      source.add(<int>[3, 4]);
      await _flushEvents();
      expect(writer.events, <String>['write:[1, 2]']);

      var finishCompleted = false;
      final Future<void> finish = capture.finish().then((_) {
        finishCompleted = true;
      });
      final Future<void> sourceClose = source.close();
      await _flushEvents();
      expect(finishCompleted, isFalse);
      expect(writer.events, <String>['write:[1, 2]']);

      firstWriteGate.complete();
      await sourceClose;
      await finish;
      expect(
        writer.events,
        <String>[
          'write:[1, 2]',
          'write:[3, 4]',
          'flush',
          'close',
        ],
      );
    });

    test('stream errors are rethrown only after the writer closes', () async {
      final StreamController<List<int>> source = StreamController<List<int>>();
      final _FakeWriter writer = _FakeWriter();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: writer,
        ),
        startStream: () async => source.stream,
      );

      source.add(<int>[5, 6]);
      source.addError(StateError('microphone stream failed'));
      await source.close();

      await expectLater(
        capture.finish(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'microphone stream failed',
          ),
        ),
      );
      expect(writer.events.last, 'close');
      expect(writer.events, contains('write:[5, 6]'));
    });

    test('write errors close the writer and remain repeatable', () async {
      final _FakeWriter writer = _FakeWriter(failWriteAt: 0);
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: writer,
        ),
        startStream: () async => Stream<List<int>>.value(<int>[7, 8]),
      );

      await expectLater(capture.finish(), throwsA(isA<FileSystemException>()));
      await expectLater(capture.finish(), throwsA(isA<FileSystemException>()));
      expect(writer.events.last, 'close');
    });

    test('start failures close the handle but preserve the reserved file',
        () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('raw-start-failure-');
      addTearDown(() => directory.delete(recursive: true));
      final String path = '${directory.path}/reserved.raw';
      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () => path,
      );

      await expectLater(
        RawPcmCapture.start(
          reservedFile: reserved,
          startStream: () async => throw StateError('native start failed'),
        ),
        throwsStateError,
      );

      expect(await File(path).exists(), isTrue);
      expect(await File(path).length(), 0);
    });

    test('stream failure preserves captured bytes for diagnosis or recovery',
        () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('raw-stream-failure-');
      addTearDown(() => directory.delete(recursive: true));
      final String path = '${directory.path}/capture.raw';
      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () => path,
      );
      final StreamController<List<int>> source = StreamController<List<int>>();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: reserved,
        startStream: () async => source.stream,
      );

      source.add(<int>[10, 11, 12]);
      source.addError(StateError('stream failed'));
      await source.close();
      await expectLater(capture.finish(), throwsStateError);

      expect(await File(path).exists(), isTrue);
      expect(await File(path).readAsBytes(), <int>[10, 11, 12]);
    });

    test('abort drains an in-flight write and permanently blocks finalization',
        () async {
      final StreamController<List<int>> source = StreamController<List<int>>();
      final Completer<void> writeGate = Completer<void>();
      final _FakeWriter writer =
          _FakeWriter(writeGates: <Completer<void>>[writeGate]);
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: writer,
        ),
        startStream: () async => source.stream,
      );
      source.add(<int>[1, 2, 3]);
      await _flushEvents();

      var abortCompleted = false;
      final Future<void> abort = capture.abort().then((_) {
        abortCompleted = true;
      });
      await _flushEvents();
      expect(abortCompleted, isFalse);

      writeGate.complete();
      await abort;
      expect(writer.events.last, 'close');
      await expectLater(
        capture.finish(),
        throwsA(isA<RawPcmCaptureAbortedException>()),
      );
      await source.close();
    });

    test('finish bounds a native stream that never closes and preserves raw',
        () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('raw-drain-timeout-');
      addTearDown(() => directory.delete(recursive: true));
      final String path = '${directory.path}/capture.raw';
      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () => path,
      );
      final StreamController<List<int>> source = StreamController<List<int>>();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: reserved,
        startStream: () async => source.stream,
      );

      source.add(<int>[21, 22, 23, 24]);
      await _flushEvents();
      await expectLater(
        capture.finish(timeout: const Duration(milliseconds: 10)),
        throwsA(
          isA<RawPcmCaptureDrainTimeoutException>()
              .having((error) => error.path, 'path', path)
              .having(
                (error) => error.duration,
                'duration',
                const Duration(milliseconds: 10),
              )
              .having(
                (error) => error.cleanupTimedOut,
                'cleanupTimedOut',
                isFalse,
              ),
        ),
      );

      expect(source.hasListener, isFalse);
      expect(await File(path).readAsBytes(), <int>[21, 22, 23, 24]);
      await expectLater(
        capture.finish(),
        throwsA(isA<RawPcmCaptureAbortedException>()),
      );
      await capture.abort();
      await source.close();
    });

    test('finish returns even when the stream cancel future never completes',
        () async {
      final Completer<void> neverCancelled = Completer<void>();
      final StreamController<List<int>> source = StreamController<List<int>>(
        onCancel: () => neverCancelled.future,
      );
      final _FakeWriter writer = _FakeWriter();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'stuck-native-stream.raw',
          writer: writer,
        ),
        startStream: () async => source.stream,
      );
      source.add(<int>[31, 32, 33]);
      await _flushEvents();
      final Stopwatch stopwatch = Stopwatch()..start();

      await expectLater(
        capture.finish(
          timeout: const Duration(milliseconds: 10),
          abortTimeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<RawPcmCaptureDrainTimeoutException>()
              .having(
                (error) => error.cleanupTimedOut,
                'cleanupTimedOut',
                isTrue,
              )
              .having(
                (error) => error.path,
                'path',
                'stuck-native-stream.raw',
              ),
        ),
      );
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(writer.events, contains('write:[31, 32, 33]'));
      expect(writer.events, containsAllInOrder(<String>['flush', 'close']));
      expect(neverCancelled.isCompleted, isFalse);
    });

    test('finish rejects a non-positive drain bound', () async {
      final StreamController<List<int>> source = StreamController<List<int>>();
      final _FakeWriter writer = _FakeWriter();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: writer,
        ),
        startStream: () async => source.stream,
      );

      await expectLater(
        capture.finish(timeout: Duration.zero),
        throwsArgumentError,
      );
      await capture.abort();
      await source.close();
    });

    test('abort rejects a non-positive cleanup bound', () async {
      final StreamController<List<int>> source = StreamController<List<int>>();
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: ReservedRawPcmFile(
          path: 'capture.raw',
          writer: _FakeWriter(),
        ),
        startStream: () async => source.stream,
      );

      await expectLater(
        capture.abort(timeout: Duration.zero),
        throwsArgumentError,
      );
      await capture.abort();
      await source.close();
    });

    for (final MapEntry<String, List<int>> example in <String, List<int>>{
      'WAV': <int>[
        ...'RIFF'.codeUnits,
        36,
        0,
        0,
        0,
        ...'WAVE'.codeUnits,
      ],
      'CAF': <int>[...'caff'.codeUnits, 0, 1, 0, 0],
      'AIFF': <int>[
        ...'FORM'.codeUnits,
        0,
        0,
        0,
        4,
        ...'AIFF'.codeUnits,
      ],
    }.entries) {
      test('rejects ${example.key} bytes instead of nesting a container',
          () async {
        final _FakeWriter writer = _FakeWriter();
        final RawPcmCapture capture = await RawPcmCapture.start(
          reservedFile: ReservedRawPcmFile(
            path: 'capture.raw',
            writer: writer,
          ),
          startStream: () async => Stream<List<int>>.value(example.value),
        );

        await expectLater(
          capture.finish(),
          throwsA(
            isA<ContainerizedAudioStreamException>().having(
              (error) => error.container,
              'container',
              example.key,
            ),
          ),
        );
        expect(writer.events.where((event) => event.startsWith('write:')),
            isEmpty);
        expect(writer.events.last, 'close');
      });
    }

    test('raw bytes are wrapped once and raw input is retained until commit',
        () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('raw-finalization-');
      addTearDown(() => directory.delete(recursive: true));
      final String rawPath = '${directory.path}/capture.raw';
      final String wavPath = '${directory.path}/capture.wav';
      final ReservedRawPcmFile reserved = await reserveUnusedRawPcmFile(
        nextCandidate: () => rawPath,
      );
      final RawPcmCapture capture = await RawPcmCapture.start(
        reservedFile: reserved,
        startStream: () async => Stream<List<int>>.fromIterable(
          <List<int>>[
            <int>[1, 2],
            <int>[3, 4],
          ],
        ),
      );
      await capture.finish();

      await writeFinalizedWavSegment(
        rawInputPath: rawPath,
        outputPath: wavPath,
        sampleRate: 48000,
        bitRate: 768000,
      );

      final Uint8List wav = await File(wavPath).readAsBytes();
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(wav.sublist(44), <int>[1, 2, 3, 4]);
      expect(await File(rawPath).readAsBytes(), <int>[1, 2, 3, 4]);
    });
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeAllocator implements RawPcmFileAllocator {
  final Set<String> collisions;
  final List<String> attempts = <String>[];

  _FakeAllocator({this.collisions = const <String>{}});

  @override
  Future<RawPcmWriter?> tryReserveExclusive(String path) async {
    attempts.add(path);
    if (collisions.contains(path)) return null;
    return _FakeWriter();
  }
}

class _FakeWriter implements RawPcmWriter {
  final List<String> events = <String>[];
  final List<Completer<void>> writeGates;
  final int? failWriteAt;
  int _writeIndex = 0;

  _FakeWriter({
    this.writeGates = const <Completer<void>>[],
    this.failWriteAt,
  });

  @override
  Future<void> write(List<int> bytes) async {
    final int index = _writeIndex++;
    events.add('write:$bytes');
    if (index < writeGates.length) {
      await writeGates[index].future;
    }
    if (failWriteAt == index) {
      throw FileSystemException('write failed');
    }
  }

  @override
  Future<void> flush() async {
    events.add('flush');
  }

  @override
  Future<void> close() async {
    events.add('close');
  }
}
