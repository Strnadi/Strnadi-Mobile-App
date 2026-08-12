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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/recording/streamRec.dart').readAsStringSync();
  });

  test('production recorder captures PCM through startStream only', () {
    expect(source, contains('_audioRecorder.startStream(config)'));
    expect(
      source,
      isNot(
        matches(
          RegExp(r'_audioRecorder\.start\(\s*config,\s*path:'),
        ),
      ),
    );
    expect(source, contains('reserveUnusedRawPcmFile('));
    expect(source, contains("audio_\${timestamp}_\$sequence.raw"));
  });

  test('physical stop is followed by the raw capture drain barrier', () {
    final int stopMethod =
        source.indexOf('Future<void> _stopActiveSegmentForFinalization');
    final int stopCall =
        source.indexOf('await _audioRecorder.stop()', stopMethod);
    final int drainCall =
        source.indexOf('await _finishActiveRawPcmCapture()', stopCall);
    final int wavWrite =
        source.indexOf('await writeFinalizedWavSegment(', drainCall);

    expect(stopMethod, greaterThanOrEqualTo(0));
    expect(stopCall, greaterThan(stopMethod));
    expect(drainCall, greaterThan(stopCall));
    expect(wavWrite, greaterThan(drainCall));
  });

  test('raw input is deleted only after finalized metadata is committed', () {
    final int finalizer =
        source.indexOf('Future<void> _finalizePendingSegment');
    final int wavWrite =
        source.indexOf('await writeFinalizedWavSegment(', finalizer);
    final int pathCommit =
        source.indexOf('segmentPaths[rawPathIndex] = finalizedPath', wavWrite);
    final int metadataCommit =
        source.indexOf('recordingPartsList.add(part)', pathCommit);
    final int pendingCommit =
        source.indexOf('_segmentFinalizationPending = false', metadataCommit);
    final int rawDelete = source.indexOf(
      'IoSegmentFileOperations().deleteIfExists(rawPath)',
      pendingCommit,
    );

    expect(wavWrite, greaterThan(finalizer));
    expect(pathCommit, greaterThan(wavWrite));
    expect(metadataCommit, greaterThan(pathCommit));
    expect(pendingCommit, greaterThan(metadataCommit));
    expect(rawDelete, greaterThan(pendingCommit));
  });

  test('capture failure aborts but remains attached to block finalization', () {
    expect(source, contains('await _abortActiveRawPcmCapture()'));
    expect(
      source,
      contains(
        'Keep the aborted capture attached. Its finish() method will continue',
      ),
    );
    expect(source, contains('await _finishActiveRawPcmCapture();'));
  });

  test('guest state is fail closed and passed to the notification bell', () {
    expect(source, contains('bool _isGuestUser = true;'));
    expect(
      RegExp(r'NotificationBellButton\(\s*'
              r'isGuestUser: _isGuestUser,\s*'
              r'recorderExitPolicy: changeConfirmation,')
          .hasMatch(source),
      isTrue,
    );
  });

  test('completed capture is durable before the metadata form opens', () {
    final int concat =
        source.indexOf('await concatWavFiles(paths, outputPath)');
    final int persist = source.indexOf(
      'RecordingDraftHandoffCoordinator.database().persistCapture(',
      concat,
    );
    final int navigate = source.indexOf('Navigator.pushReplacement(', persist);
    final int handoff = source.indexOf(
      'persistedDraft: persistedDraft',
      navigate,
    );

    expect(concat, greaterThanOrEqualTo(0));
    expect(persist, greaterThan(concat));
    expect(navigate, greaterThan(persist));
    expect(handoff, greaterThan(navigate));
    expect(
      source,
      contains(
        "t('postRecordingForm.recordingForm.dialogs.error.saveFailed')",
      ),
    );
  });

  test('a failed draft retry reuses the completed audio file', () {
    final int completedPath = source.indexOf(
      'String? outputPath = recordedFilePath',
    );
    final int existenceCheck = source.indexOf(
      'await File(outputPath).exists()',
      completedPath,
    );
    final int concatenate = source.indexOf(
      'await concatWavFiles(paths, outputPath)',
      existenceCheck,
    );

    expect(completedPath, greaterThanOrEqualTo(0));
    expect(existenceCheck, greaterThan(completedPath));
    expect(concatenate, greaterThan(existenceCheck));
  });

  test('an ambiguous draft commit cannot be retried or delete owned audio', () {
    expect(
      source,
      contains('bool _draftPersistenceMayHaveCommitted = false;'),
    );
    expect(
      source,
      contains(
        'error is RecordingDraftPersistenceException &&\n'
        '            error.mayHaveCommitted',
      ),
    );

    final int stop = source.indexOf('Future<void> _stop() async');
    final int blockedRetry = source.indexOf(
      'if (_draftPersistenceMayHaveCommitted)',
      stop,
    );
    final int persistence = source.indexOf(
      'RecordingDraftHandoffCoordinator.database().persistCapture(',
      blockedRetry,
    );
    final int exit = source.indexOf('Future<bool> changeConfirmation() async');
    final int retainedExit = source.indexOf(
      'if (_draftPersistenceMayHaveCommitted)',
      exit,
    );
    final int normalDelete = source.indexOf(
      'await _discardRecordingResources()',
      retainedExit,
    );

    expect(blockedRetry, greaterThan(stop));
    expect(persistence, greaterThan(blockedRetry));
    expect(retainedExit, greaterThan(exit));
    expect(normalDelete, greaterThan(retainedExit));
  });
}
