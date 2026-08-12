import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  late String prompt;
  late String recordingList;
  late String recordingItem;
  late String repository;
  late String uploadHelpers;

  setUpAll(() {
    prompt = _read('lib/localRecordings/incomplete_upload_prompt.dart');
    recordingList = _read('lib/localRecordings/recList.dart');
    recordingItem = _read('lib/localRecordings/recListItem.dart');
    repository = _read('lib/database/src/database_repository.dart');
    uploadHelpers =
        _read('lib/localRecordings/upload_integration_helpers.dart');
  });

  test('incomplete-upload prompt claims single-flight before DB inspection',
      () {
    final int check = prompt.indexOf('static Future<void> checkAndPrompt');
    final int claimed = prompt.indexOf('_showing = true;', check);
    final int lookup =
        prompt.indexOf('DatabaseNew.findIncompleteUploads', check);
    final int cleanup = prompt.indexOf('_showing = false;', lookup);
    final String guardedCheck = prompt.substring(check, cleanup);

    expect(check, greaterThanOrEqualTo(0));
    expect(claimed, greaterThan(check));
    expect(lookup, greaterThan(claimed));
    expect(cleanup, greaterThan(lookup));
    expect(guardedCheck, contains('catch (error, stackTrace)'));
    expect(guardedCheck, contains('finally'));
  });

  test('recording detail actions use the complete durable active state', () {
    expect(recordingItem, contains('recordingUploadIsActive('));
    expect(recordingItem, contains('recordingLease: _recording.uploadLease'));
    expect(recordingItem, contains('visible: _canStartUpload'));
    expect(recordingItem, contains('onPressed: _canResendUnsentParts'));
  });

  test('recording detail keeps refreshed data in State, not its Widget', () {
    expect(recordingItem, contains('final Recording recording;'));
    expect(recordingItem, contains('late Recording _recording;'));
    expect(recordingItem, contains('_recording = widget.recording;'));
    expect(
      recordingItem,
      contains('if (!identical(oldWidget.recording, widget.recording))'),
    );
    expect(recordingItem, isNot(contains('widget.recording =')));
  });

  test('bulk send skips records that already hold a durable lease', () {
    final int bulkSend = recordingList.indexOf('Future<void> sendAllUnsent()');
    final int build = recordingList.indexOf('@override', bulkSend);
    final String send = recordingList.substring(bulkSend, build);

    expect(send, contains('recordingUploadIsActive('));
    expect(send, contains('recordingLease: rec.uploadLease'));
  });

  test('bulk send is single-flight and disables its action while running', () {
    expect(
      recordingList,
      contains(
        '_sendAllSingleFlight.run(_sendAllUnsentOnce)',
      ),
    );
    expect(recordingList, contains('setState(() => _isSendingAll = true)'));
    expect(recordingList, contains('setState(() => _isSendingAll = false)'));
    expect(recordingList, contains('onPressed: _isSendingAll'));
  });

  test('incomplete discovery applies aggregate completion before prompting',
      () {
    final int discovery = repository.indexOf('findIncompleteUploads({');
    final int authoritativeCompletion = repository.indexOf(
      'backendSnapshot.authoritativelyConfirmsComplete(recording.BEId)',
      discovery,
    );
    final int decision = repository.indexOf(
      'aggregateUploadNeedsAttention(',
      discovery,
    );
    final int skip = repository.indexOf('if (!needsAttention)', decision);
    final int issue = repository.indexOf(
      'IncompleteRecordingUpload(',
      decision,
    );
    final String wiring = repository.substring(decision, skip);

    expect(discovery, greaterThanOrEqualTo(0));
    expect(authoritativeCompletion, greaterThan(discovery));
    expect(decision, greaterThan(discovery));
    expect(decision, greaterThan(authoritativeCompletion));
    expect(skip, greaterThan(decision));
    expect(issue, greaterThan(skip));
    expect(
      wiring,
      contains('backendExpectedPartsCount: backend?.expectedPartsCount'),
    );
    expect(
      wiring,
      contains('backendUploadedPartsCount: backend?.uploadedPartsCount'),
    );
    expect(wiring, contains('localSaysIncomplete: localSaysIncomplete'));
    expect(repository, contains('incompleteAggregateCanBeRetried('));
    expect(
      repository,
      contains('resendablePartsCount: aggregateCanBeRetried'),
    );
    expect(
      repository,
      matches(
        RegExp(
          r'reconcileAllBackendParts:\s*'
          r'backend\?\.requiresFullPartReconciliation \?\? false',
        ),
      ),
    );
    expect(
      repository,
      contains(
        'reconcileAllBackendParts: issue.reconcileAllBackendParts',
      ),
    );
  });

  test('successful empty backend scans stay distinct from unavailable scans',
      () {
    expect(
      uploadHelpers,
      contains('if (statusCode == 204)'),
    );
    expect(
      uploadHelpers,
      contains('if (statusCode != 200)'),
    );
    expect(
      uploadHelpers,
      contains('BackendIncompleteUploadSnapshot.authoritative(entries)'),
    );
    expect(
      uploadHelpers,
      contains('const BackendIncompleteUploadSnapshot.unavailable()'),
    );
  });

  test('prompt uses generic copy when online counts are not truly missing', () {
    expect(prompt, contains('backendMissingPartCountsAreDisplayable('));
    expect(
      prompt,
      contains('recordingUploadCheck.messages.singleUnknown'),
    );
    expect(
      prompt,
      contains('recordingUploadCheck.messages.multipleUnknown'),
    );
  });
}
