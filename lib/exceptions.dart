/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */


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