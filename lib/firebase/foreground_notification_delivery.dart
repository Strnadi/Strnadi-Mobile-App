typedef ForegroundNotificationAction = Future<void> Function();

class ForegroundNotificationDeliveryResult {
  const ForegroundNotificationDeliveryResult({
    required this.displayed,
    required this.persisted,
    this.displayError,
    this.persistenceError,
  });

  final bool displayed;
  final bool persisted;
  final Object? displayError;
  final Object? persistenceError;

  bool get fullyDelivered => displayed && persisted;
}

/// Delivers one foreground push through two independent injected boundaries.
///
/// Presentation is attempted first so a database delay does not postpone the
/// user-visible notification. Persistence is always attempted even when
/// presentation fails. Both operations are awaited, making delivery failures
/// observable without allowing one ancillary boundary to suppress the other.
Future<ForegroundNotificationDeliveryResult> deliverForegroundNotification({
  required ForegroundNotificationAction display,
  required ForegroundNotificationAction persist,
}) async {
  Object? displayError;
  Object? persistenceError;

  try {
    await display();
  } catch (error) {
    displayError = error;
  }

  try {
    await persist();
  } catch (error) {
    persistenceError = error;
  }

  return ForegroundNotificationDeliveryResult(
    displayed: displayError == null,
    persisted: persistenceError == null,
    displayError: displayError,
    persistenceError: persistenceError,
  );
}
