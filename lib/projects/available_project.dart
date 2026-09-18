import 'package:strnadi/config/oauth_configuration.dart';

/// Administration's project discovery response. Website URLs are never used
/// as API destinations; a missing/invalid API URL makes the project unavailable.
class AvailableProject {
  const AvailableProject({
    required this.id,
    required this.name,
    this.apiDomain,
  });
  final String id;
  final String name;
  final String? apiDomain;

  factory AvailableProject.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty) {
      throw const FormatException('Invalid project discovery response');
    }
    return AvailableProject(
      id: id.toLowerCase(),
      name: name,
      apiDomain: json['apiDomain'] is String
          ? json['apiDomain'] as String
          : null,
    );
  }

  Uri? get apiOrigin {
    final uri = Uri.tryParse(apiDomain ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }
    return uri;
  }

  OAuthConfiguration configuration(OAuthConfiguration current) =>
      OAuthConfiguration(
        environment: current.environment,
        issuer: current.issuer,
        tenantOrigin:
            apiOrigin ?? (throw StateError('Project API unavailable')),
        projectId: id,
        scopes: current.scopes,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiDomain': apiDomain,
  };
}
