import 'package:strnadi/auth/activated_auth_session.dart';

typedef CaptureActivatedNotificationSession
    = Future<ActivatedAuthSessionSnapshot?> Function();
typedef IsActivatedNotificationSessionCurrent = Future<bool> Function(
    ActivatedAuthSessionSnapshot snapshot);
typedef CurrentNotificationEnvironment = String Function();

/// The immutable account/environment boundary for one notification-cache
/// operation.
///
/// The activated snapshot is retained only so the operation can verify that
/// the same logical login is still current. Persisted rows contain only the
/// backend user id and environment, never the token or logical-session id.
class NotificationCacheScope {
  const NotificationCacheScope._({
    required this.ownerUserId,
    required this.environment,
    required this.activatedSession,
  });

  final String ownerUserId;
  final String environment;
  final ActivatedAuthSessionSnapshot activatedSession;
}

/// Coordinates notification-cache access without depending on SQLite.
///
/// Production supplies the activated-session manager and scoped database
/// closures. Tests can therefore cover account switches and persistence
/// failures using only in-memory fakes.
class NotificationCacheIsolation {
  const NotificationCacheIsolation({
    required CaptureActivatedNotificationSession captureActivatedSession,
    required IsActivatedNotificationSessionCurrent isActivatedSessionCurrent,
    required CurrentNotificationEnvironment currentEnvironment,
  })  : _captureActivatedSession = captureActivatedSession,
        _isActivatedSessionCurrent = isActivatedSessionCurrent,
        _currentEnvironment = currentEnvironment;

  final CaptureActivatedNotificationSession _captureActivatedSession;
  final IsActivatedNotificationSessionCurrent _isActivatedSessionCurrent;
  final CurrentNotificationEnvironment _currentEnvironment;

  Future<NotificationCacheScope?> _captureVerifiedScope() async {
    try {
      final ActivatedAuthSessionSnapshot? session =
          await _captureActivatedSession();
      if (session == null || !session.verified) return null;

      final String ownerUserId = session.userId.trim();
      final int? numericUserId = int.tryParse(ownerUserId);
      final String environment = _currentEnvironment().trim();
      if (numericUserId == null || numericUserId <= 0 || environment.isEmpty) {
        return null;
      }

      return NotificationCacheScope._(
        ownerUserId: ownerUserId,
        environment: environment,
        activatedSession: session,
      );
    } catch (_) {
      // A cache must never turn a missing or unreadable auth lease into an
      // unscoped persistence operation.
      return null;
    }
  }

  Future<bool> _isCurrent(NotificationCacheScope scope) async {
    try {
      if (_currentEnvironment().trim() != scope.environment) return false;
      return await _isActivatedSessionCurrent(scope.activatedSession);
    } catch (_) {
      return false;
    }
  }

  /// Inserts one scoped row.
  ///
  /// If the logical login changes after insertion, [removeInserted] receives
  /// the exact inserted id and original scope. Cleanup failures are contained:
  /// the row remains scoped to its original owner and cannot be read by the
  /// new account.
  Future<bool> persist({
    required Future<int> Function(NotificationCacheScope scope) insert,
    required Future<void> Function(
      NotificationCacheScope scope,
      int insertedId,
    ) removeInserted,
  }) async {
    final NotificationCacheScope? scope = await _captureVerifiedScope();
    if (scope == null || !await _isCurrent(scope)) return false;

    final int insertedId = await insert(scope);
    if (await _isCurrent(scope)) return true;

    try {
      await removeInserted(scope, insertedId);
    } catch (_) {
      // The inserted row is still quarantined by its original owner and
      // environment even when best-effort cleanup fails.
    }
    return false;
  }

  /// Reads rows only while the same verified logical login remains current.
  Future<List<T>> readList<T>({
    required Future<List<T>> Function(NotificationCacheScope scope) read,
  }) async {
    final NotificationCacheScope? scope = await _captureVerifiedScope();
    if (scope == null || !await _isCurrent(scope)) return <T>[];

    final List<T> result = await read(scope);
    if (!await _isCurrent(scope)) return <T>[];
    return result;
  }

  /// Reads a scoped count, returning zero whenever ownership is uncertain.
  Future<int> readCount({
    required Future<int> Function(NotificationCacheScope scope) read,
  }) async {
    final NotificationCacheScope? scope = await _captureVerifiedScope();
    if (scope == null || !await _isCurrent(scope)) return 0;

    final int result = await read(scope);
    if (!await _isCurrent(scope)) return 0;
    return result;
  }

  /// Performs a mutation constrained by the captured owner and environment.
  ///
  /// The callback must include both scope fields in its predicate. Returning
  /// false after a post-mutation account switch prevents callers from treating
  /// a stale operation as current; the scoped predicate ensures it cannot
  /// mutate the newly active account's rows.
  Future<bool> mutate({
    required Future<void> Function(NotificationCacheScope scope) mutation,
  }) async {
    final NotificationCacheScope? scope = await _captureVerifiedScope();
    if (scope == null || !await _isCurrent(scope)) return false;

    await mutation(scope);
    return _isCurrent(scope);
  }
}
