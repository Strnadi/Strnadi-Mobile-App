import 'dart:convert';

class CachedUserProfile {
  const CachedUserProfile({
    required this.firstName,
    required this.lastName,
    required this.nickname,
    required this.role,
  });

  final String firstName;
  final String lastName;
  final String? nickname;
  final String? role;
}

CachedUserProfile? parseCachedUserProfile(Object? payload) {
  Object? decoded = payload;
  if (payload is String) {
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) return null;

  final Object? firstName = decoded['firstName'];
  final Object? lastName = decoded['lastName'];
  final Object? nickname = decoded['nickname'];
  final Object? role = decoded['role'];
  if (firstName is! String ||
      lastName is! String ||
      (nickname != null && nickname is! String) ||
      (role != null && role is! String)) {
    return null;
  }

  return CachedUserProfile(
    firstName: firstName,
    lastName: lastName,
    nickname: nickname as String?,
    role: role as String?,
  );
}
