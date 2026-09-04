import 'package:strnadi/database/recording_upload_service.dart';

typedef RecordingCaptureReviewLoader = Future<bool?> Function(int recordingId);
typedef RecordingBackgroundScheduler = Future<void> Function(int recordingId);

const String recordingBackgroundTaskName = 'sendRecording';
const String iosRecordingBackgroundTaskIdentifier =
    'com.delta.strnadi.sendRecording';

enum RecordingBackgroundExistingWorkPolicy { append, keep }

class RecordingBackgroundWorkRequest {
  RecordingBackgroundWorkRequest({
    required this.uniqueName,
    required this.taskName,
    required Map<String, int> inputData,
    required this.existingWorkPolicy,
  }) : inputData = Map<String, int>.unmodifiable(inputData);

  final String uniqueName;
  final String taskName;
  final Map<String, int> inputData;
  final RecordingBackgroundExistingWorkPolicy existingWorkPolicy;
}

bool persistedCaptureReviewFlag(Object? value) {
  return value == 1 || value == true;
}

int? parseScheduledRecordingId(Object? value) {
  final int? parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.isFinite && value == value.truncate() ? value.toInt() : null;
  } else if (value is String) {
    parsed = int.tryParse(value.trim());
  } else {
    parsed = null;
  }
  return parsed != null && parsed > 0 ? parsed : null;
}

bool isRecordingBackgroundTaskName(String taskName) {
  return taskName == recordingBackgroundTaskName ||
      taskName == iosRecordingBackgroundTaskIdentifier;
}

RecordingBackgroundWorkRequest buildRecordingBackgroundWorkRequest({
  required int recordingId,
  required bool isIOS,
}) {
  if (recordingId <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot build background work without a valid local recording id.',
    );
  }

  return RecordingBackgroundWorkRequest(
    uniqueName: isIOS
        ? iosRecordingBackgroundTaskIdentifier
        : '${recordingBackgroundTaskName}_$recordingId',
    taskName: isIOS
        ? iosRecordingBackgroundTaskIdentifier
        : recordingBackgroundTaskName,
    inputData: <String, int>{'recordingId': recordingId},
    existingWorkPolicy: isIOS
        ? RecordingBackgroundExistingWorkPolicy.append
        : RecordingBackgroundExistingWorkPolicy.keep,
  );
}

/// Resolves durable capture-review state before invoking a platform scheduler.
///
/// Both dependencies are injected so the failure boundary is testable without
/// opening SQLite or registering real background work.
Future<void> scheduleReviewedRecordingUpload({
  required int recordingId,
  required RecordingCaptureReviewLoader loadCaptureReviewed,
  required RecordingBackgroundScheduler schedule,
}) async {
  if (recordingId <= 0) {
    throw const RecordingUploadValidationException(
      'Cannot schedule a recording without a valid local id.',
    );
  }

  final bool? captureReviewed = await loadCaptureReviewed(recordingId);
  if (captureReviewed != true) {
    throw const RecordingUploadValidationException(
      'Recording capture must be reviewed before scheduling upload.',
    );
  }
  await schedule(recordingId);
}
