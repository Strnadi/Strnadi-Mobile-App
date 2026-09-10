/// Public, environment-specific OAuth configuration. No client secret belongs
/// in the mobile application.
class OAuthConfiguration {
  OAuthConfiguration({
    required this.environment,
    required this.issuer,
    required this.tenantOrigin,
    required String projectId,
    List<String> scopes = const ['openid', 'offline_access'],
  })  : projectId = projectId.toLowerCase(),
        scopes = List.unmodifiable(scopes) {
    if (!['prod', 'dev', 'preprod'].contains(environment) ||
        !_isHttpsOrigin(issuer) ||
        !_isHttpsOrigin(tenantOrigin) ||
        issuer.origin == tenantOrigin.origin ||
        !RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')
            .hasMatch(this.projectId)) {
      throw ArgumentError('Invalid Administration OAuth configuration.');
    }
  }

  static const clientId = 'strnadi-app';
  static const redirectUri = 'com.delta.strnadi://auth/callback';
  final String environment;
  final Uri issuer;
  final Uri tenantOrigin;
  final String projectId;
  final List<String> scopes;

  Uri get authorizeEndpoint => issuer.resolve('/connect/authorize');
  Uri get logoutEndpoint => issuer.resolve('/connect/logout');
  Uri get tokenEndpoint => issuer.resolve('/connect/token');
  String get scopeKey =>
      '$environment|${issuer.origin}|${tenantOrigin.origin}|$projectId';

  static bool _isHttpsOrigin(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/');
}
