import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/Models/recordingPart.dart';

void main() {
  group('recording upload fingerprint persistence (no API or DB)', () {
    test('recording-part JSON round-trips frozen content identity', () {
      final RecordingPart original = RecordingPart(
        id: 7,
        recordingId: 42,
        startTime: DateTime.utc(2026, 7, 18, 8),
        endTime: DateTime.utc(2026, 7, 18, 8, 0, 1),
        gpsLatitudeStart: 50,
        gpsLatitudeEnd: 50.1,
        gpsLongitudeStart: 14,
        gpsLongitudeEnd: 14.1,
        path: '/mock/part.wav',
        uploadKey: 'part-key-7',
        uploadContentSha256: List<String>.filled(64, 'a').join(),
        uploadContentBytes: 4096,
      );

      final RecordingPart restored = RecordingPart.fromJson(original.toJson());

      expect(restored.uploadContentSha256, original.uploadContentSha256);
      expect(restored.uploadContentBytes, 4096);
    });

    test('fresh and upgraded schemas contain both fingerprint columns', () {
      final String repository =
          File('lib/database/src/database_repository.dart').readAsStringSync();

      expect(repository, contains('uploadContentSha256 TEXT'));
      expect(repository, contains('uploadContentBytes INTEGER'));
      expect(
        repository,
        contains("'recordingParts',\n          'uploadContentSha256'"),
      );
      expect(
        repository,
        contains("'recordingParts',\n          'uploadContentBytes'"),
      );
    });

    test('production store freezes only under the current aggregate lease', () {
      final String adapter = File(
        'lib/database/src/database_repository_api.dart',
      ).readAsStringSync();
      final int start = adapter.indexOf(
        'Future<void> freezeRecordingPartContent(',
      );
      final int end = adapter.indexOf(
        'Future<void> saveRecordingPart(',
        start,
      );
      final String method = adapter.substring(start, end);

      expect(start, greaterThanOrEqualTo(0));
      expect(method, contains('COALESCE(sent, 0) = 0'));
      expect(method, contains('uploadContentSha256 IS NULL'));
      expect(method, contains('LOWER(uploadContentSha256) = ?'));
      expect(method, contains('r.uploadLease = ?'));
      expect(method, contains('if (changed != 1)'));
    });

    test('production file probe validates WAV and computes SHA-256', () {
      final String adapter = File(
        'lib/database/src/database_repository_api.dart',
      ).readAsStringSync();
      final int start = adapter.indexOf(
        'class _LocalRecordingUploadFileProbe',
      );
      final int end = adapter.indexOf(
        'Future<bool> _handleDeletedPath',
        start,
      );
      final String probe = adapter.substring(start, end);

      expect(probe, contains('readWavPcmDataRegion('));
      expect(probe, contains('region.dataLength <= 0'));
      expect(probe, contains('sha256.bind(file.openRead()).first'));
      expect(probe, contains('after.size != before.size'));
      expect(probe, contains('after.modified != before.modified'));
    });

    test('service persists preflight identity and checks again before POST',
        () {
      final String service =
          File('lib/database/recording_upload_service.dart').readAsStringSync();
      final int preflight = service.indexOf(
        '_preflightRequiredPartFiles(',
      );
      final int parentPost = service.indexOf(
        '_api.createRecording(',
        preflight,
      );
      final int uploadVerification = service.indexOf(
        '_verifyPartContentBeforeUpload(',
        parentPost,
      );
      final int partPost = service.indexOf(
        '_api.uploadRecordingPart(',
        uploadVerification,
      );

      expect(preflight, greaterThanOrEqualTo(0));
      expect(parentPost, greaterThan(preflight));
      expect(uploadVerification, greaterThan(parentPost));
      expect(partPost, greaterThan(uploadVerification));
      expect(
        service,
        contains('await _store.freezeRecordingPartContent('),
      );
      expect(
        service,
        contains('changed after upload preflight'),
      );
      expect(
        service,
        contains('content changed after its upload request'),
      );
    });

    test(
        'production adapter maps only frozen-source changes to validation and '
        'reports ancillary cleanup', () {
      final String adapter = File(
        'lib/database/src/database_repository_api.dart',
      ).readAsStringSync();
      final int start = adapter.indexOf('class _BackendRecordingUploadApi');
      final int end = adapter.indexOf(
        'class _SecureStorageRecordingUploadSessions',
        start,
      );
      final String uploadAdapter = adapter.substring(start, end);

      expect(uploadAdapter, contains('on ImmutableUploadSourceException'));
      expect(uploadAdapter, isNot(contains('on FileSystemException')));
      expect(
        uploadAdapter,
        contains('onCleanupError: _reportRecordingUploadStageCleanupError'),
      );
      expect(
        uploadAdapter,
        contains('Recording upload temporary stage cleanup failed.'),
      );
    });
  });
}
