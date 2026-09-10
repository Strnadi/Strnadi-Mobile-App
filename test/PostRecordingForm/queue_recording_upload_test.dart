import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/PostRecordingForm/queue_recording_upload.dart';

void main() {
  for (final scenario in [
    (false, false, QueuedRecordingUploadStatus.offline),
    (true, false, QueuedRecordingUploadStatus.waitingForWifi),
    (true, true, QueuedRecordingUploadStatus.ready),
  ]) {
    test('queues every recording before reporting ${scenario.$3}', () async {
      final queued = <int>[];
      for (var id = 1; id <= 3; id++) {
        final status = await queueRecordingUpload(
          schedule: () async => queued.add(id),
          hasInternet: () async {
            expect(queued, contains(id));
            return scenario.$1;
          },
          canUpload: () async {
            expect(scenario.$1, isTrue);
            return scenario.$2;
          },
        );
        expect(status, scenario.$3);
      }
      expect(queued, [1, 2, 3]);
    });
  }

  test(
    'scheduler failure propagates instead of reporting a queued recording',
    () async {
      final failure = StateError('Scheduler unavailable');
      await expectLater(
        queueRecordingUpload(
          schedule: () async => throw failure,
          hasInternet: () async =>
              fail('Must not report successful scheduling'),
          canUpload: () async => fail('Must not report successful scheduling'),
        ),
        throwsA(same(failure)),
      );
    },
  );
}
