import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/projects/available_project.dart';
import 'package:strnadi/projects/project_switch_guard.dart';
import 'dart:async';
import 'package:strnadi/user/logout_safety.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/api/controllers/articles_controller.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/administration/app_administration.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/auth/administration/oauth_session.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'oauth_session_test.dart' as fixture;

class ProjectLogSink implements AppLogSink {
  final records = <AppLogRecord>[];
  @override
  void add(AppLogRecord record) {
    if (record.scope == 'projects') records.add(record);
  }

  List<Object?> get events => records.map((r) => r.context['event']).toList();
}

class Transport extends OAuthApi {
  Transport(this.configuration, {this.userId = fixture.subject});
  final String userId;
  final OAuthConfiguration configuration;
  final calls = <Map<String, String>>[];
  List<Map<String, dynamic>>? projects;
  List<Map<String, dynamic>> catalog = [];
  final joins = <Map<String, dynamic>>[];
  bool denyJoin = false;
  bool wrongProfile = false;
  Completer<void>? profileWait;
  final profileProjects = <String>[];
  List<String> projectRoles = ['admin'];
  bool denyProfile = false;
  @override
  Future<dynamic> postAdministration(
    Uri endpoint,
    String token,
    Map<String, dynamic> body,
  ) async {
    expect(endpoint.origin, configuration.issuer.origin);
    expect(endpoint.path, matches(RegExp(r'^/projects/[0-9a-f-]+/members$')));
    expect(token, 'administration-only');
    expect(body, {'email': 'self@example.test'});
    joins.add(Map.of(body));
    if (denyJoin) throw const OAuthFailure(OAuthFailureKind.exchangeDenied);
    return {'userId': userId, 'email': 'self@example.test', 'roleNames': []};
  }

  bool denyExchange = false;
  final deniedProjects = <String>{};
  OAuthFailure? exchangeFailure;
  Completer<void>? discoveryWait;
  OAuthFailure? discoveryFailure;
  @override
  Future<dynamic> getAdministration(Uri endpoint, String token) async {
    if (endpoint.path == '/connect/user-info') return {'sub': userId};
    if (endpoint.path == '/projects') return catalog;
    if (endpoint.path == '/account/profile') {
      final projectId = endpoint.queryParameters['projectId'];
      if (projectId != null) {
        profileProjects.add(projectId);
        final claims =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(base64Url.normalize(token.split('.')[1])),
                  ),
                )
                as Map;
        expect(claims['aud'], 'project:$projectId');
      }
      await profileWait?.future;
      if (denyProfile) throw const OAuthFailure(OAuthFailureKind.server);
      return {
        'id': wrongProfile ? 'another-user' : userId,
        'email': 'self@example.test',
        'firstName': 'Test',
        'lastName': 'User',
        'roles': projectRoles,
      };
    }
    expect(endpoint.path, '/users/$userId/projects');
    await discoveryWait?.future;
    if (discoveryFailure != null) throw discoveryFailure!;
    return projects ??
        [
          {
            'id': configuration.projectId,
            'name': 'Strnadi',
            'apiDomain': configuration.tenantOrigin.origin,
          },
        ];
  }

  @override
  Future<Map<String, dynamic>> postForm(
    Uri endpoint,
    Map<String, String> fields,
  ) async {
    expect(endpoint, configuration.tokenEndpoint);
    calls.add(fields);
    if (fields['project_id'] != null && exchangeFailure != null) {
      throw exchangeFailure!;
    }
    if ((denyExchange && fields['project_id'] != null) ||
        deniedProjects.contains(fields['project_id'])) {
      throw const OAuthFailure(OAuthFailureKind.exchangeDenied);
    }
    return fields['grant_type']!.contains('token-exchange')
        ? {
            'access_token': fixture.jwt(
              DateTime.now().add(const Duration(hours: 1)),
              owner: userId,
              audience: 'project:${fields['project_id']}',
              issuer: configuration.issuer.toString(),
            ),
            'token_type': 'Bearer',
          }
        : {
            'access_token': 'administration-only',
            'expires_in': 3600,
            'refresh_token': 'refresh-only',
            'token_type': 'Bearer',
          };
  }
}

class Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object responseData = <Object>[];
  int status = 200;
  void Function(RequestOptions)? beforeSend;
  Future<void> Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    beforeSend?.call(options);
    await beforeResponse?.call();
    return ResponseBody.fromString(
      jsonEncode(responseData),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final values = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late AdministrationSession session;
  late Adapter adapter;
  late HttpClientAdapter original;
  bool failActivationOnce = false;
  final projectLogs = ProjectLogSink();

  setUp(() async {
    AppAdministration.detachNotificationsForTesting = () async {};
    AppAdministration.syncNotificationsForTesting = () async {};
    values.clear();
    projectLogs.records.clear();
    AppLogger.configure(telemetrySink: projectLogs);
    failActivationOnce = false;
    AppAdministration.projectNotice = null;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          switch (call.method) {
            case 'read':
              return values[args['key']];
            case 'write':
              if (failActivationOnce &&
                  args['key'] ==
                      ActivatedAuthSessionManager.activatedMarkerKey) {
                failActivationOnce = false;
                throw PlatformException(code: 'storage-unavailable');
              }
              values[args['key']] = args['value'];
              return null;
            case 'delete':
              values.remove(args['key']);
              return null;
            default:
              throw StateError('Unexpected storage operation');
          }
        });
    await Config.loadConfig();
    await Config.setHostEnvironment(HostEnvironment.preprod);
    final config = Config.administration!;
    session = AdministrationSession(
      configuration: config,
      transport: Transport(config),
      store: const SecureStorageAuthSessionKeyValueStore(),
      browser: (uri) async =>
          '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}',
    );
    AppAdministration.useSessionForTesting(session);
    original = ApiDioClient.instance.httpClientAdapter;
    adapter = Adapter();
    ApiDioClient.instance.httpClientAdapter = adapter;
  });
  tearDown(() async {
    await AppAdministration.close();
    AppAdministration.detachNotificationsForTesting = null;
    AppAdministration.syncNotificationsForTesting = null;
    AppLogger.configure();
    ApiDioClient.instance.httpClientAdapter = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const otherId = '019a1234-1234-7123-8123-123456789abd';
  const otherProject = AvailableProject(
    id: otherId,
    name: 'Other project',
    apiDomain: 'https://other.example',
  );

  test(
    'signed-out startup clears old notices without requesting projects',
    () async {
      AppAdministration.projectNotice = 'projects.loadFailed';
      expect(await AppAdministration.restoreLogin(), isFalse);
      expect(AppAdministration.projectNotice, isNull);
      expect((session.transport as Transport).calls, isEmpty);
      expect(projectLogs.events, isNot(contains('discovered')));
    },
  );

  test('restoring a signed-in account clears a stale loading notice', () async {
    await AppAdministration.signIn();
    AppAdministration.projectNotice = 'projects.loadFailed';
    expect(await AppAdministration.restoreLogin(), isTrue);
    expect(AppAdministration.projectNotice, isNull);
  });

  test(
    'startup still reports actual discovery failure and empty membership',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      transport.discoveryFailure = const OAuthFailure(OAuthFailureKind.server);
      expect(await AppAdministration.restoreLogin(), isFalse);
      expect(AppAdministration.projectNotice, 'projects.loadFailed');
      transport.discoveryFailure = null;
      transport.projects = [];
      expect(await AppAdministration.restoreLogin(), isFalse);
      expect(AppAdministration.projectNotice, 'projects.empty');
    },
  );

  test(
    'a retired OAuth session requires login without a project alert',
    () async {
      await AppAdministration.signIn();
      await session.close();
      expect(await AppAdministration.restoreLogin(), isFalse);
      expect(AppAdministration.projectNotice, isNull);
    },
  );

  test(
    'login waits for a project choice before exchanging or activating',
    () async {
      final transport = session.transport as Transport;
      transport.projects = [
        {
          'id': session.configuration.projectId,
          'name': 'Original',
          'apiDomain': session.configuration.tenantOrigin.origin,
        },
        otherProject.toJson(),
      ];
      final opened = Completer<void>();
      final choice = Completer<AvailableProject>();
      final login = AppAdministration.signIn(
        chooseProject: (projects) {
          expect(projects.map((p) => p.id), contains(otherId));
          opened.complete();
          return choice.future;
        },
      );
      await opened.future;
      expect(
        transport.calls.where((c) => c.containsKey('project_id')),
        isEmpty,
      );
      expect(Config.activeProject, isNull);
      choice.complete(otherProject);
      await login;
      expect(Config.activeProject!.id, otherId);
      expect(
        transport.calls
            .where((c) => c.containsKey('project_id'))
            .single['project_id'],
        otherId,
      );
      expect(
        projectLogs.events,
        containsAll(['loginChoiceRequired', 'loginChoiceSelected']),
      );
    },
  );

  test(
    'cancelling the login picker does not exchange a project token',
    () async {
      final transport = session.transport as Transport;
      transport.projects = [
        {
          'id': session.configuration.projectId,
          'name': 'Original',
          'apiDomain': session.configuration.tenantOrigin.origin,
        },
        otherProject.toJson(),
      ];
      await expectLater(
        AppAdministration.signIn(
          chooseProject: (_) async {
            throw const OAuthFailure(OAuthFailureKind.cancelled);
          },
        ),
        throwsA(
          isA<OAuthFailure>().having(
            (e) => e.kind,
            'kind',
            OAuthFailureKind.cancelled,
          ),
        ),
      );
      expect(
        transport.calls.where((c) => c.containsKey('project_id')),
        isEmpty,
      );
      expect(Config.activeProject, isNull);
    },
  );

  test('single-project login continues without opening a picker', () async {
    await AppAdministration.signIn(
      chooseProject: (_) async {
        fail('Single-project login must not ask for a choice');
      },
    );
    expect(Config.activeProject!.id, session.configuration.projectId);
  });

  test(
    'self-join uses own email, remembers role-free membership, and does not switch',
    () async {
      await AppAdministration.signIn();
      final previous = await activatedAuthSessions.capture();
      final oldScope = Config.dataEnvironment;
      final transport = session.transport as Transport;
      transport.catalog = [otherProject.toJson()];
      expect((await AppAdministration.projectCatalog()).single.id, otherId);
      await AppAdministration.joinProject(otherProject);
      expect(transport.joins, [
        {'email': 'self@example.test'},
      ]);
      expect(Config.dataEnvironment, oldScope);
      expect(await activatedAuthSessions.isCurrent(previous!), true);
      expect(
        (await AppAdministration.availableProjects()).map((p) => p.id),
        contains(otherId),
      );
      await AppAdministration.switchProject(otherProject);
      expect(Config.activeProject!.id, otherId);
      // Server role discovery still omits this membership after a fresh session.
      AppAdministration.useSessionForTesting(
        AdministrationSession(
          configuration: Config.administration!,
          transport: transport,
          store: const SecureStorageAuthSessionKeyValueStore(),
          browser: (_) async => 'unused',
        ),
      );
      await AppAdministration.restoreProject();
      expect(Config.activeProject!.id, otherId);
    },
  );

  test(
    'remembered role-free joins cannot cross accounts or grant revoked access',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      transport.catalog = [otherProject.toJson()];
      await AppAdministration.joinProject(otherProject);
      transport.denyExchange = true;
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsA(isA<OAuthFailure>()),
      );
      await AppAdministration.close();
      await activatedAuthSessions.invalidate();
      final config = Config.administration!;
      final otherTransport = Transport(
        config,
        userId: '019a1234-5678-7123-8123-123456789abd',
      )..catalog = [otherProject.toJson()];
      session = AdministrationSession(
        configuration: config,
        transport: otherTransport,
        store: const SecureStorageAuthSessionKeyValueStore(),
        browser: (uri) async =>
            '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}',
      );
      AppAdministration.useSessionForTesting(session);
      await AppAdministration.signIn();
      expect(
        (await AppAdministration.availableProjects()).map((p) => p.id),
        isNot(contains(otherId)),
      );
    },
  );

  test('join rejection is retryable and never activates the target', () async {
    await AppAdministration.signIn();
    final previous = await activatedAuthSessions.capture();
    final transport = session.transport as Transport;
    transport.catalog = [otherProject.toJson()];
    transport.denyJoin = true;
    await expectLater(
      AppAdministration.joinProject(otherProject),
      throwsA(isA<OAuthFailure>()),
    );
    expect(await activatedAuthSessions.isCurrent(previous!), true);
    expect(
      (await AppAdministration.availableProjects()).map((p) => p.id),
      isNot(contains(otherId)),
    );
    transport.denyJoin = false;
    await AppAdministration.joinProject(otherProject);
    expect(
      (await AppAdministration.availableProjects()).map((p) => p.id),
      contains(otherId),
    );
  });

  test(
    'profile identity mismatch cannot submit another user for membership',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport..wrongProfile = true;
      await expectLater(
        AppAdministration.joinProject(otherProject),
        throwsA(isA<OAuthFailure>()),
      );
      expect(transport.joins, isEmpty);
    },
  );

  test(
    'logout while fetching own email prevents the membership POST',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      transport.profileWait = Completer<void>();
      final pending = AppAdministration.joinProject(otherProject);
      final expectation = expectLater(pending, throwsA(isA<OAuthFailure>()));
      await Future<void>.delayed(Duration.zero);
      await AppAdministration.close();
      await activatedAuthSessions.invalidate();
      transport.profileWait!.complete();
      await expectation;
      expect(transport.joins, isEmpty);
    },
  );

  test(
    'account with no projects can join its first project before activation',
    () async {
      final transport = session.transport as Transport;
      transport.projects = [];
      transport.catalog = [otherProject.toJson()];
      await AppAdministration.signIn(
        chooseFirstProject: (catalog, join) async {
          expect(await activatedAuthSessions.capture(), isNull);
          expect(catalog.single.id, otherId);
          await join(catalog.single);
          return catalog.single;
        },
      );
      expect(transport.joins.length, 1);
      expect(Config.activeProject!.id, otherId);
      expect((await activatedAuthSessions.capture())!.userId, fixture.subject);
    },
  );

  test(
    'membership HTTP contract posts JSON with Administration token and rejects redirects',
    () async {
      final config = Config.administration!;
      final authAdapter = Adapter();
      final previous = ApiDioClient.authorization.httpClientAdapter;
      ApiDioClient.authorization.httpClientAdapter = authAdapter;
      addTearDown(
        () => ApiDioClient.authorization.httpClientAdapter = previous,
      );
      authAdapter.beforeSend = (request) {
        authAdapter.status = request.method == 'GET' ? 200 : 201;
        authAdapter.responseData = request.method == 'GET'
            ? {'id': fixture.subject, 'email': 'self@example.test'}
            : {'userId': fixture.subject};
      };
      await const AuthController().joinProject(
        config,
        'admin-only',
        fixture.subject,
        otherProject,
      );
      final request = authAdapter.requests.last;
      expect(request.uri, config.issuer.resolve('/projects/$otherId/members'));
      expect(request.data, {'email': 'self@example.test'});
      expect(request.headers['Authorization'], 'Bearer admin-only');
      expect(request.followRedirects, false);
      authAdapter.beforeSend = (request) {
        authAdapter.status = request.method == 'GET' ? 200 : 302;
        authAdapter.responseData = {
          'id': fixture.subject,
          'email': 'self@example.test',
        };
      };
      await expectLater(
        const AuthController().joinProject(
          config,
          'admin-only',
          fixture.subject,
          otherProject,
        ),
        throwsA(isA<OAuthFailure>()),
      );
    },
  );

  test(
    'switch commits project routing and a new session, preserving local data',
    () async {
      await AppAdministration.signIn();
      final before = await activatedAuthSessions.capture();
      final oldScope = Config.dataEnvironment;
      values['recording-recovery'] = 'original owner and upload id';
      final transport = session.transport as Transport;
      transport.projects = [otherProject.toJson()];
      await AppAdministration.switchProject(otherProject);
      expect(Config.host, 'https://other.example');
      expect(Config.administration!.projectId, otherId);
      expect(Config.dataEnvironment, isNot(oldScope));
      expect(
        (await activatedAuthSessions.capture())!.sessionId,
        isNot(before!.sessionId),
      );
      expect(values['recording-recovery'], 'original owner and upload id');
      expect(
        projectLogs.events,
        containsAll(['commitStarted', 'sessionActivated']),
      );
      final queued = Recording(
        id: 7,
        BEId: 81,
        userId: fixture.subject,
        createdAt: DateTime(2026),
        estimatedBirdsCount: 1,
        byApp: true,
        partCount: 1,
        env: oldScope,
        uploadKey: 'original-upload',
        parentUploadAttempted: true,
      );
      final currentUpload = await captureActivatedRecordingUploadSession(
        captureActivatedSession: activatedAuthSessions.capture,
        readOptionalDeviceId: () async => null,
        environment: Config.dataEnvironment,
        backendHost: Config.host,
      );
      expect(
        () => validateRecordingSessionBinding(queued, currentUpload!),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );
      expect(queued.BEId, 81);
      expect(queued.uploadKey, 'original-upload');
      expect(queued.env, oldScope);
      expect(await activatedAuthSessions.isCurrent(before), false);
      Config.useProject(null);
      await Config.loadActiveProject();
      expect(Config.activeProject!.id, otherId);
      expect(await AppAdministration.token(), isNotEmpty);
    },
  );

  test(
    'denied switch leaves previous token, routing and selection usable; retry succeeds',
    () async {
      await AppAdministration.signIn();
      final before = await activatedAuthSessions.capture();
      final scope = Config.dataEnvironment;
      final transport = session.transport as Transport;
      transport.projects = [otherProject.toJson()];
      transport.denyExchange = true;
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsA(isA<OAuthFailure>()),
      );
      expect(Config.dataEnvironment, scope);
      expect(await activatedAuthSessions.isCurrent(before!), true);
      expect(await AppAdministration.token(), before.accessToken);
      expect(ProjectSwitchGuard.switching, false);
      transport.denyExchange = false;
      await AppAdministration.switchProject(otherProject);
      expect(Config.activeProject!.id, otherId);
    },
  );

  test(
    'local activation failure rolls back selection and keeps the old account usable',
    () async {
      await AppAdministration.signIn();
      final oldScope = Config.dataEnvironment;
      (session.transport as Transport).projects = [otherProject.toJson()];
      failActivationOnce = true;
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsA(isA<PlatformException>()),
      );
      expect(Config.dataEnvironment, oldScope);
      expect(
        projectLogs.events,
        containsAll(['rollbackStarted', 'rollbackCompleted']),
      );
      expect(await AppAdministration.token(), isNotEmpty);
      Config.useProject(null);
      await Config.loadActiveProject();
      expect(Config.dataEnvironment, oldScope);
    },
  );

  test(
    'interactive login asks again despite remembered selection and across accounts',
    () async {
      final originalProject = AvailableProject(
        id: session.configuration.projectId,
        name: 'Original',
        apiDomain: session.configuration.tenantOrigin.origin,
      );
      await AppAdministration.signIn();
      (session.transport as Transport).projects = [
        originalProject.toJson(),
        otherProject.toJson(),
      ];
      await AppAdministration.switchProject(otherProject);
      for (final user in [
        fixture.subject,
        '019a1234-5678-7123-8123-123456789abd',
      ]) {
        await AppAdministration.close();
        await activatedAuthSessions.invalidate();
        Config.useProject(null);
        final config = Config.administration!;
        final transport = Transport(config, userId: user)
          ..projects = [originalProject.toJson(), otherProject.toJson()];
        session = AdministrationSession(
          configuration: config,
          transport: transport,
          store: const SecureStorageAuthSessionKeyValueStore(),
          browser: (uri) async =>
              '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}',
        );
        AppAdministration.useSessionForTesting(session);
        var choices = 0;
        await AppAdministration.signIn(
          chooseProject: (projects) async {
            choices++;
            return projects.firstWhere((p) => p.id == originalProject.id);
          },
        );
        expect(choices, 1);
        expect(Config.activeProject!.id, originalProject.id);
      }
    },
  );

  test(
    'active or paused recording blocks switching before discovery',
    () async {
      await AppAdministration.signIn();
      final owner = Object();
      ProjectSwitchGuard.register(owner, () => true);
      addTearDown(() => ProjectSwitchGuard.unregister(owner));
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsStateError,
      );
      expect(Config.activeProject!.id, session.configuration.projectId);
    },
  );

  test(
    'restoration rechecks membership even when the cached project token is valid',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      final exchangesBefore = transport.calls
          .where((r) => r['project_id'] != null)
          .length;
      await AppAdministration.restoreProject();
      expect(
        transport.calls.where((r) => r['project_id'] != null).length,
        exchangesBefore + 1,
      );
      transport.denyExchange = true;
      await expectLater(AppAdministration.restoreProject(), throwsStateError);
    },
  );

  test(
    'revoked restored project falls back without reassigning stored drafts',
    () async {
      await AppAdministration.signIn();
      values['draft'] = Config.dataEnvironment;
      (session.transport as Transport).projects = [otherProject.toJson()];
      await AppAdministration.restoreProject();
      expect(Config.activeProject!.id, otherId);
      expect(values['draft'], isNot(Config.dataEnvironment));
      expect(AppAdministration.projectNotice, 'projects.fallback');
    },
  );

  test(
    'restoration skips rejected candidates and selects a later project',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      final third = AvailableProject(
        id: '019a1234-1234-7123-8123-123456789abe',
        name: 'Accessible',
        apiDomain: 'https://third.example',
      );
      transport.projects = [otherProject.toJson(), third.toJson()];
      transport.deniedProjects.add(otherId);
      await AppAdministration.restoreProject();
      expect(Config.activeProject!.id, third.id);
      expect(AppAdministration.projectNotice, 'projects.fallback');
      expect(
        transport.calls
            .where((c) => c['project_id'] != null)
            .map((c) => c['project_id'])
            .toList(),
        [session.configuration.projectId, otherId, third.id],
      );
    },
  );

  test(
    'restoration tries all rejected candidates without changing the session',
    () async {
      await AppAdministration.signIn();
      final before = await activatedAuthSessions.capture();
      final transport = session.transport as Transport;
      transport.projects = [
        otherProject.toJson(),
        {
          'id': '019a1234-1234-7123-8123-123456789abe',
          'name': 'Third',
          'apiDomain': 'https://third.example',
        },
      ];
      transport.denyExchange = true;
      var cleanups = 0;
      AppAdministration.detachNotificationsForTesting = () async {
        cleanups++;
      };
      await expectLater(AppAdministration.restoreProject(), throwsStateError);
      expect(await activatedAuthSessions.isCurrent(before!), isTrue);
      expect(cleanups, 0);
      expect(transport.calls.where((c) => c['project_id'] != null).length, 3);
    },
  );

  for (final rollback in [false, true]) {
    test(
      'project switch rebinds notifications after ${rollback ? "rollback" : "commit"}',
      () async {
        await AppAdministration.signIn();
        final before = (await activatedAuthSessions.capture())!;
        final oldHost = Config.host;
        (session.transport as Transport).projects = [otherProject.toJson()];
        final steps = <String>[];
        String? registeredHost;
        String? registeredToken;
        ActivatedAuthSessionSnapshot? registeredSession;
        AppAdministration.detachNotificationsForTesting = () async {
          steps.add('detach');
          expect(Config.host, oldHost);
          expect(await activatedAuthSessions.isCurrent(before), isTrue);
        };
        AppAdministration.syncNotificationsForTesting = () async {
          steps.add('sync');
          registeredHost = Config.host;
          registeredSession = await activatedAuthSessions.capture();
          registeredToken = await AppAdministration.token();
        };
        failActivationOnce = rollback;
        if (rollback) {
          await expectLater(
            AppAdministration.switchProject(otherProject),
            throwsA(isA<PlatformException>()),
          );
        } else {
          await AppAdministration.switchProject(otherProject);
        }
        expect(steps, ['detach', 'sync']);
        expect(
          registeredHost,
          rollback ? oldHost : otherProject.apiOrigin!.origin,
        );
        expect(registeredSession!.sessionId, isNot(before.sessionId));
        expect(registeredSession!.userId, before.userId);
        expect(registeredToken, registeredSession!.accessToken);
      },
    );
  }

  test(
    'logout during notification cleanup cannot register the candidate',
    () async {
      await AppAdministration.signIn();
      (session.transport as Transport).projects = [otherProject.toJson()];
      var registrations = 0;
      AppAdministration.detachNotificationsForTesting = () async {
        await AppAdministration.close();
        await activatedAuthSessions.invalidate();
      };
      AppAdministration.syncNotificationsForTesting = () async {
        registrations++;
      };
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsA(isA<OAuthFailure>()),
      );
      expect(registrations, 0);
      expect(await activatedAuthSessions.capture(), isNull);
    },
  );

  test(
    'failed notification cleanup aborts switching and restores the old binding',
    () async {
      await AppAdministration.signIn();
      final oldHost = Config.host;
      (session.transport as Transport).projects = [otherProject.toJson()];
      var registrations = 0;
      AppAdministration.detachNotificationsForTesting = () async {
        throw StateError('projects.switchFailed');
      };
      AppAdministration.syncNotificationsForTesting = () async {
        registrations++;
        expect(Config.host, oldHost);
      };
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsStateError,
      );
      expect(Config.host, oldHost);
      expect(registrations, 1);
    },
  );

  test(
    'restoration stops on exchange network errors instead of trying another project',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      transport.projects = [
        otherProject.toJson(),
        {
          'id': '019a1234-1234-7123-8123-123456789abe',
          'name': 'Third',
          'apiDomain': 'https://third.example',
        },
      ];
      transport.exchangeFailure = const OAuthFailure(OAuthFailureKind.network);
      await expectLater(
        AppAdministration.restoreProject(),
        throwsA(
          isA<OAuthFailure>().having(
            (e) => e.kind,
            'kind',
            OAuthFailureKind.network,
          ),
        ),
      );
      expect(transport.calls.where((c) => c['project_id'] != null).length, 2);
    },
  );

  test('registration failure does not roll back a committed project', () async {
    await AppAdministration.signIn();
    (session.transport as Transport).projects = [otherProject.toJson()];
    AppAdministration.syncNotificationsForTesting = () async {
      throw StateError('offline');
    };
    await AppAdministration.switchProject(otherProject);
    expect(Config.activeProject!.id, otherId);
    expect(await AppAdministration.token(), isNotEmpty);
    expect(
      projectLogs.records.where(
        (r) => r.context['operation'] == 'syncNotifications',
      ),
      isNotEmpty,
    );
  });

  for (final roles in [
    <String>['admin'],
    <String>[],
  ]) {
    test(
      'switch caches target roles $roles before completing activation',
      () async {
        await AppAdministration.signIn();
        values['role'] = 'tester';
        final transport = session.transport as Transport;
        transport.projects = [otherProject.toJson()];
        transport.projectRoles = roles;
        String? roleAtRegistration;
        AppAdministration.syncNotificationsForTesting = () async {
          roleAtRegistration = values['role'];
        };
        await AppAdministration.switchProject(otherProject);
        expect(transport.profileProjects, [otherId]);
        expect(values['role'], roles.isEmpty ? isNull : 'admin');
        expect(roleAtRegistration, values['role']);
      },
    );
  }

  for (final oldRole in [null, 'tester']) {
    test('failed activation restores previous role $oldRole', () async {
      await AppAdministration.signIn();
      if (oldRole != null) values['role'] = oldRole;
      (session.transport as Transport).projects = [otherProject.toJson()];
      failActivationOnce = true;
      await expectLater(
        AppAdministration.switchProject(otherProject),
        throwsA(isA<PlatformException>()),
      );
      expect(values['role'], oldRole);
    });
  }

  test('failed profile loading preserves the old project and role', () async {
    await AppAdministration.signIn();
    final before = (await activatedAuthSessions.capture())!;
    values['role'] = 'tester';
    final transport = session.transport as Transport;
    transport.projects = [otherProject.toJson()];
    transport.denyProfile = true;
    await expectLater(
      AppAdministration.switchProject(otherProject),
      throwsA(isA<OAuthFailure>()),
    );
    expect(await activatedAuthSessions.isCurrent(before), isTrue);
    expect(values['role'], 'tester');
  });

  test('another account profile cannot supply the target role', () async {
    await AppAdministration.signIn();
    final before = (await activatedAuthSessions.capture())!;
    values['role'] = 'tester';
    final transport = session.transport as Transport;
    transport.projects = [otherProject.toJson()];
    transport.wrongProfile = true;
    await expectLater(
      AppAdministration.switchProject(otherProject),
      throwsFormatException,
    );
    expect(await activatedAuthSessions.isCurrent(before), isTrue);
    expect(values['role'], 'tester');
  });

  test(
    'logout while loading candidate profile cannot cache its role',
    () async {
      await AppAdministration.signIn();
      final transport = session.transport as Transport;
      transport.projects = [otherProject.toJson()];
      transport.profileWait = Completer<void>();
      final switching = AppAdministration.switchProject(otherProject);
      final expectation = expectLater(switching, throwsA(isA<OAuthFailure>()));
      while (transport.profileProjects.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      await AppAdministration.close();
      await activatedAuthSessions.invalidate();
      transport.profileWait!.complete();
      await expectation;
      expect(values['role'], isNull);
      expect(await activatedAuthSessions.capture(), isNull);
    },
  );

  test('no projects fails closed without deleting the old session', () async {
    await AppAdministration.signIn();
    final before = await activatedAuthSessions.capture();
    (session.transport as Transport).projects = [];
    await expectLater(AppAdministration.restoreProject(), throwsStateError);
    expect(await activatedAuthSessions.isCurrent(before!), true);
  });

  test('logout during discovery cannot reactivate a candidate', () async {
    await AppAdministration.signIn();
    final transport = session.transport as Transport;
    transport.projects = [otherProject.toJson()];
    transport.discoveryWait = Completer<void>();
    final switching = AppAdministration.switchProject(otherProject);
    final expectation = expectLater(switching, throwsA(isA<OAuthFailure>()));
    await Future<void>.delayed(Duration.zero);
    await AppAdministration.close();
    await activatedAuthSessions.invalidate();
    transport.discoveryWait!.complete();
    await expectation;
    expect(await activatedAuthSessions.capture(), isNull);
    expect(ProjectSwitchGuard.switching, false);
  });

  test(
    'logout clears credentials before browser and switches environment last',
    () async {
      final events = <String>[];
      final config = Config.administration!;
      session = AdministrationSession(
        configuration: config,
        transport: Transport(config),
        store: const SecureStorageAuthSessionKeyValueStore(),
        browser: (uri) async {
          expect(uri.path, config.logoutEndpoint.path);
          expect(uri.queryParameters, {
            'redirect_uri': OAuthConfiguration.redirectUri,
          });
          expect(values.containsKey(session.storageKey), false);
          expect(events, ['capture', 'reset', 'device', 'auth', 'provider']);
          expect(Config.hostEnvironment, HostEnvironment.preprod);
          events.add('browser');
          throw const OAuthFailure(OAuthFailureKind.cancelled);
        },
      );
      AppAdministration.useSessionForTesting(session);
      values[session.storageKey] = 'old credentials';
      await runOrderedLogoutCleanup(
        captureLogoutEvent: () async => events.add('capture'),
        resetAnalyticsIdentity: () async => events.add('reset'),
        deleteDeviceToken: () async => events.add('device'),
        clearAuthSession: () async => events.add('auth'),
        signOutIdentityProvider: () async => events.add('provider'),
        afterCleanup: () async {
          events.add('switch');
          await Config.setHostEnvironment(HostEnvironment.prod);
        },
      );
      expect(events.last, 'switch');
      expect(events, contains('browser'));
      expect(Config.hostEnvironment, HostEnvironment.prod);
    },
  );

  test(
    'PKCE activates GUID and routes only project tokens to Tenant',
    () async {
      values['firstName'] = 'Previous account';
      await AppAdministration.signIn();
      final snapshot = (await activatedAuthSessions.capture())!;
      expect(snapshot.userId, fixture.subject);
      expect(values['firstName'], isNull);
      expect(values['token'], isNot('administration-only'));
      expect(values[session.storageKey], contains('administration-only'));
      await const ArticlesController().fetchArticles();
      expect(adapter.requests.last.uri.host, 'preprod-api.strnadi.cz');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer ${snapshot.accessToken}',
      );
      expect(adapter.requests.last.followRedirects, isFalse);
      await const UserController().uploadProfilePhoto(
        userId: fixture.subject,
        photoBase64: 'fake',
        format: 'png',
        accessToken: snapshot.accessToken,
        host: Config.host,
      );
      expect(
        adapter.requests.last.uri.host,
        'preprod-administration.strnadi.cz',
      );
      expect(adapter.requests.last.uri.path, '/account/profile-photo');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer administration-only',
      );
      await activatedAuthSessions.invalidate();
      await expectLater(
        AppAdministration.token(),
        throwsA(isA<OAuthFailure>()),
      );
    },
  );

  test(
    'own profile uses project token, maps names/roles, and sends the new patch',
    () async {
      await AppAdministration.signIn();
      final snapshot = (await activatedAuthSessions.capture())!;
      adapter.responseData = {
        'id': fixture.subject,
        'firstName': 'Jan',
        'lastName': 'Novak',
        'userName': 'birdwatcher',
        'email': 'person@example.test',
        'city': 'Praha',
        'postCode': 11000,
        'roles': ['tester'],
      };
      final response = await const UserController().getUserById(
        fixture.subject,
        accessToken: snapshot.accessToken,
        host: Config.host,
      );
      expect(response.data['nickname'], 'birdwatcher');
      expect(response.data['role'], 'tester');
      final request = adapter.requests.single;
      expect(request.uri.path, '/account/profile');
      expect(
        request.uri.queryParameters['projectId'],
        Config.administration!.projectId,
      );
      expect(request.uri.host, 'preprod-administration.strnadi.cz');
      expect(
        request.headers['Authorization'],
        'Bearer ${snapshot.accessToken}',
      );
      expect(request.followRedirects, isFalse);
      await const UserController().updateUserById(
        fixture.subject,
        {
          'nickname': 'new-name',
          'firstName': 'Jan',
          'lastName': 'Novak',
          'city': null,
          'postCode': null,
          'email': 'ignored@example.test',
        },
        accessToken: snapshot.accessToken,
        host: Config.host,
      );
      expect(adapter.requests.last.method, 'PATCH');
      expect(adapter.requests.last.data, {
        'userName': 'new-name',
        'firstName': 'Jan',
        'lastName': 'Novak',
        'city': null,
        'postCode': null,
      });
    },
  );

  test(
    'foreign profiles and removed JSON password reset never make a request',
    () async {
      await AppAdministration.signIn();
      await expectLater(
        const UserController().getUserById(
          '01a08608-44b7-7aba-8d0c-542148b30bf2',
        ),
        throwsStateError,
      );
      expect(
        () => const AuthController().setResetPassword(
          email: 'person@example.test',
          token: 'reset-token',
          password: 'new-password',
        ),
        throwsUnsupportedError,
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'profile response from another account is rejected; HTTP rejection stays a failure',
    () async {
      await AppAdministration.signIn();
      adapter.responseData = {'id': 'different-owner'};
      await expectLater(
        const UserController().getUserById(fixture.subject),
        throwsFormatException,
      );
      adapter.status = 403;
      final response = await const UserController().getUserById(
        fixture.subject,
      );
      expect(response.statusCode, 403);
    },
  );

  test(
    'renewal inside the authenticated interceptor uses the API controller without deadlock',
    () async {
      var now = DateTime.now();
      final authAdapter = Adapter();
      final previousAuth = ApiDioClient.authorization.httpClientAdapter;
      ApiDioClient.authorization.httpClientAdapter = authAdapter;
      addTearDown(
        () => ApiDioClient.authorization.httpClientAdapter = previousAuth,
      );
      final config = Config.administration!;
      authAdapter.beforeSend = (request) {
        if (request.method == 'GET') {
          authAdapter.responseData = request.uri.path == '/connect/user-info'
              ? {'sub': fixture.subject}
              : [
                  {
                    'id': config.projectId,
                    'name': 'Strnadi',
                    'apiDomain': config.tenantOrigin.origin,
                  },
                ];
          return;
        }
        final grant = (request.data as Map)['grant_type'] as String;
        authAdapter.responseData = grant.contains('token-exchange')
            ? {
                'access_token': fixture.jwt(
                  now.add(const Duration(minutes: 5)),
                  audience: 'project:${config.projectId}',
                  issuer: config.issuer.toString(),
                ),
                'token_type': 'Bearer',
              }
            : {
                'access_token': 'admin-only',
                'refresh_token': 'refresh-only',
                'expires_in': 3600,
                'token_type': 'Bearer',
              };
      };
      session = AdministrationSession(
        configuration: config,
        transport: const AuthController(),
        store: const SecureStorageAuthSessionKeyValueStore(),
        now: () => now,
        browser: (uri) async =>
            '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}',
      );
      AppAdministration.useSessionForTesting(session);
      await AppAdministration.signIn();
      final first = (await activatedAuthSessions.capture())!;
      now = now.add(const Duration(hours: 2));
      await const ArticlesController().fetchArticles().timeout(
        const Duration(seconds: 3),
      );
      expect(
        authAdapter.requests.where((r) => r.method == 'POST'),
        hasLength(4),
      );
      expect(
        authAdapter.requests
            .where((r) => r.method == 'POST')
            .every((r) => !r.headers.containsKey('Authorization')),
        isTrue,
      );
      final renewed = (await activatedAuthSessions.capture())!;
      expect(renewed.sessionId, first.sessionId);
      expect(renewed.accessToken, isNot(first.accessToken));
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer ${renewed.accessToken}',
      );
    },
  );

  test(
    'the active Dio client rejects credentials for foreign or insecure origins',
    () async {
      await AppAdministration.signIn();
      final token = (await activatedAuthSessions.capture())!.accessToken;
      for (final target in [
        'https://other.example/recordings',
        'http://preprod-api.strnadi.cz/recordings',
        'https://preprod-api.strnadi.cz:8443/recordings',
      ]) {
        await expectLater(
          ApiDioClient.instance.get(
            target,
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          ),
          throwsA(isA<DioException>()),
        );
      }
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'the active Dio client discards a response arriving after logout',
    () async {
      await AppAdministration.signIn();
      final sent = Completer<void>();
      final release = Completer<void>();
      adapter.beforeResponse = () {
        sent.complete();
        return release.future;
      };
      final request = const ArticlesController().fetchArticles();
      final check = expectLater(request, throwsA(isA<DioException>()));
      await sent.future;
      await activatedAuthSessions.invalidate();
      release.complete();
      await check;
    },
  );

  test('tenant authentication rejection is not retried', () async {
    await AppAdministration.signIn();
    adapter.status = 401;
    final response = await const ArticlesController().fetchArticles();
    expect(response.statusCode, 401);
    expect(adapter.requests, hasLength(1));
  });

  test('guest calls never reuse a legacy preprod JWT', () async {
    values['token'] = 'legacy-token';
    await const ArticlesController().fetchArticles();
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test('scope changes reject an activated project session', () async {
    await AppAdministration.signIn();
    await Config.setHostEnvironment(HostEnvironment.prod);
    expect(await activatedAuthSessions.capture(), isNull);
    await expectLater(AppAdministration.token(), throwsA(isA<OAuthFailure>()));
  });
}
