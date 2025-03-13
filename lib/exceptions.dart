

class FetchException implements Exception {
  final String message;
  final int statusCode;

  FetchException(this.message, this.statusCode);

  @override
  String toString() {
    return 'FetchException: $message with code $statusCode';
  }
}

class UploadException implements Exception {
  final String message;
  final int statusCode;

  UploadException(this.message, this.statusCode);
  @override
  String toString() {
    return 'UploadException: $message with code $statusCode';
  }
}

class UnreadyException implements Exception {
  final String message;

  UnreadyException(this.message);
  @override
  String toString() {
    return 'UnreadyException: $message';
  }
}

class InvalidPartException implements Exception {
  final String message;
  final int id;

  InvalidPartException(this.message, this.id);
  @override
  String toString() {
    return 'InvalidPartException: $message on Part id $id';
  }
}

class LocationException implements Exception {
  final String message;
  final bool permission;
  final bool enabled;
  final bool? falledBack;

  LocationException(this.message, this.permission, this.enabled, this.falledBack);
  @override
  toString() {
    return 'LocationException: $message, permission: $permission, enabled: $enabled, falledBack: $falledBack';
  }
}