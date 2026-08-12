import 'package:strnadi/database/recording_upload_service.dart';

typedef RecordingCaptureReviewLoader = Future<bool?> Function(int recordingId);
typedef RecordingBackgroundScheduler = Future<void> Function(int recordingId);

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
