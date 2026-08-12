import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

abstract interface class AuthSessionKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureStorageAuthSessionKeyValueStore
    implements AuthSessionKeyValueStore {
  const SecureStorageAuthSessionKeyValueStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ActivatedAuthSessionException implements Exception {
  const ActivatedAuthSessionException(this.message);

  final String message;

  @override
  String toString() => 'ActivatedAuthSessionException: $message';
}

class AuthSessionTransition {
  const AuthSessionTransition._({
    required this.accessToken,
    required this.subject,
    required this.transitionId,
  });

  final String accessToken;
  final String subject;
  final String transitionId;
}

class ActivatedAuthSessionSnapshot {
  const ActivatedAuthSessionSnapshot({
    required this.accessToken,
    required this.userId,
    required this.subject,
    required this.sessionId,
    required this.verified,
  });

  final String accessToken;
  final String userId;
  final String subject;

  /// An opaque logical-login identifier. Callers must compare it for equality
  /// and must not derive account data from it.
  final String sessionId;
  final bool verified;
}

enum OfflineActivatedSessionStatus {
  loggedIn,
  notVerified,
  loggedOut,
}

enum JwtVerificationDisposition {
  verified,
  notVerified,
  rejected,
}

/// Maps backend JWT verification responses to the only two activatable states.
///
/// Redirects, missing statuses, authentication errors, and server failures all
/// reject the pending credential instead of falling through as verified.
JwtVerificationDisposition classifyJwtVerificationStatus(int? statusCode) {
  switch (statusCode) {
    case 200:
      return JwtVerificationDisposition.verified;
    case 403:
      return JwtVerificationDisposition.notVerified;
    default:
      return JwtVerificationDisposition.rejected;
  }
}

/// Evaluates offline restoration without trusting independent credential keys.
///
/// A legacy token/user-id pair without an activated snapshot deliberately
/// cannot restore offline because its account binding was never committed.
OfflineActivatedSessionStatus evaluateOfflineActivatedSession({
  required ActivatedAuthSessionSnapshot? snapshot,
  required String? storedAccessToken,
  required DateTime? expiresAt,
  required DateTime now,
}) {
  if (snapshot == null ||
      storedAccessToken != snapshot.accessToken ||
      expiresAt == null ||
      !expiresAt.isAfter(now)) {
    return OfflineActivatedSessionStatus.loggedOut;
  }
  return snapshot.verified
      ? OfflineActivatedSessionStatus.loggedIn
      : OfflineActivatedSessionStatus.notVerified;
}

typedef AuthSessionIdFactory = String Function(int monotonicGeneration);
typedef AuthSessionSubjectDecoder = String? Function(String accessToken);

String? decodeAuthSessionJwtSubject(String accessToken) {
  try {
    final dynamic subject = JwtDecoder.decode(accessToken)['sub'];
    if (subject is! String || subject.trim().isEmpty) return null;
    return subject.trim();
  } catch (_) {
    return null;
  }
}

String _randomOpaqueId(String prefix, int monotonicGeneration) {
  final Random random = Random.secure();
  final String entropy = base64Url
      .encode(List<int>.generate(18, (_) => random.nextInt(256)))
      .replaceAll('=', '');
  final String orderedGeneration =
      monotonicGeneration.toRadixString(36).padLeft(13, '0');
  return '$prefix-$orderedGeneration-$entropy';
}

/// Owns the two-phase transition between authentication credentials.
///
/// A new token is never considered an upload-capable login merely because the
/// independent `token` and `userId` keys happen to be populated. The final
/// marker is written last and binds the exact token, positive user id, JWT
/// subject, and a monotonically generated opaque logical-session id.
class ActivatedAuthSessionManager {
  ActivatedAuthSessionManager({
    required AuthSessionKeyValueStore store,
    AuthSessionSubjectDecoder subjectDecoder = decodeAuthSessionJwtSubject,
    AuthSessionIdFactory? sessionIdFactory,
    String Function()? transitionIdFactory,
  })  : _store = store,
        _subjectDecoder = subjectDecoder,
        _sessionIdFactory = sessionIdFactory ??
            ((generation) => _randomOpaqueId('s', generation)),
        _transitionIdFactory =
            transitionIdFactory ?? (() => _randomOpaqueId('t', 0));

  static const String tokenKey = 'token';
  static const String userIdKey = 'userId';
  static const String verifiedKey = 'verified';
  static const String activatedMarkerKey = 'activatedAuthSession';
  static const String pendingTransitionKey = 'pendingAuthTransition';
  static const String monotonicGenerationKey = 'authSessionGeneration';

  final AuthSessionKeyValueStore _store;
  final AuthSessionSubjectDecoder _subjectDecoder;
  final AuthSessionIdFactory _sessionIdFactory;
  final String Function() _transitionIdFactory;

  Future<void> _operationTail = Future<void>.value();

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final Completer<void> release = Completer<void>();
    final Future<void> previous = _operationTail;
    _operationTail = release.future;
    return (() async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
      }
    })();
  }

  /// Starts replacement of the current credential.
  ///
  /// Invalidation intentionally happens before the new token write. Any torn
  /// transition therefore has no activated marker and no stale user id.
  Future<AuthSessionTransition> beginTokenTransition(
    String accessToken,
  ) {
    return _exclusive<AuthSessionTransition>(() async {
      final String token = accessToken.trim();
      if (token.isEmpty) {
        throw const ActivatedAuthSessionException(
          'Cannot start a session with an empty token.',
        );
      }

      await _store.delete(activatedMarkerKey);
      await _store.delete(userIdKey);
      await _store.delete(verifiedKey);
      await _store.delete(pendingTransitionKey);

      final String? subject = _subjectDecoder(token);
      if (subject == null || subject.trim().isEmpty) {
        throw const ActivatedAuthSessionException(
          'The new token has no valid subject.',
        );
      }

      await _store.write(tokenKey, token);
      final String transitionId = _transitionIdFactory().trim();
      if (transitionId.isEmpty) {
        throw const ActivatedAuthSessionException(
          'The transition id factory returned an empty id.',
        );
      }
      await _store.write(pendingTransitionKey, transitionId);
      return AuthSessionTransition._(
        accessToken: token,
        subject: subject.trim(),
        transitionId: transitionId,
      );
    });
  }

  /// Activates a transition only after the backend returned a positive user id.
  Future<ActivatedAuthSessionSnapshot> activate(
    AuthSessionTransition transition,
    int userId, {
    required bool verified,
  }) {
    return _exclusive<ActivatedAuthSessionSnapshot>(
      () => _activateUnlocked(
        transition,
        userId,
        verified: verified,
      ),
    );
  }

  /// Activates an already stored token after its owner was freshly resolved.
  ///
  /// This is used to migrate legacy installs and to restore a currently valid
  /// login. A matching activated marker is returned unchanged; otherwise the
  /// old user id and marker are invalidated before the fetched id is committed.
  Future<ActivatedAuthSessionSnapshot> activateCurrentToken(
    int fetchedUserId, {
    required bool verified,
  }) {
    return _exclusive<ActivatedAuthSessionSnapshot>(() async {
      if (fetchedUserId <= 0) {
        throw const ActivatedAuthSessionException(
          'A session requires a positive user id.',
        );
      }

      final ActivatedAuthSessionSnapshot? existing = await _captureUnlocked();
      if (existing != null &&
          existing.userId == fetchedUserId.toString() &&
          existing.verified == verified) {
        return existing;
      }

      final String? storedToken = await _store.read(tokenKey);
      final String token = storedToken?.trim() ?? '';
      final String? subject = token.isEmpty ? null : _subjectDecoder(token);

      await _store.delete(activatedMarkerKey);
      await _store.delete(userIdKey);
      await _store.delete(verifiedKey);
      await _store.delete(pendingTransitionKey);

      if (token.isEmpty || subject == null || subject.trim().isEmpty) {
        throw const ActivatedAuthSessionException(
          'The stored token cannot be activated.',
        );
      }

      final String transitionId = _transitionIdFactory().trim();
      if (transitionId.isEmpty) {
        throw const ActivatedAuthSessionException(
          'The transition id factory returned an empty id.',
        );
      }
      await _store.write(pendingTransitionKey, transitionId);
      return _activateUnlocked(
        AuthSessionTransition._(
          accessToken: token,
          subject: subject.trim(),
          transitionId: transitionId,
        ),
        fetchedUserId,
        verified: verified,
      );
    });
  }

  Future<ActivatedAuthSessionSnapshot> _activateUnlocked(
    AuthSessionTransition transition,
    int userId, {
    required bool verified,
  }) async {
    if (userId <= 0) {
      throw const ActivatedAuthSessionException(
        'A session requires a positive user id.',
      );
    }

    final String? currentToken = await _store.read(tokenKey);
    final String? pendingTransition = await _store.read(pendingTransitionKey);
    if (currentToken != transition.accessToken ||
        pendingTransition != transition.transitionId ||
        _subjectDecoder(transition.accessToken) != transition.subject) {
      throw const ActivatedAuthSessionException(
        'Authentication changed before the session could be activated.',
      );
    }

    final int previousGeneration =
        int.tryParse(await _store.read(monotonicGenerationKey) ?? '') ?? 0;
    if (previousGeneration < 0 || previousGeneration == 0x7fffffffffffffff) {
      throw const ActivatedAuthSessionException(
        'The logical-session generation is invalid.',
      );
    }
    final int generation = previousGeneration + 1;
    final String sessionId = _sessionIdFactory(generation).trim();
    if (sessionId.isEmpty) {
      throw const ActivatedAuthSessionException(
        'The session id factory returned an empty id.',
      );
    }

    final ActivatedAuthSessionSnapshot snapshot = ActivatedAuthSessionSnapshot(
      accessToken: transition.accessToken,
      userId: userId.toString(),
      subject: transition.subject,
      sessionId: sessionId,
      verified: verified,
    );
    final String marker = jsonEncode(<String, Object>{
      'version': 1,
      'generation': generation,
      'sessionId': snapshot.sessionId,
      'accessToken': snapshot.accessToken,
      'userId': snapshot.userId,
      'subject': snapshot.subject,
      'verified': snapshot.verified,
    });

    await _store.write(monotonicGenerationKey, generation.toString());
    await _store.write(userIdKey, snapshot.userId);
    await _store.write(verifiedKey, snapshot.verified.toString());
    await _store.delete(pendingTransitionKey);
    // This is deliberately the final operation. Once this single marker is
    // visible, activate() cannot subsequently report a failed commit.
    await _store.write(activatedMarkerKey, marker);
    return snapshot;
  }

  Future<ActivatedAuthSessionSnapshot?> capture() => _captureUnlocked();

  Future<ActivatedAuthSessionSnapshot?> _captureUnlocked() async {
    final String? firstMarker = await _store.read(activatedMarkerKey);
    if (firstMarker == null || firstMarker.trim().isEmpty) return null;

    final String? token = await _store.read(tokenKey);
    final String? userId = await _store.read(userIdKey);
    final String? verified = await _store.read(verifiedKey);
    final String? pendingTransition = await _store.read(pendingTransitionKey);
    final int? persistedGeneration =
        int.tryParse(await _store.read(monotonicGenerationKey) ?? '');
    final String? secondMarker = await _store.read(activatedMarkerKey);
    if (firstMarker != secondMarker || pendingTransition != null) return null;

    try {
      final dynamic decoded = jsonDecode(firstMarker);
      if (decoded is! Map) return null;
      final Map<String, dynamic> marker = decoded.cast<String, dynamic>();
      final int? version = marker['version'] as int?;
      final int? generation = marker['generation'] as int?;
      final String? markerToken = marker['accessToken'] as String?;
      final String? markerUserId = marker['userId'] as String?;
      final String? markerSubject = marker['subject'] as String?;
      final String? sessionId = marker['sessionId'] as String?;
      final bool? markerVerified = marker['verified'] as bool?;
      final String normalizedMarkerUserId = markerUserId?.trim() ?? '';
      final int? numericUserId = int.tryParse(normalizedMarkerUserId);
      if (version != 1 ||
          generation == null ||
          generation <= 0 ||
          persistedGeneration != generation ||
          numericUserId == null ||
          numericUserId <= 0 ||
          markerToken == null ||
          markerToken.isEmpty ||
          markerSubject == null ||
          markerSubject.trim().isEmpty ||
          sessionId == null ||
          sessionId.trim().isEmpty ||
          markerVerified == null ||
          token != markerToken ||
          userId?.trim() != normalizedMarkerUserId ||
          verified != markerVerified.toString() ||
          _subjectDecoder(markerToken) != markerSubject) {
        return null;
      }
      return ActivatedAuthSessionSnapshot(
        accessToken: markerToken,
        userId: normalizedMarkerUserId,
        subject: markerSubject,
        sessionId: sessionId,
        verified: markerVerified,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<bool> isCurrent(ActivatedAuthSessionSnapshot snapshot) async {
    final ActivatedAuthSessionSnapshot? current = await capture();
    return current != null &&
        current.sessionId == snapshot.sessionId &&
        current.accessToken == snapshot.accessToken &&
        current.userId == snapshot.userId &&
        current.subject == snapshot.subject &&
        current.verified == snapshot.verified;
  }

  /// Invalidates upload-capable authentication before optionally removing the
  /// token itself.
  Future<void> invalidate({bool deleteToken = true}) {
    return _exclusive<void>(() async {
      await _store.delete(activatedMarkerKey);
      await _store.delete(userIdKey);
      await _store.delete(verifiedKey);
      await _store.delete(pendingTransitionKey);
      if (deleteToken) {
        await _store.delete(tokenKey);
      }
    });
  }

  /// Clears application secure storage without allowing logical-session ids to
  /// be reused after logout.
  Future<void> clearAllPreservingGeneration(
    Future<void> Function() clearAll,
  ) {
    return _exclusive<void>(() async {
      final String? generation = await _store.read(monotonicGenerationKey);
      await _store.delete(activatedMarkerKey);
      await _store.delete(userIdKey);
      await _store.delete(verifiedKey);
      await _store.delete(pendingTransitionKey);
      try {
        await clearAll();
      } finally {
        final int? parsed = int.tryParse(generation ?? '');
        if (parsed != null && parsed > 0) {
          await _store.write(monotonicGenerationKey, parsed.toString());
        }
      }
    });
  }
}

final ActivatedAuthSessionManager activatedAuthSessions =
    ActivatedAuthSessionManager(
  store: const SecureStorageAuthSessionKeyValueStore(),
);
