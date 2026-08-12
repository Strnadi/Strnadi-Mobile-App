import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('interrupted recording review recovery (source only; no API or DB)',
      () {
    late String listSource;

    setUpAll(() {
      listSource = File('lib/localRecordings/recList.dart').readAsStringSync();
    });

    test('unreviewed rows reopen the metadata form instead of upload details',
        () {
      final int openRecording =
          listSource.indexOf('Future<void> openRecording(');
      final int reviewedBranch = listSource.indexOf(
        'if (!recording.captureReviewed)',
        openRecording,
      );
      final int resume = listSource.indexOf(
        'await _resumeInterruptedRecordingDraft(recording)',
        reviewedBranch,
      );
      final int normalDetails = listSource.indexOf(
        'builder: (context) => RecordingItem(recording: recording)',
        resume,
      );

      expect(openRecording, greaterThanOrEqualTo(0));
      expect(reviewedBranch, greaterThan(openRecording));
      expect(resume, greaterThan(reviewedBranch));
      expect(normalDetails, greaterThan(resume));
    });

    test('recovery validates durable rows and passes the restored handoff', () {
      final int recovery = listSource.indexOf(
        'Future<void> _resumeInterruptedRecordingDraft(',
      );
      final int loadParts = listSource.indexOf(
        'DatabaseNew.getPartsByRecordingId(recordingId)',
        recovery,
      );
      final int restore = listSource.indexOf(
        'RecordingDraftHandoff.restorePersisted(',
        loadParts,
      );
      final int form = listSource.indexOf('RecordingForm(', restore);
      final int handoff = listSource.indexOf('persistedDraft: handoff', form);

      expect(recovery, greaterThanOrEqualTo(0));
      expect(loadParts, greaterThan(recovery));
      expect(restore, greaterThan(loadParts));
      expect(form, greaterThan(restore));
      expect(handoff, greaterThan(form));
      expect(
        listSource,
        contains("t('recList.errors.reviewRecoveryFailed')"),
      );
    });

    test('unreviewed rows are visibly labelled for review', () {
      expect(
        listSource,
        matches(
          RegExp(
            r"t\(\s*'recList\.status\.finishReview'\s*\)",
            multiLine: true,
          ),
        ),
      );
    });
  });
}
