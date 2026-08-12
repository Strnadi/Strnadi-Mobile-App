enum DeviceTokenRefreshAction {
  none,
  register,
  update,
  remove,
}

String? _normalizedToken(String? token) {
  final String normalized = token?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

DeviceTokenRefreshAction resolveDeviceTokenRefreshAction({
  required String? storedToken,
  required String? currentToken,
}) {
  final String? stored = _normalizedToken(storedToken);
  final String? current = _normalizedToken(currentToken);

  if (stored == null && current == null) {
    return DeviceTokenRefreshAction.none;
  }
  if (stored == null) {
    return DeviceTokenRefreshAction.register;
  }
  if (current == null) {
    return DeviceTokenRefreshAction.remove;
  }
  if (stored == current) {
    return DeviceTokenRefreshAction.none;
  }
  return DeviceTokenRefreshAction.update;
}

class DeviceTokenCleanupResult {
  const DeviceTokenCleanupResult({
    required this.remoteAttempted,
    required this.remoteDeleted,
    required this.messagingTokenInvalidated,
    required this.storedTokenDeleted,
  });

  final bool remoteAttempted;
  final bool remoteDeleted;
  final bool messagingTokenInvalidated;
  final bool storedTokenDeleted;

  bool get fullyCleaned =>
      (!remoteAttempted || remoteDeleted) &&
      messagingTokenInvalidated &&
      storedTokenDeleted;
}

typedef DeleteRemoteDeviceToken = Future<int?> Function(String token);
typedef DeleteLocalDeviceToken = Future<void> Function();

Future<DeviceTokenCleanupResult> cleanUpDeviceToken({
  required String? storedToken,
  required DeleteRemoteDeviceToken deleteRemote,
  required DeleteLocalDeviceToken invalidateMessagingToken,
  required DeleteLocalDeviceToken deleteStoredToken,
}) async {
  final String? token = _normalizedToken(storedToken);
  final bool remoteAttempted = token != null;
  bool remoteDeleted = false;
  bool messagingTokenInvalidated = false;
  bool storedTokenDeleted = false;

  if (token != null) {
    try {
      final int? status = await deleteRemote(token);
      remoteDeleted =
          status == 404 || (status != null && status >= 200 && status < 300);
    } catch (_) {
      remoteDeleted = false;
    }
  }

  try {
    await invalidateMessagingToken();
    messagingTokenInvalidated = true;
  } catch (_) {
    messagingTokenInvalidated = false;
  }

  try {
    await deleteStoredToken();
    storedTokenDeleted = true;
  } catch (_) {
    storedTokenDeleted = false;
  }

  return DeviceTokenCleanupResult(
    remoteAttempted: remoteAttempted,
    remoteDeleted: remoteDeleted,
    messagingTokenInvalidated: messagingTokenInvalidated,
    storedTokenDeleted: storedTokenDeleted,
  );
}
