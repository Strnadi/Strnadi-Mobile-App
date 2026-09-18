import 'package:strnadi/projects/project_diagnostics.dart';
import 'package:strnadi/projects/available_project.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:strnadi/api/debug_auth_logging.dart';
import 'package:strnadi/auth/activated_auth_session.dart';

import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'pkce_attempt.dart';

typedef InitialProjectChooser =
    Future<AvailableProject> Function(
      List<AvailableProject> projects,
      Future<void> Function(AvailableProject) join,
    );

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

  OAuthConfiguration configuration;
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
  Future<void> _credentialTail = Future.value();

  Future<T> _credentialOperation<T>(Future<T> Function() operation) async {
    final previous = _credentialTail;
    final done = Completer<void>();
    _credentialTail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

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

  Future<ProjectCredential> signIn({
    InitialProjectChooser? chooseFirstProject,
    Future<AvailableProject> Function(
      String subject,
      List<AvailableProject> projects,
    )?
    selectProject,
  }) => ProjectDiagnostics.run(ProjectOperation.authorizeProject, () async {
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
      final result = await transport.exchangeAuthorizationCode(
        configuration,
        code: code,
        verifier: attempt.verifier,
      );
      _check(generation);
      final admin = _parseAdmin(result);
      logDebugBrowserToken(kind: 'Administration', token: admin.token);
      final tokens = _Tokens(
        admin.token,
        admin.expiry,
        _requiredString(result, 'refresh_token'),
        null,
      );
      String? discoveredSubject;
      if (selectProject != null) {
        final info = await transport.getAdministration(
          configuration.issuer.resolve('/connect/user-info'),
          admin.token,
        );
        _check(generation);
        final subject = _requiredString(
          Map<String, dynamic>.from(info as Map),
          'sub',
        );
        discoveredSubject = subject;
        var projects = await _availableProjects(admin.token, subject);
        _check(generation);
        if (projects.isEmpty && chooseFirstProject != null) {
          ProjectDiagnostics.event(ProjectEvent.firstProjectRequired);
          final catalog = await transport.projectCatalog(
            configuration,
            admin.token,
          );
          _check(generation);
          final first = await chooseFirstProject(catalog, (project) async {
            _check(generation);
            if (!catalog.any((item) => item.id == project.id)) {
              throw const OAuthFailure(OAuthFailureKind.invalidResponse);
            }
            await _joinProject(admin.token, subject, generation, project);
          });
          _check(generation);
          projects = [first];
          ProjectDiagnostics.event(ProjectEvent.firstProjectChosen);
        }
        _check(generation);
        final selected = await selectProject(subject, projects);
        _check(generation);
        configuration = selected.configuration(configuration);
      }
      // The account binding is established from the returned project token;
      // an Administration access token can be opaque/encrypted.
      final exchanged = await _exchange(tokens, generation);
      if (discoveredSubject != null &&
          exchanged.project!.subject != discoveredSubject) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      logDebugBrowserToken(
        kind: 'project',
        token: exchanged.project!.accessToken,
      );
      await _save(exchanged, generation);
      return exchanged.project!;
    } on OAuthFailure {
      rethrow;
    } on StateError catch (error) {
      if (error.message == 'projects.empty') rethrow;
      throw const OAuthFailure(OAuthFailureKind.server);
    } catch (_) {
      throw const OAuthFailure(OAuthFailureKind.server);
    } finally {
      attempt.cancel();
      if (identical(_attempt, attempt)) _attempt = null;
    }
  });

  /// Discovery and recovery must work even after access to the old project
  /// has been revoked. Refresh Administration independently of project exchange.
  Future<String> discoveryCredential({required String expectedSubject}) =>
      _credentialOperation(() => _discoveryCredential(expectedSubject));

  Future<String> _discoveryCredential(String expectedSubject) async {
    final generation = _generation;
    _check(generation);
    var tokens = _tokens;
    if (tokens == null) {
      final saved = await store.read(storageKey);
      _check(generation);
      if (saved == null) {
        throw const OAuthFailure(OAuthFailureKind.loginRequired);
      }
      tokens = _Tokens.fromJson(jsonDecode(saved), configuration);
    }
    if (tokens.project?.subject != expectedSubject) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    if (!tokens.adminExpiry.isAfter(_now().add(const Duration(seconds: 30)))) {
      final refreshToken = tokens.refreshToken;
      final result = await ProjectDiagnostics.run(
        ProjectOperation.refreshAdministration,
        () => transport.refreshAdministrationToken(configuration, refreshToken),
      );
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
    }
    await _save(tokens, generation);
    return tokens.adminToken;
  }

  Future<List<AvailableProject>> availableProjects(String subject) =>
      ProjectDiagnostics.run(ProjectOperation.discoverMemberships, () async {
        final generation = _generation;
        final token = await discoveryCredential(expectedSubject: subject);
        final result = await _availableProjects(token, subject);
        _check(generation);
        return result;
      });

  // The server's role-based discovery omits role-free self-joins. These IDs
  // are discovery hints only: token exchange remains the access authority.
  String _joinedKey(String subject) {
    final digest = sha256.convert(
      utf8.encode(
        '${configuration.environment}|${configuration.issuer.origin}|$subject',
      ),
    );
    return 'administration.joined.v1.$digest';
  }

  Future<Set<String>> _joinedIds(String subject) async {
    final raw = await store.read(_joinedKey(subject));
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).cast<String>().toSet();
    } catch (error, stackTrace) {
      ProjectDiagnostics.event(ProjectEvent.invalidRememberedJoins);
      ProjectDiagnostics.failure(
        ProjectOperation.discoverMemberships,
        error,
        stackTrace,
      );
      return {};
    }
  }

  Future<List<AvailableProject>> _availableProjects(
    String token,
    String subject,
  ) async {
    final projects = await transport.availableProjects(
      configuration,
      token,
      subject,
    );
    ProjectDiagnostics.event(ProjectEvent.discovered, count: projects.length);
    final remembered = await _joinedIds(subject);
    ProjectDiagnostics.event(
      ProjectEvent.rememberedJoinsLoaded,
      count: remembered.length,
    );
    if (remembered.isEmpty) return projects;
    final catalog = await transport.projectCatalog(configuration, token);
    return {
      for (final p in catalog.where((p) => remembered.contains(p.id))) p.id: p,
      for (final p in projects) p.id: p,
    }.values.toList();
  }

  Future<List<AvailableProject>> projectCatalog(String subject) =>
      ProjectDiagnostics.run(ProjectOperation.discoverCatalog, () async {
        final generation = _generation;
        final token = await discoveryCredential(expectedSubject: subject);
        final projects = await transport.projectCatalog(configuration, token);
        _check(generation);
        ProjectDiagnostics.event(
          ProjectEvent.catalogLoaded,
          count: projects.length,
        );
        return projects;
      });

  Future<void> joinProject(String subject, AvailableProject project) =>
      ProjectDiagnostics.run(ProjectOperation.joinMembership, () async {
        final generation = _generation;
        final token = await discoveryCredential(expectedSubject: subject);
        _check(generation);
        await _joinProject(token, subject, generation, project);
      });

  Future<void> _joinProject(
    String token,
    String subject,
    int generation,
    AvailableProject project,
  ) async {
    await transport.joinProject(
      configuration,
      token,
      subject,
      project,
      requireCurrent: () => _check(generation),
    );
    _check(generation);
    await _serialize(() async {
      _check(generation);
      final joined = (await _joinedIds(subject))..add(project.id);
      _check(generation);
      await store.write(_joinedKey(subject), jsonEncode(joined.toList()));
      _check(generation);
      ProjectDiagnostics.event(
        ProjectEvent.joinRemembered,
        count: joined.length,
      );
    });
  }

  Future<void> validateProjectAccess(String subject) =>
      ProjectDiagnostics.run(ProjectOperation.validateAccess, () async {
        await discoveryCredential(expectedSubject: subject);
        await _credentialOperation(() async {
          final generation = _generation;
          _check(generation);
          final exchanged = await _exchange(_tokens!, generation);
          await _save(exchanged, generation);
        });
      });

  /// Prepare a candidate without closing or replacing the usable old session.
  Future<AdministrationSession> prepareProject(
    AvailableProject project,
    String subject,
  ) => ProjectDiagnostics.run(ProjectOperation.prepareCredential, () async {
    final generation = _generation;
    await discoveryCredential(expectedSubject: subject);
    _check(generation);
    final candidate = AdministrationSession(
      configuration: project.configuration(configuration),
      transport: transport,
      store: store,
      browser: browser,
      now: _now,
    );
    final current = _tokens!;
    final exchanged = await candidate._exchange(
      _Tokens(
        current.adminToken,
        current.adminExpiry,
        current.refreshToken,
        null,
      ),
      0,
    );
    _check(generation);
    if (exchanged.project!.subject != subject) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    await candidate._save(exchanged, 0);
    return candidate;
  });

  /// Stop in-flight work after a successful switch, without revoking the shared
  /// Administration refresh token or deleting another project's credentials.
  void retire() {
    _closed = true;
    ++_generation;
    _attempt?.cancel();
    _attempt = null;
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
    final operation =
        existing ?? _credentialOperation(() => _loadOrRenew(_generation));
    if (existing == null) {
      _renewal = operation;
      operation.then(
        (_) {
          if (identical(_renewal, operation)) _renewal = null;
        },
        onError: (Object _, StackTrace __) {
          if (identical(_renewal, operation)) _renewal = null;
        },
      );
    }
    return operation.then((credential) {
      requireCurrent(credential);
      if (expectedSubject != null && credential.subject != expectedSubject) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      return credential;
    });
  }

  Future<String> administrationCredential({
    required String expectedSubject,
  }) async {
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
    var exchangingProject = false;
    try {
      if (!tokens.adminExpiry.isAfter(threshold)) {
        final refreshToken = tokens.refreshToken;
        final result = await ProjectDiagnostics.run(
          ProjectOperation.refreshAdministration,
          () =>
              transport.refreshAdministrationToken(configuration, refreshToken),
        );
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
      exchangingProject = true;
      tokens = await _exchange(tokens, generation);
      await _save(tokens, generation);
      return tokens.project!;
    } on OAuthFailure catch (error) {
      if (error.kind == OAuthFailureKind.loginRequired ||
          (error.kind == OAuthFailureKind.exchangeDenied &&
              !exchangingProject)) {
        await _serialize(() async {
          _check(generation);
          _tokens = null;
          await store.delete(storageKey);
        });
      }
      rethrow;
    }
  }

  Future<_Tokens> _exchange(_Tokens tokens, int generation) =>
      ProjectDiagnostics.run(ProjectOperation.exchangeCredential, () async {
        final result = await transport.exchangeProjectToken(
          configuration,
          tokens.adminToken,
        );
        _check(generation);
        _requireBearer(result);
        final token = _requiredString(result, 'access_token');
        if (token == tokens.adminToken) {
          throw _invalidResponse(
            'Project exchange returned the Administration token unchanged.',
          );
        }
        final credential = _project(token, configuration, _now());
        if (tokens.project != null &&
            tokens.project!.subject != credential.subject) {
          throw const OAuthFailure(OAuthFailureKind.loginRequired);
        }
        return _Tokens(
          tokens.adminToken,
          tokens.adminExpiry,
          tokens.refreshToken,
          credential,
        );
      });

  ({String token, DateTime expiry}) _parseAdmin(Map<String, dynamic> result) {
    _requireBearer(result);
    final expiresIn = result['expires_in'];
    if (expiresIn is! int || expiresIn <= 0 || expiresIn > 31536000) {
      throw _invalidResponse(
        'Administration expires_in must be an integer between 1 and 31536000.',
      );
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

OAuthFailure _invalidResponse(String reason) {
  if (kDebugMode) debugPrint('[Auth] Invalid OAuth response: $reason');
  return const OAuthFailure(OAuthFailureKind.invalidResponse);
}

String _requiredString(Map<String, dynamic> result, String key) {
  final value = result[key];
  if (value is! String || value.trim().isEmpty) {
    throw _invalidResponse('Missing or empty string field: $key.');
  }
  return value;
}

void _requireBearer(Map<String, dynamic> result) {
  if (result['token_type'] is! String ||
      (result['token_type'] as String).toLowerCase() != 'bearer') {
    throw _invalidResponse('token_type is missing or is not Bearer.');
  }
}

ProjectCredential _project(
  String token,
  OAuthConfiguration config,
  DateTime now,
) {
  try {
    final parts = token.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
      throw _invalidResponse(
        'Project token must have three non-empty JWT segments.',
      );
    }
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    final subject = _requiredString(claims, 'sub');
    final audience = claims['aud'];
    final expected = 'project:${config.projectId}';
    final validAudience =
        audience == expected ||
        (audience is List &&
            audience.every((value) => value is String) &&
            audience.contains(expected));
    final exp = claims['exp'];
    if (!validAudience) {
      throw _invalidResponse(
        'Project audience does not match the configured project.',
      );
    }
    if (claims['iss'] != config.issuer.toString()) {
      throw _invalidResponse(
        'Project issuer does not exactly match the configured issuer (including trailing slash).',
      );
    }
    if (exp is! int || exp <= 0 || exp > 8640000000000) {
      throw _invalidResponse(
        'Project exp must be a positive integer Unix timestamp in seconds.',
      );
    }
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    if (!expiry.isAfter(now)) {
      throw _invalidResponse(
        'Project token is expired according to the device clock.',
      );
    }
    // This is an outbound routing check, not signature verification. Tenant.Api
    // must cryptographically validate issuer, signature, audience and expiry.
    return ProjectCredential(
      accessToken: token,
      subject: subject,
      expiresAt: expiry,
      scopeKey: config.scopeKey,
    );
  } on OAuthFailure {
    rethrow;
  } catch (_) {
    throw _invalidResponse(
      'Project JWT payload cannot be decoded as a JSON object.',
    );
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
    final project = _project(
      _requiredString(data, 'projectToken'),
      config,
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
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
      project,
    );
  }
}
