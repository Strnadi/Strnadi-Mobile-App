import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:strnadi/auth/activated_auth_session.dart';

import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'pkce_attempt.dart';

typedef AuthenticationBrowser = Future<String> Function(Uri authorizeUri);

class ProjectCredential {
  const ProjectCredential({
    required this.accessToken,
    required this.subject,
    required this.expiresAt,
    required this.scopeKey,
  });
  final String accessToken;
  final String subject;
  final DateTime expiresAt;
  final String scopeKey;
}

/// Owns one environment/issuer/project session. Changing scope requires a new
/// instance and closing the old one. Tokens never use the legacy `token` key.
class AdministrationSession {
  AdministrationSession({
    required this.configuration,
    required this.transport,
    required this.store,
    required this.browser,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final OAuthConfiguration configuration;
  final OAuthApi transport;
  final AuthSessionKeyValueStore store;
  final AuthenticationBrowser browser;
  final DateTime Function() _now;
  _Tokens? _tokens;
  PkceAttempt? _attempt;
  int _generation = 0;
  bool _closed = false;
  Future<ProjectCredential>? _renewal;
  Future<void> _writes = Future.value();

  String get storageKey =>
      'administration.session.v1.${sha256.convert(utf8.encode(configuration.scopeKey))}';

  void _check(int generation) {
    if (_closed || generation != _generation) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final previous = _writes;
    final done = Completer<void>();
    _writes = done.future;
    return (() async {
      await previous;
      try {
        return await operation();
      } finally {
        done.complete();
      }
    })();
  }

  Future<void> _save(_Tokens tokens, int generation) => _serialize(() async {
        _check(generation);
        await store.write(storageKey, jsonEncode(tokens.toJson()));
        _check(generation);
        _tokens = tokens;
      });

  Future<ProjectCredential> signIn() async {
    if (_closed) throw const OAuthFailure(OAuthFailureKind.staleSession);
    if (_attempt != null || _renewal != null) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    final generation = ++_generation;
    final attempt = PkceAttempt.create();
    _attempt = attempt;
    try {
      // A rejected account switch must not fall back to the previous account.
      _tokens = null;
      await _serialize(() async {
        _check(generation);
        await store.delete(storageKey);
      });
      _check(generation);
      final callback = await browser(attempt.authorizationUri(configuration));
      _check(generation);
      final code = attempt.consumeCallback(callback);
      final result = await transport.exchangeAuthorizationCode(configuration,
          code: code, verifier: attempt.verifier);
      _check(generation);
      final admin = _parseAdmin(result);
      final tokens = _Tokens(admin.token, admin.expiry,
          _requiredString(result, 'refresh_token'), null);
      // The account binding is established from the returned project token;
      // an Administration access token can be opaque/encrypted.
      final exchanged = await _exchange(tokens, generation);
      await _save(exchanged, generation);
      return exchanged.project!;
    } on OAuthFailure {
      rethrow;
    } catch (_) {
      throw const OAuthFailure(OAuthFailureKind.server);
    } finally {
      attempt.cancel();
      if (identical(_attempt, attempt)) _attempt = null;
    }
  }

  void cancelSignIn() {
    if (_attempt == null) return;
    ++_generation;
    _attempt?.cancel();
    _attempt = null;
  }

  void requireCurrent(ProjectCredential credential) {
    if (_closed ||
        _attempt != null ||
        credential.scopeKey != configuration.scopeKey ||
        !identical(_tokens?.project, credential) ||
        !credential.expiresAt.isAfter(_now())) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
  }

  Future<ProjectCredential> projectCredential({String? expectedSubject}) {
    if (_closed || _attempt != null) {
      return Future.error(const OAuthFailure(OAuthFailureKind.staleSession));
    }
    final existing = _renewal;
    final operation = existing ?? _loadOrRenew(_generation);
    if (existing == null) {
      _renewal = operation;
      operation.then((_) {
        if (identical(_renewal, operation)) _renewal = null;
      }, onError: (Object _, StackTrace __) {
        if (identical(_renewal, operation)) _renewal = null;
      });
    }
    return operation.then((credential) {
      requireCurrent(credential);
      if (expectedSubject != null && credential.subject != expectedSubject) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      return credential;
    });
  }

  Future<String> administrationCredential(
      {required String expectedSubject}) async {
    await projectCredential(expectedSubject: expectedSubject);
    return _tokens!.adminToken;
  }

  Future<ProjectCredential> _loadOrRenew(int generation) async {
    _check(generation);
    var tokens = _tokens;
    if (tokens == null) {
      final saved = await store.read(storageKey);
      _check(generation);
      if (saved == null) {
        throw const OAuthFailure(OAuthFailureKind.loginRequired);
      }
      try {
        tokens = _Tokens.fromJson(jsonDecode(saved), configuration);
      } catch (_) {
        throw const OAuthFailure(OAuthFailureKind.loginRequired);
      }
      _tokens = tokens;
    }
    final threshold = _now().add(const Duration(seconds: 30));
    if (tokens.project?.expiresAt.isAfter(threshold) == true) {
      return tokens.project!;
    }
    try {
      if (!tokens.adminExpiry.isAfter(threshold)) {
        final result = await transport.refreshAdministrationToken(
            configuration, tokens.refreshToken);
        _check(generation);
        final admin = _parseAdmin(result);
        tokens = _Tokens(
          admin.token,
          admin.expiry,
          result.containsKey('refresh_token')
              ? _requiredString(result, 'refresh_token')
              : tokens.refreshToken,
          tokens.project,
        );
        // Persist rotation before exchange: a temporary exchange failure must
        // not leave only the now-invalid previous refresh token on disk.
        await _save(tokens, generation);
      }
      tokens = await _exchange(tokens, generation);
      await _save(tokens, generation);
      return tokens.project!;
    } on OAuthFailure catch (error) {
      if (error.kind == OAuthFailureKind.loginRequired ||
          error.kind == OAuthFailureKind.exchangeDenied) {
        await _serialize(() async {
          _check(generation);
          _tokens = null;
          await store.delete(storageKey);
        });
      }
      rethrow;
    }
  }

  Future<_Tokens> _exchange(_Tokens tokens, int generation) async {
    final result =
        await transport.exchangeProjectToken(configuration, tokens.adminToken);
    _check(generation);
    _requireBearer(result);
    final token = _requiredString(result, 'access_token');
    if (token == tokens.adminToken) {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
    final credential = _project(token, configuration, _now());
    if (tokens.project != null &&
        tokens.project!.subject != credential.subject) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    return _Tokens(
        tokens.adminToken, tokens.adminExpiry, tokens.refreshToken, credential);
  }

  ({String token, DateTime expiry}) _parseAdmin(Map<String, dynamic> result) {
    _requireBearer(result);
    final expiresIn = result['expires_in'];
    if (expiresIn is! int || expiresIn <= 0 || expiresIn > 31536000) {
      throw const OAuthFailure(OAuthFailureKind.invalidResponse);
    }
    return (
      token: _requiredString(result, 'access_token'),
      expiry: _now().add(Duration(seconds: expiresIn)),
    );
  }

  /// Invalidates in-flight browser, refresh and exchange work immediately.
  /// Deletion is serialized after pending writes, so logout always wins.
  Future<void> signOut() {
    ++_generation;
    _attempt?.cancel();
    _attempt = null;
    _tokens = null;
    return _serialize(() => store.delete(storageKey));
  }

  /// Returns whether the browser reached the expected logout callback.
  /// Cancellation is not proof of server-side logout.
  /// Local credentials must already be cleared before opening this page.
  Future<bool> endBrowserSession() async {
    if (!_closed) throw StateError('Close the local session before logout.');
    try {
      final callback = await browser(transport.logoutUri(configuration));
      return callback == OAuthConfiguration.redirectUri;
    } on OAuthFailure {
      // Offline/cancelled browser logout must never restore local credentials.
      return false;
    }
  }

  Future<void> close() {
    _closed = true;
    return signOut();
  }
}

String _requiredString(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is! String || value.trim().isEmpty) {
    throw const OAuthFailure(OAuthFailureKind.invalidResponse);
  }
  return value;
}

void _requireBearer(Map<String, dynamic> result) {
  if (result['token_type'] is! String ||
      (result['token_type'] as String).toLowerCase() != 'bearer') {
    throw const OAuthFailure(OAuthFailureKind.invalidResponse);
  }
}

ProjectCredential _project(
    String token, OAuthConfiguration config, DateTime now) {
  try {
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw const FormatException();
    }
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    final subject = _requiredString(claims, 'sub');
    final audience = claims['aud'];
    final expected = 'project:${config.projectId}';
    final validAudience = audience == expected ||
        (audience is List &&
            audience.length == 1 &&
            audience.single == expected);
    final exp = claims['exp'];
    if (!validAudience ||
        claims['iss'] != config.issuer.toString() ||
        exp is! int ||
        exp <= 0 ||
        exp > 8640000000000) {
      throw const FormatException();
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    if (!expiry.isAfter(now)) throw const FormatException();
    // This is an outbound routing check, not signature verification. Tenant.Api
    // must cryptographically validate issuer, signature, audience and expiry.
    return ProjectCredential(
        accessToken: token,
        subject: subject,
        expiresAt: expiry,
        scopeKey: config.scopeKey);
  } catch (_) {
    throw const OAuthFailure(OAuthFailureKind.invalidResponse);
  }
}

class _Tokens {
  _Tokens(this.adminToken, this.adminExpiry, this.refreshToken, this.project);
  final String adminToken;
  final DateTime adminExpiry;
  final String refreshToken;
  final ProjectCredential? project;

  Map<String, dynamic> toJson() => {
        'adminToken': adminToken,
        'adminExpiry': adminExpiry.toIso8601String(),
        'refreshToken': refreshToken,
        'projectToken': project?.accessToken,
        'scope': project?.scopeKey,
        'subject': project?.subject,
      };

  factory _Tokens.fromJson(dynamic json, OAuthConfiguration config) {
    final data = json as Map<String, dynamic>;
    // Expired project credentials still bind refresh to the original account.
    final project = _project(_requiredString(data, 'projectToken'), config,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    if (data['scope'] != config.scopeKey ||
        data['subject'] != project.subject) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    if (data['adminToken'] == project.accessToken) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    return _Tokens(
        _requiredString(data, 'adminToken'),
        DateTime.parse(_requiredString(data, 'adminExpiry')),
        _requiredString(data, 'refreshToken'),
        project);
  }
}
