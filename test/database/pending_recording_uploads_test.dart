import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/pending_recording_uploads.dart';

void main() {
  const session = ActivatedAuthSessionSnapshot(
    accessToken: 'mock',
    userId: '42',
    subject: 'bird@example.test',
    sessionId: 'a',
    verified: true,
  );
  Recording recording(int id) => Recording(
    id: id,
    userId: 42,
    createdAt: DateTime(2026),
    estimatedBirdsCount: 1,
    byApp: true,
    partCount: 1,
    env: 'dev',
  );
  late bool online, current;
  late String environment;
  late List<Recording> recordings;
  late List<int> queued;
  late List<Object> errors;
  late PendingRecordingUploads retry;
  Future<void> Function(int)? scheduler;
  setUp(() {
    online = true;
    current = true;
    environment = 'dev';
    recordings = [recording(1), recording(2)];
    queued = [];
    errors = [];
    scheduler = null;
    retry = PendingRecordingUploads(
      environment: () => environment,
      captureSession: () async => session,
      isCurrent: (_) async => current,
      canUpload: () async => online,
      loadRecordings: () async => recordings,
      schedule: (id) async {
        queued.add(id);
        await scheduler?.call(id);
      },
      onError: (error, _) => errors.add(error),
    );
  });
  test(
    'offline queue resumes all recordings when connectivity returns',
    () async {
      online = false;
      await retry.retry();
      expect(queued, isEmpty);
      online = true;
      await retry.retry();
      expect(queued, [1, 2]);
    },
  );
  test(
    'skips drafts, completed, active, ambiguous, and other scopes',
    () async {
      recordings = [
        recording(1)..captureReviewed = false,
        recording(2)..sent = true,
        recording(3)..sending = true,
        recording(4)..BEId = 123,
        recording(5)..parentUploadAttempted = true,
        recording(6)..uploadLease = 'lease',
        recording(7)..userId = 99,
        recording(8)..env = 'prod',
        recording(9),
      ];
      await retry.retry();
      expect(queued, [9]);
    },
  );
  test('a failed registration does not prevent later recordings', () async {
    scheduler = (id) async {
      if (id == 1) throw StateError('mock');
    };
    await retry.retry();
    expect(queued, [1, 2]);
    expect(errors, hasLength(1));
  });
  for (final change in ['session', 'environment', 'dispose']) {
    test('stops remaining work after $change changes', () async {
      scheduler = (_) async {
        if (change == 'session') current = false;
        if (change == 'environment') environment = 'prod';
        if (change == 'dispose') retry.dispose();
      };
      await retry.retry();
      expect(queued, [1]);
    });
  }
  test('overlapping reconnect events do not schedule duplicate work', () async {
    final gate = Completer<void>();
    scheduler = (_) => gate.future;
    final first = retry.retry();
    await Future<void>.delayed(Duration.zero);
    await retry.retry();
    expect(queued, [1]);
    gate.complete();
    await first;
    expect(queued, [1, 2]);
  });
}
