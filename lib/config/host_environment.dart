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

/// Parse a complete API base URL; retain legacy hostname configuration.
Uri apiBaseUri(String value) {
  final fullUrl = value.contains('://');
  final uri = Uri.tryParse(fullUrl ? value : 'https://$value');
  final hostname = RegExp(
    r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
  );
  if (value.trim() != value ||
      uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      !hostname.hasMatch(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (!fullUrl && !hostname.hasMatch(value))) {
    throw StateError('API base URL is missing or invalid.');
  }
  return uri;
}

/// Join endpoint paths without discarding the configured base path.
Uri apiEndpointUri(String base, String path) {
  final uri = apiBaseUri(base);
  final prefix = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final endpoint = path.replaceFirst(RegExp(r'^/+'), '');
  return uri.replace(path: '$prefix/$endpoint');
}

/// Never fall back from preprod to production.
String resolveApiHost(
  HostEnvironment environment,
  Map<String, dynamic> config,
) {
  final value = switch (environment) {
    HostEnvironment.prod => config['host'],
    HostEnvironment.dev =>
      config['devhost'] == null || config['devhost'] == ''
          ? config['host']
          : config['devhost'],
    HostEnvironment.preprod => config['preprodhost'],
  };
  if (value is! String) throw StateError('API base URL is missing.');
  final uri = apiBaseUri(value);
  if (environment == HostEnvironment.preprod &&
      (uri.host == 'api.strnadi.cz' ||
          uri.host == apiBaseUri(config['host'] as String).host)) {
    throw StateError('Preprod API must not use the production hostname.');
  }
  return value;
}
