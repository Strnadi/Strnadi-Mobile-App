import 'package:strnadi/auth/user_identity.dart';

/// Adapts only the authenticated caller's profile. A mismatched response must
/// never replace cached metadata for the current account.
Map<String, dynamic> normalizeAdministrationProfile(
  Object? payload, {
  required Object expectedUserId,
}) {
  if (parseUserId(expectedUserId) == null ||
      payload is! Map ||
      parseUserId(payload['id']) != parseUserId(expectedUserId) ||
      payload['firstName'] is! String ||
      payload['lastName'] is! String ||
      (payload['userName'] != null && payload['userName'] is! String) ||
      (payload['email'] != null && payload['email'] is! String) ||
      payload['roles'] is! List ||
      (payload['roles'] as List).any((role) => role is! String)) {
    throw const FormatException('Invalid Administration profile response.');
  }
  final roles = payload['roles'] as List;
  return <String, dynamic>{
    ...payload.cast<String, dynamic>(),
    'nickname': payload['userName'],
    // Existing UI has one role slot. Only explicit project roles enable controls.
    'role': roles.contains('admin')
        ? 'admin'
        : roles.contains('tester')
            ? 'tester'
            : roles.contains('user')
                ? 'user'
                : null,
  };
}

Map<String, dynamic> administrationProfilePatch(Map<String, dynamic> body) => {
      'userName': body['nickname'],
      'firstName': body['firstName'] ?? '',
      'lastName': body['lastName'] ?? '',
      'city': body['city'],
      'postCode': body['postCode'],
    };
