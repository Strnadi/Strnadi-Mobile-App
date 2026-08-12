typedef AsyncFirebaseInitializer = Future<void> Function();
typedef FirebaseBackgroundHandlerRegistrar = void Function();

/// Runs Firebase core setup in a strict order.
///
/// Registering the background callback before Firebase initialization has
/// completed can leave startup in a partially initialized state. Keeping this
/// tiny coordinator platform-free also lets tests verify the ordering without
/// loading Firebase.
Future<void> initializeFirebaseCoreRuntime({
  required AsyncFirebaseInitializer initializeApp,
  required FirebaseBackgroundHandlerRegistrar registerBackgroundHandler,
}) async {
  await initializeApp();
  registerBackgroundHandler();
}

class NotificationRuntimeInitializationResult {
  const NotificationRuntimeInitializationResult({
    required this.localNotificationsInitialized,
    required this.messagingInitialized,
    this.localNotificationsError,
    this.messagingError,
  });

  final bool localNotificationsInitialized;
  final bool messagingInitialized;
  final Object? localNotificationsError;
  final Object? messagingError;

  bool get fullyInitialized =>
      localNotificationsInitialized && messagingInitialized;
}

/// Initializes both notification layers deterministically and awaits each one.
///
/// The second layer is still attempted if the first one fails. This keeps
/// foreground/background persistence and token maintenance available when the
/// local presentation plugin is unavailable, while returning every failure to
/// the caller instead of creating an unobserved future.
Future<NotificationRuntimeInitializationResult> initializeNotificationRuntime({
  required AsyncFirebaseInitializer initializeLocalNotifications,
  required AsyncFirebaseInitializer initializeMessaging,
}) async {
  Object? localError;
  Object? messagingError;

  try {
    await initializeLocalNotifications();
  } catch (error) {
    localError = error;
  }

  try {
    await initializeMessaging();
  } catch (error) {
    messagingError = error;
  }

  return NotificationRuntimeInitializationResult(
    localNotificationsInitialized: localError == null,
    messagingInitialized: messagingError == null,
    localNotificationsError: localError,
    messagingError: messagingError,
  );
}
