import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/recording_update_fields.dart';

RecordingPart _part() {
  return RecordingPart(
    id: 7,
    BEId: 70,
    recordingId: 4,
    backendRecordingId: 40,
    startTime: DateTime.utc(2026, 1, 2, 3),
    endTime: DateTime.utc(2026, 1, 2, 3, 1),
    gpsLatitudeStart: 50.0,
    gpsLatitudeEnd: 50.1,
    gpsLongitudeStart: 14.0,
    gpsLongitudeEnd: 14.1,
    path: 'logical://downloaded.wav',
    length: 1234,
    sent: true,
    uploadAttempted: true,
    uploadKey: 'part-key',
  );
}

void main() {
  group('captured recording ownership', () {
    test('binds a backend recording only to its explicit owner', () {
      expect(
        recordingBelongsToCapturedAccount(
          sent: true,
          ownerUserId: 42,
          capturedUserId: 42,
        ),
        isTrue,
      );
      expect(
        recordingBelongsToCapturedAccount(
          sent: true,
          ownerUserId: 7,
          capturedUserId: 42,
        ),
        isFalse,
      );
    });

    test('keeps a backend recording with no owner unowned', () {
      expect(
        recordingBelongsToCapturedAccount(
          sent: true,
          ownerUserId: null,
          capturedUserId: 42,
        ),
        isFalse,
      );
    });

    test('allows an unsent local draft to be claimed', () {
      expect(
        recordingBelongsToCapturedAccount(
          sent: false,
          ownerUserId: null,
          capturedUserId: 42,
        ),
        isTrue,
      );
    });
  });

  test('recording-part cache updates contain no request metadata or identity',
      () {
    final Map<String, Object?> fields = recordingPartCacheUpdateFields(_part());

    expect(
      fields,
      <String, Object?>{
        'path': 'logical://downloaded.wav',
        'length': 1234,
      },
    );
    for (final String forbidden in <String>[
      'id',
      'BEId',
      'recordingId',
      'backendRecordingId',
      'startTime',
      'endTime',
      'gpsLatitudeStart',
      'gpsLatitudeEnd',
      'gpsLongitudeStart',
      'gpsLongitudeEnd',
      'sent',
      'sending',
      'uploadAttempted',
      'uploadKey',
    ]) {
      expect(fields, isNot(contains(forbidden)));
    }
  });

  test('recording-part persistence round-trip retains its freeze marker', () {
    final RecordingPart roundTrip = RecordingPart.fromJson(_part().toJson());

    expect(roundTrip.uploadAttempted, isTrue);
    expect(roundTrip.BEId, 70);
    expect(roundTrip.uploadKey, 'part-key');
  });
}
