enum QueuedRecordingUploadStatus { ready, offline, waitingForWifi }

/// Register durable work even while offline. Connectivity only selects the
/// confirmation message; the worker rechecks policy and session before upload.
Future<QueuedRecordingUploadStatus> queueRecordingUpload({
  required Future<void> Function() schedule,
  required Future<bool> Function() hasInternet,
  required Future<bool> Function() canUpload,
}) async {
  await schedule();
  if (!await hasInternet()) return QueuedRecordingUploadStatus.offline;
  if (!await canUpload()) return QueuedRecordingUploadStatus.waitingForWifi;
  return QueuedRecordingUploadStatus.ready;
}
