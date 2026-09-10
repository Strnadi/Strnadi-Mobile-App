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

class Transport extends OAuthApi {
  Transport(this.configuration);
  final OAuthConfiguration configuration;
  final calls = <Map<String, String>>[];
  @override
  Future<Map<String, dynamic>> postForm(
      Uri endpoint, Map<String, String> fields) async {
    expect(endpoint, configuration.tokenEndpoint);
    calls.add(fields);
    return fields['grant_type']!.contains('token-exchange')
        ? {
            'access_token': fixture.jwt(
                DateTime.now().add(const Duration(hours: 1)),
                audience: 'project:${configuration.projectId}',
                issuer: configuration.issuer.toString()),
            'token_type': 'Bearer'
          }
        : {
            'access_token': 'administration-only',
            'expires_in': 3600,
            'refresh_token': 'refresh-only',
            'token_type': 'Bearer'
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
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancel) async {
    requests.add(options);
    beforeSend?.call(options);
    await beforeResponse?.call();
    return ResponseBody.fromString(jsonEncode(responseData), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
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

  setUp(() async {
    values.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      switch (call.method) {
        case 'read':
          return values[args['key']];
        case 'write':
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
            '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}');
    AppAdministration.useSessionForTesting(session);
    original = ApiDioClient.instance.httpClientAdapter;
    adapter = Adapter();
    ApiDioClient.instance.httpClientAdapter = adapter;
  });
  tearDown(() async {
    await AppAdministration.close();
    ApiDioClient.instance.httpClientAdapter = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('logout clears credentials before browser and switches environment last',
      () async {
    final events = <String>[];
    final config = Config.administration!;
    session = AdministrationSession(
      configuration: config,
      transport: Transport(config),
      store: const SecureStorageAuthSessionKeyValueStore(),
      browser: (uri) async {
        expect(uri.path, config.logoutEndpoint.path);
        expect(uri.queryParameters,
            {'redirect_uri': OAuthConfiguration.redirectUri});
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
  });

  test('PKCE activates GUID and routes only project tokens to Tenant',
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
    expect(adapter.requests.last.headers['Authorization'],
        'Bearer ${snapshot.accessToken}');
    expect(adapter.requests.last.followRedirects, isFalse);
    await const UserController().uploadProfilePhoto(
        userId: fixture.subject,
        photoBase64: 'fake',
        format: 'png',
        accessToken: snapshot.accessToken,
        host: Config.host);
    expect(adapter.requests.last.uri.host, 'preprod-administration.strnadi.cz');
    expect(adapter.requests.last.uri.path, '/account/profile-photo');
    expect(adapter.requests.last.headers['Authorization'],
        'Bearer administration-only');
    await activatedAuthSessions.invalidate();
    await expectLater(AppAdministration.token(), throwsA(isA<OAuthFailure>()));
  });

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
    final response = await const UserController().getUserById(fixture.subject,
        accessToken: snapshot.accessToken, host: Config.host);
    expect(response.data['nickname'], 'birdwatcher');
    expect(response.data['role'], 'tester');
    final request = adapter.requests.single;
    expect(request.uri.path, '/account/profile');
    expect(request.uri.host, 'preprod-administration.strnadi.cz');
    expect(request.headers['Authorization'], 'Bearer ${snapshot.accessToken}');
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
        host: Config.host);
    expect(adapter.requests.last.method, 'PATCH');
    expect(adapter.requests.last.data, {
      'userName': 'new-name',
      'firstName': 'Jan',
      'lastName': 'Novak',
      'city': null,
      'postCode': null,
    });
  });

  test('foreign profiles and removed JSON password reset never make a request',
      () async {
    await AppAdministration.signIn();
    await expectLater(
        const UserController()
            .getUserById('01a08608-44b7-7aba-8d0c-542148b30bf2'),
        throwsStateError);
    expect(
        () => const AuthController().setResetPassword(
            email: 'person@example.test',
            token: 'reset-token',
            password: 'new-password'),
        throwsUnsupportedError);
    expect(adapter.requests, isEmpty);
  });

  test(
      'profile response from another account is rejected; HTTP rejection stays a failure',
      () async {
    await AppAdministration.signIn();
    adapter.responseData = {'id': 'different-owner'};
    await expectLater(const UserController().getUserById(fixture.subject),
        throwsFormatException);
    adapter.status = 403;
    final response = await const UserController().getUserById(fixture.subject);
    expect(response.statusCode, 403);
  });

  test(
      'renewal inside the authenticated interceptor uses the API controller without deadlock',
      () async {
    var now = DateTime.now();
    final authAdapter = Adapter();
    final previousAuth = ApiDioClient.authorization.httpClientAdapter;
    ApiDioClient.authorization.httpClientAdapter = authAdapter;
    addTearDown(
        () => ApiDioClient.authorization.httpClientAdapter = previousAuth);
    final config = Config.administration!;
    authAdapter.beforeSend = (request) {
      final grant = (request.data as Map)['grant_type'] as String;
      authAdapter.responseData = grant.contains('token-exchange')
          ? {
              'access_token': fixture.jwt(now.add(const Duration(minutes: 5)),
                  audience: 'project:${config.projectId}',
                  issuer: config.issuer.toString()),
              'token_type': 'Bearer'
            }
          : {
              'access_token': 'admin-only',
              'refresh_token': 'refresh-only',
              'expires_in': 3600,
              'token_type': 'Bearer'
            };
    };
    session = AdministrationSession(
        configuration: config,
        transport: const AuthController(),
        store: const SecureStorageAuthSessionKeyValueStore(),
        now: () => now,
        browser: (uri) async =>
            '${OAuthConfiguration.redirectUri}?code=fake&state=${uri.queryParameters['state']}');
    AppAdministration.useSessionForTesting(session);
    await AppAdministration.signIn();
    final first = (await activatedAuthSessions.capture())!;
    now = now.add(const Duration(hours: 2));
    await const ArticlesController()
        .fetchArticles()
        .timeout(const Duration(seconds: 3));
    expect(authAdapter.requests, hasLength(4));
    expect(
        authAdapter.requests
            .every((r) => !r.headers.containsKey('Authorization')),
        isTrue);
    final renewed = (await activatedAuthSessions.capture())!;
    expect(renewed.sessionId, first.sessionId);
    expect(renewed.accessToken, isNot(first.accessToken));
    expect(adapter.requests.single.headers['Authorization'],
        'Bearer ${renewed.accessToken}');
  });

  test(
      'the active Dio client rejects credentials for foreign or insecure origins',
      () async {
    await AppAdministration.signIn();
    final token = (await activatedAuthSessions.capture())!.accessToken;
    for (final target in [
      'https://other.example/recordings',
      'http://preprod-api.strnadi.cz/recordings',
      'https://preprod-api.strnadi.cz:8443/recordings'
    ]) {
      await expectLater(
          ApiDioClient.instance.get(target,
              options: Options(headers: {'Authorization': 'Bearer $token'})),
          throwsA(isA<DioException>()));
    }
    expect(adapter.requests, isEmpty);
  });

  test('the active Dio client discards a response arriving after logout',
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
  });

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
        adapter.requests.single.headers.containsKey('Authorization'), isFalse);
  });

  test('scope changes reject an activated project session', () async {
    await AppAdministration.signIn();
    await Config.setHostEnvironment(HostEnvironment.prod);
    expect(await activatedAuthSessions.capture(), isNull);
    await expectLater(AppAdministration.token(), throwsA(isA<OAuthFailure>()));
  });
}
