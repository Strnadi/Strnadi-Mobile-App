import 'dart:async';
import 'dart:convert';

String? _normalizeDeviceToken(String? token) {
  final String normalized = token?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

class DeviceRegistrationScope {
  DeviceRegistrationScope({
    required String sessionId,
    required String accessToken,
    required this.userId,
    required String subject,
    required String environment,
    required String apiHost,
  })  : sessionId = sessionId.trim(),
        accessToken = accessToken.trim(),
        subject = subject.trim(),
        environment = environment.trim(),
        apiHost = apiHost.trim() {
    if (this.sessionId.isEmpty ||
        this.accessToken.isEmpty ||
        userId <= 0 ||
        this.subject.isEmpty ||
        this.environment.isEmpty ||
        this.apiHost.isEmpty) {
      throw ArgumentError('A device registration scope must be complete.');
    }
  }

  final String sessionId;
  final String accessToken;
  final int userId;
  final String subject;
  final String environment;
  final String apiHost;
}

class DeviceRegistrationMetadata {
  DeviceRegistrationMetadata({
    required String platform,
    required String model,
  })  : platform = platform.trim(),
        model = model.trim() {
    if (this.platform.isEmpty || this.model.isEmpty) {
      throw ArgumentError('Device registration metadata cannot be empty.');
    }
  }

  final String platform;
  final String model;
}

/// The durable marker proving which logical login owns a registered FCM token.
///
/// The access token is deliberately excluded. A new logical login gets a new
/// session id and therefore cannot update a token registered by an older login,
/// even when both logins belong to the same backend user.
class DeviceTokenBinding {
  DeviceTokenBinding({
    required String token,
    required this.userId,
    required String subject,
    required String sessionId,
    required String environment,
    required String apiHost,
  })  : token = _normalizeDeviceToken(token) ??
            (throw ArgumentError('A device token cannot be empty.')),
        subject = subject.trim(),
        sessionId = sessionId.trim(),
        environment = environment.trim(),
        apiHost = apiHost.trim() {
    if (userId <= 0 ||
        this.subject.isEmpty ||
        this.sessionId.isEmpty ||
        this.environment.isEmpty ||
        this.apiHost.isEmpty) {
      throw ArgumentError('A device-token binding must be complete.');
    }
  }

  final String token;
  final int userId;
  final String subject;
  final String sessionId;
  final String environment;
  final String apiHost;

  factory DeviceTokenBinding.forScope(
    DeviceRegistrationScope scope,
    String token,
  ) {
    return DeviceTokenBinding(
      token: token,
      userId: scope.userId,
      subject: scope.subject,
      sessionId: scope.sessionId,
      environment: scope.environment,
      apiHost: scope.apiHost,
    );
  }

  bool belongsTo(DeviceRegistrationScope scope) {
    return belongsToLogicalSession(scope) &&
        environment == scope.environment &&
        apiHost == scope.apiHost;
  }

  bool belongsToLogicalSession(DeviceRegistrationScope scope) {
    return userId == scope.userId &&
        subject == scope.subject &&
        sessionId == scope.sessionId;
  }

  Map<String, Object> toJson() => <String, Object>{
        'version': 1,
        'token': token,
        'userId': userId,
        'subject': subject,
        'sessionId': sessionId,
        'environment': environment,
        'apiHost': apiHost,
      };

  String encode() => jsonEncode(toJson());

  static DeviceTokenBinding? decode(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final Map<String, dynamic> values = decoded.cast<String, dynamic>();
      if (values['version'] != 1 ||
          values['token'] is! String ||
          values['userId'] is! int ||
          values['subject'] is! String ||
          values['sessionId'] is! String ||
          values['environment'] is! String ||
          values['apiHost'] is! String) {
        return null;
      }
      return DeviceTokenBinding(
        token: values['token'] as String,
        userId: values['userId'] as int,
        subject: values['subject'] as String,
        sessionId: values['sessionId'] as String,
        environment: values['environment'] as String,
        apiHost: values['apiHost'] as String,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

enum DeviceTokenSyncStatus {
  unchanged,
  registered,
  updated,
  noVerifiedSession,
  noCurrentToken,
  sessionChangedBeforeRemote,
  sessionChangedAfterRemote,
  remoteRejected,
  remoteFailed,
  persistenceFailed,
  suppressedAfterCleanup,
}

class DeviceTokenSyncResult {
  const DeviceTokenSyncResult(
    this.status, {
    this.statusCode,
    this.error,
  });

  final DeviceTokenSyncStatus status;
  final int? statusCode;
  final Object? error;

  bool get succeeded =>
      status == DeviceTokenSyncStatus.unchanged ||
      status == DeviceTokenSyncStatus.registered ||
      status == DeviceTokenSyncStatus.updated;
}

typedef CaptureDeviceRegistrationScope = Future<DeviceRegistrationScope?>
    Function();
typedef IsDeviceRegistrationScopeCurrent = Future<bool> Function(
  DeviceRegistrationScope scope,
);
typedef ReadDeviceTokenBinding = Future<String?> Function();
typedef CurrentFirebaseDeviceToken = Future<String?> Function();
typedef LoadDeviceRegistrationMetadata = Future<DeviceRegistrationMetadata>
    Function();
typedef RegisterRemoteDevice = Future<int?> Function(
  DeviceRegistrationScope scope,
  String token,
  DeviceRegistrationMetadata metadata,
);
typedef UpdateRemoteDevice = Future<int?> Function(
  DeviceRegistrationScope scope,
  String oldToken,
  String newToken,
);
typedef PersistDeviceTokenBinding = Future<void> Function(
  DeviceTokenBinding binding,
);
typedef ClearDeviceTokenBindingIfCurrent = Future<void> Function(
  DeviceTokenBinding binding,
);
typedef DeleteBoundRemoteDevice = Future<int?> Function(
  DeviceRegistrationScope scope,
  DeviceTokenBinding binding,
);
typedef InvalidateFirebaseDeviceToken = Future<void> Function();

class DeviceSessionCleanupResult {
  const DeviceSessionCleanupResult({
    required this.remoteAttempted,
    required this.remoteDeleted,
    required this.firebaseTokenInvalidated,
    required this.bindingCleared,
  });

  final bool remoteAttempted;
  final bool remoteDeleted;
  final bool firebaseTokenInvalidated;
  final bool bindingCleared;

  bool get fullyCleaned =>
      (!remoteAttempted || remoteDeleted) &&
      firebaseTokenInvalidated &&
      bindingCleared;
}

bool _successfulDeviceStatus(int? status) {
  return status != null && status >= 200 && status < 300;
}

/// Serializes and session-binds registration and refresh operations.
///
/// Every remote closure receives the captured access token and API host through
/// [DeviceRegistrationScope]. Production must use those captured values rather
/// than reading mutable global auth/config state inside the request.
class DeviceTokenSessionCoordinator {
  DeviceTokenSessionCoordinator({
    required CaptureDeviceRegistrationScope captureScope,
    required IsDeviceRegistrationScopeCurrent isScopeCurrent,
    required ReadDeviceTokenBinding readBinding,
    required CurrentFirebaseDeviceToken getCurrentToken,
    required LoadDeviceRegistrationMetadata loadMetadata,
    required RegisterRemoteDevice registerRemote,
    required UpdateRemoteDevice updateRemote,
    required PersistDeviceTokenBinding persistBinding,
    required ClearDeviceTokenBindingIfCurrent clearBindingIfCurrent,
  })  : _captureScope = captureScope,
        _isScopeCurrent = isScopeCurrent,
        _readBinding = readBinding,
        _getCurrentToken = getCurrentToken,
        _loadMetadata = loadMetadata,
        _registerRemote = registerRemote,
        _updateRemote = updateRemote,
        _persistBinding = persistBinding,
        _clearBindingIfCurrent = clearBindingIfCurrent;

  final CaptureDeviceRegistrationScope _captureScope;
  final IsDeviceRegistrationScopeCurrent _isScopeCurrent;
  final ReadDeviceTokenBinding _readBinding;
  final CurrentFirebaseDeviceToken _getCurrentToken;
  final LoadDeviceRegistrationMetadata _loadMetadata;
  final RegisterRemoteDevice _registerRemote;
  final UpdateRemoteDevice _updateRemote;
  final PersistDeviceTokenBinding _persistBinding;
  final ClearDeviceTokenBindingIfCurrent _clearBindingIfCurrent;

  Future<void> _operationTail = Future<void>.value();
  String? _suppressedSessionId;

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

  Future<DeviceTokenSyncResult> synchronize({
    String? currentTokenOverride,
  }) {
    return _exclusive<DeviceTokenSyncResult>(() async {
      final DeviceRegistrationScope? scope;
      try {
        scope = await _captureScope();
      } catch (error) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.noVerifiedSession,
          error: error,
        );
      }
      if (scope == null) {
        return const DeviceTokenSyncResult(
          DeviceTokenSyncStatus.noVerifiedSession,
        );
      }
      if (_suppressedSessionId == scope.sessionId) {
        return const DeviceTokenSyncResult(
          DeviceTokenSyncStatus.suppressedAfterCleanup,
        );
      }
      // A newly activated logical login is independent from the session whose
      // logout was suppressed.
      _suppressedSessionId = null;

      final String? currentToken;
      try {
        currentToken = _normalizeDeviceToken(
          currentTokenOverride ?? await _getCurrentToken(),
        );
      } catch (error) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.noCurrentToken,
          error: error,
        );
      }
      if (currentToken == null) {
        return const DeviceTokenSyncResult(
          DeviceTokenSyncStatus.noCurrentToken,
        );
      }

      DeviceTokenBinding? existingBinding;
      try {
        existingBinding = DeviceTokenBinding.decode(await _readBinding());
      } catch (_) {
        // An unreadable or corrupt binding is untrusted. Registration is safe:
        // it uses only the freshly captured account, token, host, and session.
        existingBinding = null;
      }

      if (!await _safeIsCurrent(scope)) {
        return const DeviceTokenSyncResult(
          DeviceTokenSyncStatus.sessionChangedBeforeRemote,
        );
      }

      if (existingBinding != null &&
          existingBinding.belongsTo(scope) &&
          existingBinding.token == currentToken) {
        return const DeviceTokenSyncResult(DeviceTokenSyncStatus.unchanged);
      }

      final bool canUpdate =
          existingBinding != null && existingBinding.belongsTo(scope);
      int? statusCode;
      try {
        if (canUpdate) {
          // Revalidate immediately before the mocked/production API boundary.
          if (!await _safeIsCurrent(scope)) {
            return const DeviceTokenSyncResult(
              DeviceTokenSyncStatus.sessionChangedBeforeRemote,
            );
          }
          statusCode = await _updateRemote(
            scope,
            existingBinding.token,
            currentToken,
          );
        } else {
          final DeviceRegistrationMetadata metadata = await _loadMetadata();
          // Device-info reads can be slow, so revalidate after them too.
          if (!await _safeIsCurrent(scope)) {
            return const DeviceTokenSyncResult(
              DeviceTokenSyncStatus.sessionChangedBeforeRemote,
            );
          }
          statusCode = await _registerRemote(scope, currentToken, metadata);
        }
      } catch (error) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.remoteFailed,
          error: error,
        );
      }

      if (!_successfulDeviceStatus(statusCode)) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.remoteRejected,
          statusCode: statusCode,
        );
      }

      // Never let an API response from account A become account B's local
      // marker after a logout, relogin, or environment switch.
      if (!await _safeIsCurrent(scope)) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.sessionChangedAfterRemote,
          statusCode: statusCode,
        );
      }

      final DeviceTokenBinding newBinding =
          DeviceTokenBinding.forScope(scope, currentToken);
      try {
        await _persistBinding(newBinding);
      } catch (error) {
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.persistenceFailed,
          statusCode: statusCode,
          error: error,
        );
      }

      // Auth can still change while secure storage is being written. Remove
      // only the exact stale marker; serialization prevents another device
      // operation from installing a newer marker concurrently.
      if (!await _safeIsCurrent(scope)) {
        try {
          await _clearBindingIfCurrent(newBinding);
        } catch (_) {
          // A stale marker remains scoped to its old logical session and will
          // never be trusted by a future login.
        }
        return DeviceTokenSyncResult(
          DeviceTokenSyncStatus.sessionChangedAfterRemote,
          statusCode: statusCode,
        );
      }

      return DeviceTokenSyncResult(
        canUpdate
            ? DeviceTokenSyncStatus.updated
            : DeviceTokenSyncStatus.registered,
        statusCode: statusCode,
      );
    });
  }

  Future<bool> _safeIsCurrent(DeviceRegistrationScope scope) async {
    try {
      return await _isScopeCurrent(scope);
    } catch (_) {
      return false;
    }
  }

  /// Serializes logout cleanup with registration and permanently suppresses
  /// further refresh work for the captured logical session.
  ///
  /// The binding retains its original API host, so an environment switch can
  /// still remove the old registration after the global host has changed.
  Future<DeviceSessionCleanupResult> cleanUpCurrentSession({
    required DeleteBoundRemoteDevice deleteRemote,
    required InvalidateFirebaseDeviceToken invalidateFirebaseToken,
    required InvalidateFirebaseDeviceToken clearUnboundLocalToken,
  }) {
    return _exclusive<DeviceSessionCleanupResult>(() async {
      DeviceRegistrationScope? scope;
      try {
        scope = await _captureScope();
      } catch (_) {
        scope = null;
      }
      if (scope != null) {
        _suppressedSessionId = scope.sessionId;
      }

      DeviceTokenBinding? binding;
      try {
        binding = DeviceTokenBinding.decode(await _readBinding());
      } catch (_) {
        binding = null;
      }

      final bool remoteAttempted = scope != null &&
          binding != null &&
          binding.belongsToLogicalSession(scope);
      bool remoteDeleted = false;
      if (remoteAttempted) {
        try {
          final int? status = await deleteRemote(scope, binding);
          remoteDeleted = status == 404 || _successfulDeviceStatus(status);
        } catch (_) {
          remoteDeleted = false;
        }
      }

      bool firebaseTokenInvalidated = false;
      try {
        await invalidateFirebaseToken();
        firebaseTokenInvalidated = true;
      } catch (_) {
        firebaseTokenInvalidated = false;
      }

      bool bindingCleared = false;
      if (binding != null) {
        try {
          await _clearBindingIfCurrent(binding);
          bindingCleared = true;
        } catch (_) {
          bindingCleared = false;
        }
      } else {
        try {
          await clearUnboundLocalToken();
          bindingCleared = true;
        } catch (_) {
          bindingCleared = false;
        }
      }

      return DeviceSessionCleanupResult(
        remoteAttempted: remoteAttempted,
        remoteDeleted: remoteDeleted,
        firebaseTokenInvalidated: firebaseTokenInvalidated,
        bindingCleared: bindingCleared,
      );
    });
  }
}
