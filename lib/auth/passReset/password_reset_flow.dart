import 'package:jwt_decoder/jwt_decoder.dart';

String? passwordResetEmailFromToken(String token) {
  final String normalizedToken = token.trim();
  if (normalizedToken.isEmpty) return null;

  try {
    final Object? subject = JwtDecoder.decode(normalizedToken)['sub'];
    if (subject is! String) return null;
    final String email = subject.trim();
    return email.isEmpty ? null : email;
  } catch (_) {
    return null;
  }
}
