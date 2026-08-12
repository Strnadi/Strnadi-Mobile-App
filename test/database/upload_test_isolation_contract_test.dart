import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upload tests cannot open SQLite or target the production API', () {
    final List<File> uploadTests = <File>[
      ...Directory('test/database')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('_test.dart')),
      ...Directory('test/api')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('_test.dart')),
      ...Directory('test/localRecordings')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('_test.dart')),
      ...Directory('test/PostRecordingForm')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('_test.dart')),
    ]
        .where(
          (File file) =>
              !file.path.endsWith(
                'upload_test_isolation_contract_test.dart',
              ) &&
              !file.path.endsWith('database_adapter_contract_test.dart'),
        )
        .toList(growable: false);

    expect(uploadTests, isNotEmpty);
    for (final File testFile in uploadTests) {
      final String source = testFile.readAsStringSync();
      expect(
        source,
        isNot(contains("import 'package:sqflite/sqflite.dart'")),
        reason: '${testFile.path} must use a fake persistence boundary.',
      );
      expect(
        source,
        isNot(contains("import 'package:sqflite_common_ffi/")),
        reason: '${testFile.path} must not install an in-memory SQLite fake.',
      );
      expect(
        source,
        isNot(contains('DatabaseNew.initDb(')),
        reason: '${testFile.path} must never initialize the production DB.',
      );
      expect(
        source,
        isNot(contains('DatabaseNew.database')),
        reason: '${testFile.path} must never open the production DB.',
      );
      expect(
        source,
        isNot(contains('api.strnadi')),
        reason: '${testFile.path} must never reference the production API.',
      );
    }
  });

  test('behavioral API tests replace Dio networking with fake adapters', () {
    for (final String path in <String>[
      'test/api/filtered_recordings_controller_test.dart',
      'test/api/immutable_recording_part_upload_test.dart',
      'test/api/post_json_with_redirect_test.dart',
      'test/api/recording_parts_controller_test.dart',
      'test/api/recordings_controller_test.dart',
      'test/api/device_controller_test.dart',
      'test/api/account_controllers_test.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(
        source,
        contains('HttpClientAdapter'),
        reason: '$path must define a mocked transport.',
      );
      expect(
        source,
        contains('httpClientAdapter ='),
        reason: '$path must install the mocked transport before requests.',
      );
      expect(
        source,
        contains('example.test'),
        reason: '$path must use a reserved non-production host.',
      );
    }
  });

  test('aggregate upload tests use fake API, store, session, and file probes',
      () {
    final String source =
        File('test/database/recording_upload_service_test.dart')
            .readAsStringSync();

    for (final String fake in <String>[
      '_FakeUploadStore',
      '_FakeUploadApi',
      '_FakeSessionProvider',
      '_FakePolicy',
      '_FakeFileProbe',
    ]) {
      expect(source, contains(fake));
    }
    expect(source, isNot(contains('DatabaseNew.database')));
    expect(source, isNot(contains('ApiDioClient.instance')));
  });

  test('recording download tests use fake API, store, session, and files', () {
    final String source =
        File('test/database/recording_download_service_test.dart')
            .readAsStringSync();

    for (final String fake in <String>[
      '_FakeStore',
      '_FakeApi',
      '_FakeSessions',
      '_FakeFiles',
    ]) {
      expect(source, contains(fake));
    }
    expect(source, isNot(contains('DatabaseNew.database')));
    expect(source, isNot(contains('ApiDioClient.instance')));
  });
}
