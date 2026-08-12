Uri? configuredBackendHttpsOrigin(String configuredHost) {
  final Uri? origin = Uri.tryParse('https://${configuredHost.trim()}');
  if (origin == null ||
      origin.host.isEmpty ||
      origin.path.isNotEmpty && origin.path != '/' ||
      origin.hasQuery ||
      origin.hasFragment ||
      origin.userInfo.isNotEmpty) {
    return null;
  }
  return origin;
}

bool targetsConfiguredBackendHost(Uri candidate, String configuredHost) {
  final Uri? origin = configuredBackendHttpsOrigin(configuredHost);
  return origin != null &&
      candidate.host.toLowerCase() == origin.host.toLowerCase();
}

bool isApprovedProtectedMarkdownOrigin(
  Uri candidate,
  String configuredHost,
) {
  final Uri? origin = configuredBackendHttpsOrigin(configuredHost);
  if (origin == null) return false;

  return candidate.scheme.toLowerCase() == 'https' &&
      candidate.userInfo.isEmpty &&
      candidate.host.toLowerCase() == origin.host.toLowerCase() &&
      candidate.port == origin.port;
}
