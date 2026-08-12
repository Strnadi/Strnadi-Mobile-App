import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/recording/recording_foreground_service.dart';

void main() {
  group('recording foreground service lifecycle (fake platform only)', () {
    test('an already stopped service is not sent a stop request', () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(running: false);

      await stopRecordingForegroundService(service: service);

      expect(service.runningChecks, 1);
      expect(service.stopCalls, 0);
    });

    test('a running service is stopped and verified', () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(running: true);

      await stopRecordingForegroundService(service: service);

      expect(service.runningChecks, 2);
      expect(service.stopCalls, 1);
      expect(service.running, isFalse);
    });

    test('a transient stop exception is retried', () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(
        running: true,
        stopFailures: <Object>[StateError('transient platform failure')],
      );

      await stopRecordingForegroundService(service: service);

      expect(service.stopCalls, 2);
      expect(service.running, isFalse);
    });

    test('a false success is detected and retried', () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(
        running: true,
        stopsThatLeaveServiceRunning: 1,
      );

      await stopRecordingForegroundService(service: service);

      expect(service.stopCalls, 2);
      expect(service.running, isFalse);
    });

    test('exhausted stop attempts expose the platform failure', () async {
      final StateError finalFailure = StateError('still owned by Android');
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(
        running: true,
        stopFailures: <Object>[
          StateError('first failure'),
          finalFailure,
        ],
      );

      await expectLater(
        stopRecordingForegroundService(service: service),
        throwsA(
          isA<RecordingForegroundServiceStopException>()
              .having((error) => error.attempts, 'attempts', 2)
              .having((error) => error.cause, 'cause', same(finalFailure)),
        ),
      );

      expect(service.stopCalls, 2);
      expect(service.running, isTrue);
    });

    test('cold-start reconciliation uses the same verified stop path',
        () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(running: true);

      await reconcileStaleRecordingForegroundService(service: service);

      expect(service.stopCalls, 1);
      expect(service.running, isFalse);
    });

    test('a non-positive attempt bound is rejected without platform access',
        () async {
      final _FakeRecordingForegroundService service =
          _FakeRecordingForegroundService(running: true);

      await expectLater(
        stopRecordingForegroundService(
          service: service,
          maxAttempts: 0,
        ),
        throwsArgumentError,
      );

      expect(service.runningChecks, 0);
      expect(service.stopCalls, 0);
    });
  });
}

final class _FakeRecordingForegroundService
    implements RecordingForegroundService {
  _FakeRecordingForegroundService({
    required this.running,
    List<Object> stopFailures = const <Object>[],
    this.stopsThatLeaveServiceRunning = 0,
  }) : _stopFailures = List<Object>.of(stopFailures);

  bool running;
  int stopsThatLeaveServiceRunning;
  final List<Object> _stopFailures;
  int runningChecks = 0;
  int startCalls = 0;
  int updateCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> isRunning() async {
    runningChecks++;
    return running;
  }

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required void Function() callback,
  }) async {
    startCalls++;
    running = true;
  }

  @override
  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (_stopFailures.isNotEmpty) {
      throw _stopFailures.removeAt(0);
    }
    if (stopsThatLeaveServiceRunning > 0) {
      stopsThatLeaveServiceRunning--;
      return;
    }
    running = false;
  }
}
