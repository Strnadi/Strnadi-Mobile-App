import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/localRecordings/incomplete_upload_prompt.dart';

void main() {
  testWidgets('session change cancels inspection and allows a fresh check',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold();
    })));
    final failures = <Object>[];
    await IncompleteUploadPrompt.checkAndPrompt(
      context,
      findIncompleteUploads: (_) async =>
          throw const RecordingUploadSessionChangedException(),
      reportFailure: (error, stack) => failures.add(error),
    );
    expect(failures, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    var checks = 0;
    await IncompleteUploadPrompt.checkAndPrompt(
      context,
      findIncompleteUploads: (_) async {
        checks++;
        return [];
      },
      reportFailure: (error, stack) => failures.add(error),
    );
    expect(checks, 1);
    expect(failures, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unexpected inspection failures are still reported',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (value) {
      context = value;
      return const Scaffold();
    })));
    final failure = StateError('Mock persistence read failed');
    final failures = <Object>[];
    await IncompleteUploadPrompt.checkAndPrompt(
      context,
      findIncompleteUploads: (_) async => throw failure,
      reportFailure: (error, stack) => failures.add(error),
    );
    expect(failures, [failure]);
    expect(tester.takeException(), isNull);
  });
}
