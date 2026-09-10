/// Preserves legacy integer identities and GUID identities as distinct values.
/// Never derives an identity from an email or converts a GUID to an integer.
Object? parseUserId(Object? value) {
  if (value is int) return value > 0 ? value : null;
  if (value is! String) return null;
  final text = value.trim();
  final number = int.tryParse(text);
  if (number != null) return number > 0 ? number : null;
  return RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
          .hasMatch(text)
      ? text.toLowerCase()
      : null;
}

Object requireUserId(Object? value) =>
    parseUserId(value) ?? (throw StateError('Invalid account identity.'));
