typedef BackgroundInitializationStep = Future<void> Function();

typedef BackgroundInitializationFailureReporter = void Function(
  String step,
  Object error,
  StackTrace stackTrace,
);

/// Initializes the background-upload isolate without allowing ancillary
/// notification or localization failures to suppress the upload itself.
///
/// Configuration remains authoritative because the upload cannot safely select
/// an API environment without it. Notifications and localized copy are
/// best-effort conveniences and are therefore isolated from the essential
/// initialization path.
Future<void> initializeBackgroundUploadRuntime({
  required BackgroundInitializationStep initializeEssentialConfiguration,
  required BackgroundInitializationStep initializeNotifications,
  required BackgroundInitializationStep initializeLocalization,
  BackgroundInitializationFailureReporter? onAncillaryFailure,
}) async {
  await initializeEssentialConfiguration();

  await _runAncillaryStep(
    name: 'notifications',
    action: initializeNotifications,
    onFailure: onAncillaryFailure,
  );
  await _runAncillaryStep(
    name: 'localization',
    action: initializeLocalization,
    onFailure: onAncillaryFailure,
  );
}

Future<void> _runAncillaryStep({
  required String name,
  required BackgroundInitializationStep action,
  BackgroundInitializationFailureReporter? onFailure,
}) async {
  try {
    await action();
  } catch (error, stackTrace) {
    try {
      onFailure?.call(name, error, stackTrace);
    } catch (_) {
      // Diagnostics must never become more authoritative than the upload.
    }
  }
}
