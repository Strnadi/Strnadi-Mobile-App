import 'package:strnadi/utils/async_single_flight.dart';

typedef IncompleteRecordingUploadLookup = Future<bool> Function();
typedef IncompleteRecordingUploadHandler = Future<void> Function();
typedef RecordingUploadScheduler = Future<void> Function();

/// Coordinates one recording-send action from lookup through scheduling.
///
/// Keeping the incomplete-upload lookup inside the single-flight boundary is
/// important: two rapid taps can otherwise both observe an idle recording
/// before either one reaches the scheduler.
final class RecordingSendCoordinator {
  final AsyncSingleFlight _singleFlight = AsyncSingleFlight();

  bool get isRunning => _singleFlight.isRunning;

  Future<void> send({
    required IncompleteRecordingUploadLookup hasIncompleteUpload,
    required IncompleteRecordingUploadHandler handleIncompleteUpload,
    required RecordingUploadScheduler scheduleUpload,
  }) {
    return _singleFlight.run(() async {
      if (await hasIncompleteUpload()) {
        await handleIncompleteUpload();
        return;
      }
      await scheduleUpload();
    });
  }
}
