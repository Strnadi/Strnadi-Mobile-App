

class FetchException implements Exception {
  final String message;
  final int statusCode;

  FetchException(this.message, this.statusCode);
}

class UploadException implements Exception {
  final String message;
  final int statusCode;

  UploadException(this.message, this.statusCode);
}

class UnreadyException implements Exception {
  final String message;

  UnreadyException(this.message);
}

class InvalidPartException implements Exception {
  final String message;
  final int id;

  InvalidPartException(this.message, this.id);
}

class LocationException implements Exception {
  final String message;
  final bool permission;
  final bool enabled;
  final bool? falledBack;

  LocationException(this.message, this.permission, this.enabled, this.falledBack);
}

class NotImplementedException implements Exception {
}
/*
class PermissionException implements Exception {
  final String message;
  final String permission;

  PermissionException(this.message, this.permission);
}
*/