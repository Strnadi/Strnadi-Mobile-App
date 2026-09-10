import 'package:strnadi/auth/administration/app_administration.dart';

/// Runs logout side effects in the only order that cannot assign a delayed
/// analytics event or identity reset to the next signed-in account.
Future<void> runOrderedLogoutCleanup({
  required Future<void> Function() captureLogoutEvent,
  required Future<void> Function() resetAnalyticsIdentity,
  required Future<void> Function() deleteDeviceToken,
  required Future<void> Function() clearAuthSession,
  required Future<void> Function() signOutIdentityProvider,
  Future<void> Function()? afterCleanup,
}) async {
  final endBrowserSession = AppAdministration.captureBrowserLogout();
  await captureLogoutEvent();
  await resetAnalyticsIdentity();
  await deleteDeviceToken();
  await AppAdministration.close();
  await clearAuthSession();
  await signOutIdentityProvider();
  await endBrowserSession?.call();
  // Environment changes belong after credential/device cleanup and before the
  // caller navigates to authentication on the new backend.
  await afterCleanup?.call();
}
