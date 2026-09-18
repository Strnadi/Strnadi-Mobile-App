import 'package:strnadi/config/host_environment.dart';

Uri? configuredBackendHttpsOrigin(String configuredHost) {
  try {
    final value = configuredHost.trim();
    final uri = apiBaseUri(value.contains('://') ? value : 'https://$value');
    return uri.scheme == 'https' ? Uri.parse(uri.origin) : null;
  } on StateError {
    return null;
  }
}

bool targetsConfiguredBackendHost(Uri candidate, String configuredHost) {
  final Uri? origin = configuredBackendHttpsOrigin(configuredHost);
  return origin != null &&
      candidate.host.toLowerCase() == origin.host.toLowerCase();
}

bool isApprovedProtectedMarkdownOrigin(Uri candidate, String configuredHost) {
  final Uri? origin = configuredBackendHttpsOrigin(configuredHost);
  if (origin == null) return false;

  return candidate.scheme.toLowerCase() == 'https' &&
      candidate.userInfo.isEmpty &&
      candidate.host.toLowerCase() == origin.host.toLowerCase() &&
      candidate.port == origin.port;
}
