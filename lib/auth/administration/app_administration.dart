import 'package:strnadi/projects/project_diagnostics.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/projects/available_project.dart';
import 'package:strnadi/projects/project_switch_guard.dart';
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
  static int _generation = 0;
  static bool _committingProject = false;
  static String? projectNotice;

  static String _activeKey() {
    final config = Config.administration!;
    return 'project.active.${config.environment}|${config.issuer.origin}';
  }

  static String _selectionKey(String subject) => '${_activeKey()}|$subject';

  static Future<List<AvailableProject>> availableProjects() =>
      ProjectDiagnostics.run(ProjectOperation.discover, () async {
        final before = await activatedAuthSessions.capture();
        if (before == null) {
          throw const OAuthFailure(OAuthFailureKind.loginRequired);
        }
        final owner = session;
        final projects = await owner.availableProjects(before.userId);
        if (!identical(owner, session) ||
            !await activatedAuthSessions.isCurrent(before)) {
          throw const OAuthFailure(OAuthFailureKind.staleSession);
        }
        return projects;
      });

  static Future<List<AvailableProject>> projectCatalog() =>
      ProjectDiagnostics.run(ProjectOperation.catalog, () async {
        final before = await activatedAuthSessions.capture();
        if (before == null) {
          throw const OAuthFailure(OAuthFailureKind.loginRequired);
        }
        final owner = session;
        final projects = await owner.projectCatalog(before.userId);
        if (!identical(owner, session) ||
            !await activatedAuthSessions.isCurrent(before)) {
          throw const OAuthFailure(OAuthFailureKind.staleSession);
        }
        return projects;
      });

  static Future<void> joinProject(AvailableProject project) =>
      ProjectDiagnostics.run(ProjectOperation.join, () async {
        final before = await activatedAuthSessions.capture();
        if (before == null) {
          throw const OAuthFailure(OAuthFailureKind.loginRequired);
        }
        final owner = session;
        await owner.joinProject(before.userId, project);
        if (!identical(owner, session) ||
            !await activatedAuthSessions.isCurrent(before)) {
          throw const OAuthFailure(OAuthFailureKind.staleSession);
        }
      });

  static Future<void> switchProject(AvailableProject requested) =>
      ProjectDiagnostics.run(ProjectOperation.switchProject, () async {
        if (ProjectSwitchGuard.recording) {
          ProjectDiagnostics.event(ProjectEvent.recordingBlocked);
          throw StateError('projects.recordingBlocked');
        }
        if (ProjectSwitchGuard.switching) {
          ProjectDiagnostics.event(ProjectEvent.switchAlreadyRunning);
          throw StateError('projects.switchFailed');
        }
        ProjectSwitchGuard.switching = true;
        try {
          await _switchProject(requested);
        } finally {
          ProjectSwitchGuard.switching = false;
        }
      });

  static Future<void> _switchProject(AvailableProject requested) async {
    final generation = _generation;
    final owner = session;
    final previousProject = Config.activeProject;
    final previousConfiguration = Config.administration!;
    final before = await activatedAuthSessions.capture();
    if (before == null) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    final projects = await owner.availableProjects(before.userId);
    final target = projects.where((p) => p.id == requested.id).firstOrNull;
    if (target == null) throw StateError('projects.revoked');
    final candidate = await owner.prepareProject(target, before.userId);
    final credential = await candidate.projectCredential(
      expectedSubject: before.userId,
    );
    if (generation != _generation ||
        !identical(owner, session) ||
        !await activatedAuthSessions.isCurrent(before)) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    if (ProjectSwitchGuard.recording) {
      ProjectDiagnostics.event(ProjectEvent.recordingBlocked);
      throw StateError('projects.recordingBlocked');
    }
    final prefs = await SharedPreferences.getInstance();
    final activeKey = _activeKey();
    final selectedKey = _selectionKey(before.userId);
    final oldActive = prefs.getString(activeKey);
    final oldSelected = prefs.getString(selectedKey);
    const profileStore = SecureStorageAuthSessionKeyValueStore();
    final oldRole = await profileStore.read('role');
    ProjectDiagnostics.event(ProjectEvent.commitStarted);
    _committingProject = true;
    try {
      await profileStore.delete('role');
      if (!await prefs.setString(activeKey, jsonEncode(target.toJson())) ||
          !await prefs.setString(selectedKey, target.id)) {
        throw StateError('projects.switchFailed');
      }
      if (generation != _generation) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      Config.useProject(target);
      final transition = await activatedAuthSessions.beginTokenTransition(
        credential.accessToken,
      );
      if (generation != _generation) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      await activatedAuthSessions.activate(
        transition,
        before.userId,
        verified: true,
      );
      if (generation != _generation) {
        throw const OAuthFailure(OAuthFailureKind.staleSession);
      }
      _session = candidate;
      owner.retire();
      ProjectDiagnostics.activated();
    } catch (error, stackTrace) {
      if (generation == _generation) {
        ProjectDiagnostics.failure(
          ProjectOperation.switchProject,
          error,
          stackTrace,
          afterSessionChange: true,
        );
        ProjectDiagnostics.event(
          ProjectEvent.rollbackStarted,
          afterSessionChange: true,
        );
        Config.useProject(previousProject);
        _session = owner;
        if (oldRole != null) await profileStore.write('role', oldRole);
        if (oldActive == null) {
          await prefs.remove(activeKey);
        } else {
          await prefs.setString(activeKey, oldActive);
        }
        if (oldSelected == null) {
          await prefs.remove(selectedKey);
        } else {
          await prefs.setString(selectedKey, oldSelected);
        }
        // Restore the prior logical owner after an interrupted local commit.
        final transition = await activatedAuthSessions.beginTokenTransition(
          before.accessToken,
        );
        await activatedAuthSessions.activate(
          transition,
          before.userId,
          verified: before.verified,
        );
        assert(
          Config.administration!.scopeKey == previousConfiguration.scopeKey,
        );
        ProjectDiagnostics.event(
          ProjectEvent.rollbackCompleted,
          afterSessionChange: true,
        );
      }
      rethrow;
    } finally {
      _committingProject = false;
    }
  }

  /// Missing or retired login state is normal at startup, not a discovery error.
  static Future<bool> restoreLogin() async {
    projectNotice = null;
    try {
      if (await activatedAuthSessions.capture() == null) return false;
      await restoreProject();
      await token();
      return true;
    } catch (error) {
      if (error is OAuthFailure &&
          (error.kind == OAuthFailureKind.loginRequired ||
              error.kind == OAuthFailureKind.staleSession)) {
        projectNotice = null;
      } else {
        projectNotice = error is StateError && error.message == 'projects.empty'
            ? 'projects.empty'
            : 'projects.loadFailed';
      }
      return false;
    }
  }

  /// Revalidate discovery on foreground restoration, never in an upload job.
  /// A revoked selection falls back only after an authorized candidate exists.
  static Future<void> restoreProject() =>
      ProjectDiagnostics.run(ProjectOperation.restore, () async {
        final projects = await availableProjects();
        final current = Config.administration!;
        final selected = projects
            .where(
              (p) =>
                  p.id == current.projectId &&
                  p.apiOrigin?.origin == current.tenantOrigin.origin,
            )
            .firstOrNull;
        if (selected != null) {
          final before = await activatedAuthSessions.capture();
          if (before == null) {
            throw const OAuthFailure(OAuthFailureKind.loginRequired);
          }
          final owner = session;
          try {
            await owner.validateProjectAccess(before.userId);
            if (!identical(owner, session) ||
                !await activatedAuthSessions.isCurrent(before)) {
              throw const OAuthFailure(OAuthFailureKind.staleSession);
            }
            Config.useProject(selected);
            return;
          } on OAuthFailure catch (error) {
            if (error.kind != OAuthFailureKind.exchangeDenied) rethrow;
            ProjectDiagnostics.event(ProjectEvent.accessRevoked);
          }
        }
        final fallback = projects
            .where(
              (p) =>
                  p.id != selected?.id &&
                  p.apiOrigin != null &&
                  p.apiOrigin!.origin != current.issuer.origin,
            )
            .firstOrNull;
        if (fallback == null) throw StateError('projects.empty');
        ProjectDiagnostics.event(ProjectEvent.fallbackSelected);
        await switchProject(fallback);
        projectNotice = 'projects.fallback';
      });

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

  static Future<void> signIn({
    InitialProjectChooser? chooseFirstProject,
    Future<AvailableProject> Function(List<AvailableProject>)? chooseProject,
  }) => ProjectDiagnostics.run(ProjectOperation.signIn, () async {
    if (ProjectSwitchGuard.switching) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    ++_generation;
    final owner = session;
    await activatedAuthSessions.invalidate();
    const store = SecureStorageAuthSessionKeyValueStore();
    await cacheUserProfileMetadata(
      null,
      write: (key, value) =>
          value == null ? store.delete(key) : store.write(key, value),
    );
    AvailableProject? selected;
    final credential = await owner.signIn(
      chooseFirstProject: chooseFirstProject,
      selectProject: (subject, projects) async {
        final prefs = await SharedPreferences.getInstance();
        final remembered = prefs.getString(_selectionKey(subject));
        final valid = projects
            .where(
              (p) =>
                  p.apiOrigin != null &&
                  p.apiOrigin!.origin != owner.configuration.issuer.origin,
            )
            .toList();
        if (valid.length > 1 && chooseProject != null) {
          ProjectDiagnostics.event(ProjectEvent.loginChoiceRequired);
          final choice = await chooseProject(List.unmodifiable(valid));
          selected = valid.where((p) => p.id == choice.id).firstOrNull;
          if (selected == null) {
            throw const OAuthFailure(OAuthFailureKind.invalidResponse);
          }
          ProjectDiagnostics.event(ProjectEvent.loginChoiceSelected);
        } else {
          selected =
              valid.where((p) => p.id == remembered).firstOrNull ??
              valid.firstOrNull;
          if (selected == null) throw StateError('projects.empty');
          ProjectDiagnostics.event(
            selected!.id == remembered
                ? ProjectEvent.selectionRemembered
                : ProjectEvent.defaultSelected,
          );
        }
        return selected!;
      },
    );
    Config.useProject(selected);
    _session = owner;
    if (!enabled ||
        !identical(owner, session) ||
        parseUserId(credential.subject) is! String) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    owner.requireCurrent(credential);
    final transition = await activatedAuthSessions.beginTokenTransition(
      credential.accessToken,
    );
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_activeKey(), jsonEncode(selected!.toJson())) ||
        !await prefs.setString(
          _selectionKey(credential.subject),
          selected!.id,
        )) {
      throw StateError('projects.switchFailed');
    }
    await activatedAuthSessions.activate(
      transition,
      credential.subject,
      verified: true,
    );
    ProjectDiagnostics.activated();
  });

  static Future<String> token({
    String? capturedToken,
    bool administration = false,
  }) async {
    if (_committingProject) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    final before = await activatedAuthSessions.capture();
    if (before == null ||
        parseUserId(before.userId) is! String ||
        (capturedToken != null && before.accessToken != capturedToken)) {
      throw const OAuthFailure(OAuthFailureKind.loginRequired);
    }
    final owner = session;
    final credential = await owner.projectCredential(
      expectedSubject: before.userId,
    );
    if (!enabled ||
        !identical(owner, session) ||
        !await activatedAuthSessions.isCurrent(before)) {
      throw const OAuthFailure(OAuthFailureKind.staleSession);
    }
    owner.requireCurrent(credential);
    await activatedAuthSessions.replaceCredential(
      before,
      credential.accessToken,
    );
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
    ++_generation;
    projectNotice = null;
    final owner = _session;
    _session = null;
    if (owner != null) await owner.close();
    if (enabled) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeKey());
    }
    Config.useProject(null);
    ProjectDiagnostics.event(ProjectEvent.signedOut);
  }
}
