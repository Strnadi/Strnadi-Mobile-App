import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String repository = File(
    'lib/database/src/database_repository.dart',
  ).readAsStringSync();
  final String downloadAdapter = File(
    'lib/database/src/database_repository_download.dart',
  ).readAsStringSync();
  final String controller = File(
    'lib/api/controllers/recording_parts_controller.dart',
  ).readAsStringSync();
  final String mapPage = File(
    'lib/map/RecordingPage.dart',
  ).readAsStringSync();
  final String localListItem = File(
    'lib/localRecordings/recListItem.dart',
  ).readAsStringSync();

  test('repository and UI expose unambiguous local/backend entry points', () {
    expect(
      repository,
      contains('static Future<int> downloadRecordingByLocalId('),
    );
    expect(
      repository,
      contains('static Future<int> downloadRecordingByBackendId('),
    );
    expect(
      repository,
      isNot(contains('static Future<int?> downloadRecording(')),
    );
    expect(
      mapPage,
      contains('DatabaseNew.downloadRecordingByBackendId('),
    );
    expect(
      localListItem,
      contains('DatabaseNew.downloadRecordingByLocalId('),
    );
  });

  test('adapter never reads auth storage or uses mutable global host mid-run',
      () {
    expect(downloadAdapter, isNot(contains('FlutterSecureStorage')));
    expect(downloadAdapter, isNot(contains("read(key: 'token')")));
    expect(
      downloadAdapter,
      contains('accessToken: session.accessToken'),
    );
    expect(downloadAdapter, contains('host: session.backendHost'));
    expect(
      downloadAdapter,
      contains('_requireRecordingSessionCurrent(_sessions, session)'),
    );
  });

  test('cached success requires a readable local file', () {
    final String service = File(
      'lib/database/recording_download_service.dart',
    ).readAsStringSync();

    expect(service, contains('Future<bool> isReadable(String path)'));
    expect(service, contains('await _files.isReadable(target.path!)'));
    expect(downloadAdapter, contains('Future<bool> isReadable(String path)'));
    expect(downloadAdapter, contains('file.open(mode: FileMode.read)'));
  });

  test('cache paths are written only inside one database transaction', () {
    final int commitStart = downloadAdapter.indexOf(
      'Future<bool> commitDownload(',
    );
    final int apiStart = downloadAdapter.indexOf(
      'class _ControllerRecordingDownloadApi',
    );
    expect(commitStart, greaterThanOrEqualTo(0));
    expect(apiStart, greaterThan(commitStart));
    final String commit = downloadAdapter.substring(commitStart, apiStart);
    final String beforeCommit = downloadAdapter.substring(0, commitStart);

    expect(beforeCommit, isNot(contains("txn.update(")));
    expect(beforeCommit, isNot(contains("'path':")));
    expect(
      downloadAdapter,
      isNot(contains('updateRecordingPartCacheState')),
    );
    expect(downloadAdapter, isNot(contains('updateRecordingCacheState')));
    expect(commit, contains('db.transaction<bool>'));
    expect(commit, contains("txn.update(\n          'recordingParts'"));
    expect(commit, contains("txn.update(\n        'recordings'"));
    expect(commit, contains("'path': part.path"));
    expect(commit, contains("'path': commit.recordingPath"));
    expect(commit, contains("'downloaded': 1"));
  });

  test('transaction pins owner, environment, and both identities', () {
    final int commitStart = downloadAdapter.indexOf(
      'Future<bool> commitDownload(',
    );
    final int apiStart = downloadAdapter.indexOf(
      'class _ControllerRecordingDownloadApi',
    );
    final String commit = downloadAdapter.substring(commitStart, apiStart);

    expect(commit, contains('id = ? AND BEId = ? AND env = ?'));
    expect(commit, contains('userId IS ? AND mail IS ?'));
    expect(commit, contains('recordingId = ?'));
    expect(commit, contains('backendRecordingId = ?'));
    expect(commit, contains('COALESCE(sent, 0) = 1'));
    expect(commit, contains('uploadLease IS NULL'));
    expect(commit, contains('currentPartRows.length != commit.parts.length'));
    expect(
      commit,
      contains('currentPartIdentities.containsAll(committedPartIdentities)'),
    );
    expect(downloadAdapter, contains('reconcileDownloadCommit('));
    expect(downloadAdapter, contains('partsCommitted'));
    expect(downloadAdapter, contains('partsAbsent'));
  });

  test('download controller requires captured credentials and rejects replay',
      () {
    final int start = controller.indexOf(
      'Future<Response<List<int>>> downloadPartSound',
    );
    expect(start, greaterThanOrEqualTo(0));
    final String download = controller.substring(start);

    expect(download, contains('required String accessToken'));
    expect(download, contains('required String host'));
    expect(download, contains("'Authorization': 'Bearer \$accessToken'"));
    expect(download, contains('host: host'));
    expect(download, contains('followRedirects: false'));
    expect(download, contains('maxRedirects: 0'));
  });
}
