import 'package:flutter/services.dart';

const _sessionKeys = <String>[
  'activatedAuthSession',
  'pendingAuthTransition',
  'token',
  'userId',
  'verified',
  'role',
  'firstName',
  'lastName',
  'lastname',
  'nick',
  'user',
];

const _knownKeys = <String>{
  ..._sessionKeys,
  'authSessionGeneration',
  'fcmToken',
  'fcmTokenBinding',
  'language',
  'tracking_authorization_status',
};

bool isUndecryptableSecureStorageValue(Object error) {
  if (error is! PlatformException) return false;
  final description = '${error.code} ${error.message} ${error.details}';
  return description.contains('BadPaddingException') ||
      description.contains('BAD_DECRYPT');
}

/// Run once, before starting UI, notification registration or background jobs.
///
/// Remove only known unreadable values and invalidate authentication as a
/// unit. Readable preferences, notification bindings, SQLite and audio files
/// remain intact. Never run this recovery in the middle of a recording.
Future<bool> recoverUndecryptableCredentials({
  required Future<String?> Function(String key) read,
  required Future<void> Function(String key) delete,
}) async {
  final corruptKeys = <String>{};
  for (final key in _knownKeys) {
    try {
      await read(key);
    } catch (error) {
      if (!isUndecryptableSecureStorageValue(error)) rethrow;
      corruptKeys.add(key);
    }
  }
  if (corruptKeys.isEmpty) return false;

  // Remove activation first: a failed or interrupted cleanup cannot restore
  // an authenticated session from a partly repaired set of credentials.
  for (final key in <String>{..._sessionKeys, ...corruptKeys}) {
    await delete(key);
  }
  return true;
}
