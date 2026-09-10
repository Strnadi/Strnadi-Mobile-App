import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/user_identity.dart';
import 'package:strnadi/auth/user_profile_payload.dart';
import 'package:strnadi/config/config.dart';

import 'oauth_session.dart';
import 'pkce_attempt.dart';
import 'system_authentication_browser.dart';

/// One scoped OAuth owner per isolate. Persisted activated markers are checked
/// before renewal so an isolate cannot restore a session after logout.
class AppAdministration {
  static AdministrationSession? _session;
  @visibleForTesting
  static void useSessionForTesting(AdministrationSession? value) =>
      _session = value;
  static bool get enabled => Config.usesAdministration;

  static AdministrationSession get session {
    final configuration = Config.administration;
    if (!enabled || configuration == null) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    final existing = _session;
    if (existing != null &&
        existing.configuration.scopeKey == configuration.scopeKey) {
      return existing;
    }
    existing?.cancelSignIn();
    return _session = AdministrationSession(
      configuration: configuration,
      transport: const AuthController(),
      store: const SecureStorageAuthSessionKeyValueStore(),
      browser: openSystemAuthenticationBrowser,
    );
  }

  static Future<void> signIn() async {
    final owner = session;
    await activatedAuthSessions.invalidate();
    const store = SecureStorageAuthSessionKeyValueStore();
    await cacheUserProfileMetadata(null,
        write: (key, value) =>
            value == null ? store.delete(key) : store.write(key, value));
    final credential = await owner.signIn();
    if (!enabled ||
        !identical(owner, session) ||
        parseUserId(credential.subject) is! String) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    owner.requireCurrent(credential);
    final transition = await activatedAuthSessions
        .beginTokenTransition(credential.accessToken);
    await activatedAuthSessions.activate(transition, credential.subject,
        verified: true);
  }

  static Future<String> token(
      {String? capturedToken, bool administration = false}) async {
    final before = await activatedAuthSessions.capture();
    if (before == null ||
        parseUserId(before.userId) is! String ||
        (capturedToken != null && before.accessToken != capturedToken)) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    final owner = session;
    final credential =
        await owner.projectCredential(expectedSubject: before.userId);
    if (!enabled ||
        !identical(owner, session) ||
        !await activatedAuthSessions.isCurrent(before)) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    owner.requireCurrent(credential);
    await activatedAuthSessions.replaceCredential(
        before, credential.accessToken);
    return administration
        ? await owner.administrationCredential(expectedSubject: before.userId)
        : credential.accessToken;
  }

  /// Capture the old environment before cleanup or an environment switch.
  static Future<void> Function()? captureBrowserLogout() {
    if (!enabled) return null;
    final owner = session;
    return () async {
      await owner.endBrowserSession();
    };
  }

  static Future<void> close() async {
    final owner = _session;
    _session = null;
    if (owner != null) await owner.close();
  }
}
