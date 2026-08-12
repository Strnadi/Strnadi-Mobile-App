/// Runs logout side effects in the only order that cannot assign a delayed
/// analytics event or identity reset to the next signed-in account.
Future<void> runOrderedLogoutCleanup({
  required Future<void> Function() captureLogoutEvent,
  required Future<void> Function() resetAnalyticsIdentity,
  required Future<void> Function() deleteDeviceToken,
  required Future<void> Function() clearAuthSession,
  required Future<void> Function() signOutIdentityProvider,
}) async {
  await captureLogoutEvent();
  await resetAnalyticsIdentity();
  await deleteDeviceToken();
  await clearAuthSession();
  await signOutIdentityProvider();
}
