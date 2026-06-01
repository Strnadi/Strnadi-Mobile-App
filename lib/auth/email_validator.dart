class EmailValidator {
  static final RegExp _emailPattern = RegExp(
    r"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)+$",
    caseSensitive: false,
  );

  static String normalize(String email) {
    return email.trim().toLowerCase();
  }

  static bool isValid(String email) {
    final String normalized = normalize(email);
    return normalized.isNotEmpty && _emailPattern.hasMatch(normalized);
  }
}
