import 'package:strnadi/database/recording_upload_scheduling.dart';

enum BackgroundRecordingUploadNotice {
  missingId,
  databaseReadFailure,
  notFound,
  uploadSucceeded,
  uploadFailed,
}

typedef BackgroundRecordingLoader<T> = Future<T?> Function(int recordingId);
typedef BackgroundRecordingReconciler = Future<void> Function();
typedef BackgroundRecordingUploader<T> = Future<void> Function(T recording);
typedef BackgroundRecordingDialectSender = Future<void> Function(
  int recordingId,
  int? backendRecordingId,
);
typedef BackgroundRecordingNoticeSender = Future<void> Function(
  BackgroundRecordingUploadNotice notice,
  int? recordingId,
);
typedef BackgroundRecordingHealthStarter = Future<bool> Function(
  int recordingId,
);
typedef BackgroundRecordingHealthStopper = Future<void> Function(
  int recordingId,
);
typedef BackgroundRecordingRetryClassifier = bool Function(Object error);
typedef BackgroundRecordingTaskFailure = void Function(
  Object error,
  StackTrace stackTrace,
);
typedef BackgroundRecordingAncillaryFailure = void Function(
  String operation,
  Object error,
  StackTrace stackTrace,
);
typedef BackgroundRecordingTaskInitializer = Future<void> Function();
typedef BackgroundRecordingTaskHandler = Future<bool> Function(
  Map<String, dynamic>? inputData,
);
typedef BackgroundUnknownTaskReporter = void Function(String taskName);

/// Routes a Workmanager callback through testable initialization and task
/// boundaries. Unknown task names complete successfully so they are not
/// retried forever by the platform scheduler.
Future<bool> dispatchBackgroundRecordingTask({
  required String taskName,
  required Map<String, dynamic>? inputData,
  required BackgroundRecordingTaskInitializer initialize,
  required BackgroundRecordingTaskHandler handleRecordingTask,
  BackgroundUnknownTaskReporter? onUnknownTask,
}) async {
  await initialize();
  if (!isRecordingBackgroundTaskName(taskName)) {
    onUnknownTask?.call(taskName);
    return true;
  }
  return handleRecordingTask(inputData);
}

/// Executes one scheduled recording upload through injected boundaries.
///
/// This function deliberately knows nothing about SQLite, Dio, Workmanager, or
/// notifications. Production supplies those adapters; tests can therefore
/// exercise every retry and failure branch without real API or database I/O.
Future<bool> handleBackgroundRecordingUploadTask<T>({
  required Object? rawRecordingId,
  required BackgroundRecordingLoader<T> loadRecording,
  required BackgroundRecordingReconciler reconcileInterruptedUploads,
  required bool Function(T recording) recordingIsSending,
  required int? Function(T recording) backendRecordingId,
  required BackgroundRecordingUploader<T> uploadRecording,
  required BackgroundRecordingDialectSender sendDialects,
  required BackgroundRecordingNoticeSender sendNotice,
  required BackgroundRecordingHealthStarter startHealth,
  required BackgroundRecordingHealthStopper stopHealth,
  required BackgroundRecordingRetryClassifier isRetryable,
  BackgroundRecordingTaskFailure? onTaskFailure,
  BackgroundRecordingAncillaryFailure? onAncillaryFailure,
}) async {
  Future<void> notify(
    BackgroundRecordingUploadNotice notice,
    int? recordingId,
  ) async {
    try {
      await sendNotice(notice, recordingId);
    } catch (error, stackTrace) {
      try {
        onAncillaryFailure?.call(
          'notification',
          error,
          stackTrace,
        );
      } catch (_) {
        // Failure reporting is ancillary too.
      }
    }
  }

  final int? recordingId = parseScheduledRecordingId(rawRecordingId);
  if (recordingId == null) {
    await notify(BackgroundRecordingUploadNotice.missingId, null);
    return true;
  }

  T? recording;
  try {
    recording = await loadRecording(recordingId);
  } catch (_) {
    await notify(
      BackgroundRecordingUploadNotice.databaseReadFailure,
      recordingId,
    );
    return false;
  }
  if (recording == null) {
    await notify(BackgroundRecordingUploadNotice.notFound, recordingId);
    return true;
  }

  bool healthStarted = false;
  try {
    await reconcileInterruptedUploads();
    recording = await loadRecording(recordingId);
    if (recording == null) {
      throw StateError(
        'Recording disappeared during upload reconciliation.',
      );
    }
    if (recordingIsSending(recording)) {
      throw StateError('Recording upload is already active.');
    }

    try {
      healthStarted = await startHealth(recordingId);
    } catch (error, stackTrace) {
      try {
        onAncillaryFailure?.call(
          'health registration',
          error,
          stackTrace,
        );
      } catch (_) {
        // Failure reporting is ancillary too.
      }
    }

    await uploadRecording(recording);
    await sendDialects(recordingId, backendRecordingId(recording));
    await notify(
      BackgroundRecordingUploadNotice.uploadSucceeded,
      recordingId,
    );
    return true;
  } catch (error, stackTrace) {
    try {
      onTaskFailure?.call(error, stackTrace);
    } catch (_) {
      // Failure reporting must not alter Workmanager retry classification.
    }
    await notify(
      BackgroundRecordingUploadNotice.uploadFailed,
      recordingId,
    );
    return !isRetryable(error);
  } finally {
    if (healthStarted) {
      try {
        await stopHealth(recordingId);
      } catch (error, stackTrace) {
        try {
          onAncillaryFailure?.call(
            'health shutdown',
            error,
            stackTrace,
          );
        } catch (_) {
          // Failure reporting is ancillary too.
        }
      }
    }
  }
}
