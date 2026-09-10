enum HostEnvironment {
  prod,
  dev,
  preprod;

  bool get isNonProduction => this != prod;

  String get labelKey => switch (this) {
        prod => 'user.settings.environment.production',
        dev => 'user.settings.environment.development',
        preprod => 'user.settings.environment.preprod',
      };

  String get badgeKey => switch (this) {
        prod => 'user.settings.environment.production',
        dev => 'user.settings.environment.devBadge',
        preprod => 'user.settings.environment.preprodBadge',
      };

  static HostEnvironment fromPreference(String? value) =>
      HostEnvironment.values.firstWhere(
        (environment) =>
            environment.toString() == value || environment.name == value,
        orElse: () => prod,
      );
}

/// Preserve the existing prod/dev behavior, but never fall back from preprod
/// to production. Values are hostnames, not URLs (callers use Uri.https).
String resolveApiHost(
    HostEnvironment environment, Map<String, dynamic> config) {
  switch (environment) {
    case HostEnvironment.prod:
      return config['host'] as String;
    case HostEnvironment.dev:
      final devHost = config['devhost'] as String?;
      return devHost != null && devHost.isNotEmpty
          ? devHost
          : config['host'] as String;
    case HostEnvironment.preprod:
      final host = config['preprodhost'];
      final hostname = RegExp(
        r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
      );
      if (host is! String || host.length > 253 || !hostname.hasMatch(host)) {
        throw StateError('Preprod API hostname is missing or invalid.');
      }
      if (host.toLowerCase() == 'api.strnadi.cz' ||
          host.toLowerCase() == (config['host'] as String?)?.toLowerCase()) {
        throw StateError('Preprod API must not use the production hostname.');
      }
      return host;
  }
}
