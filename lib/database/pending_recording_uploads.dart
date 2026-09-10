import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/database/Models/recording.dart';

/// Restores scheduling for reviewed offline captures in the active scope.
/// Partial/ambiguous uploads stay in the existing explicit recovery flow.
class PendingRecordingUploads {
  PendingRecordingUploads({
    required this.captureSession,
    required this.environment,
    required this.isCurrent,
    required this.canUpload,
    required this.loadRecordings,
    required this.schedule,
    required this.onError,
  });

  final String Function() environment;
  final Future<ActivatedAuthSessionSnapshot?> Function() captureSession;
  final Future<bool> Function(ActivatedAuthSessionSnapshot) isCurrent;
  final Future<bool> Function() canUpload;
  final Future<List<Recording>> Function() loadRecordings;
  final Future<void> Function(int) schedule;
  final void Function(Object, StackTrace) onError;
  bool _running = false;
  bool _disposed = false;

  void dispose() => _disposed = true;

  Future<void> retry() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final capturedEnvironment = environment();
      final session = await captureSession();
      if (session?.verified != true || !await canUpload() || _disposed) return;
      final recordings = await loadRecordings();
      for (final recording in recordings) {
        if (_disposed ||
            !await isCurrent(session!) ||
            environment() != capturedEnvironment) {
          return;
        }
        if (recording.env != capturedEnvironment ||
            recording.userId.toString() != session.userId ||
            recording.id == null ||
            recording.id! <= 0 ||
            !recording.captureReviewed ||
            recording.sent ||
            recording.sending ||
            recording.BEId != null ||
            recording.parentUploadAttempted ||
            recording.uploadLease != null) {
          continue;
        }
        try {
          await schedule(recording.id!);
        } catch (error, stackTrace) {
          onError(error, stackTrace);
        }
      }
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    } finally {
      _running = false;
    }
  }
}
