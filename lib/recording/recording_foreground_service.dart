import 'package:flutter_foreground_task/flutter_foreground_task.dart';

abstract interface class RecordingForegroundService {
  Future<bool> isRunning();

  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required void Function() callback,
  });

  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  });

  Future<void> stop();
}

final class FlutterRecordingForegroundService
    implements RecordingForegroundService {
  const FlutterRecordingForegroundService();

  @override
  Future<bool> isRunning() => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required void Function() callback,
  }) async {
    final ServiceRequestResult result =
        await FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: callback,
      serviceTypes: const <ForegroundServiceTypes>[
        ForegroundServiceTypes.microphone,
      ],
    );
    _throwIfFailed(result, operation: 'start');
  }

  @override
  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  }) async {
    final ServiceRequestResult result =
        await FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
    _throwIfFailed(result, operation: 'update');
  }

  @override
  Future<void> stop() async {
    final ServiceRequestResult result =
        await FlutterForegroundTask.stopService();
    _throwIfFailed(result, operation: 'stop');
  }

  static void _throwIfFailed(
    ServiceRequestResult result, {
    required String operation,
  }) {
    if (result is ServiceRequestFailure) {
      throw RecordingForegroundServiceOperationException(
        operation: operation,
        cause: result.error,
      );
    }
  }
}

final class RecordingForegroundServiceOperationException implements Exception {
  const RecordingForegroundServiceOperationException({
    required this.operation,
    required this.cause,
  });

  final String operation;
  final Object cause;

  @override
  String toString() => 'Recording foreground service $operation failed: $cause';
}

final class RecordingForegroundServiceStopException implements Exception {
  const RecordingForegroundServiceStopException({
    required this.attempts,
    required this.cause,
  });

  final int attempts;
  final Object cause;

  @override
  String toString() =>
      'Recording foreground service remained active after $attempts '
      'stop attempt(s): $cause';
}

Future<void> stopRecordingForegroundService({
  required RecordingForegroundService service,
  int maxAttempts = 2,
}) async {
  if (maxAttempts <= 0) {
    throw ArgumentError.value(
      maxAttempts,
      'maxAttempts',
      'must be greater than zero',
    );
  }

  Object? lastError;
  StackTrace? lastStackTrace;
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      if (!await service.isRunning()) {
        return;
      }
      await service.stop();
      if (!await service.isRunning()) {
        return;
      }
      throw StateError('The service still reports itself as running.');
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }

  final RecordingForegroundServiceStopException failure =
      RecordingForegroundServiceStopException(
    attempts: maxAttempts,
    cause: lastError ?? StateError('Unknown foreground service stop failure.'),
  );
  if (lastStackTrace != null) {
    Error.throwWithStackTrace(failure, lastStackTrace);
  }
  throw failure;
}

Future<void> reconcileStaleRecordingForegroundService({
  required RecordingForegroundService service,
}) {
  return stopRecordingForegroundService(service: service);
}
