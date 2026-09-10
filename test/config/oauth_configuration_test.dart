import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/auth/administration/oauth_session.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/administration/oauth_session_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Config.loadConfig();
  });

  test(
      'unprovisioned builds have no OAuth configuration or environment fallback',
      () {
    for (final environment in [HostEnvironment.prod, HostEnvironment.dev]) {
      expect(Config.administrationForEnvironment(environment), isNull);
    }
  });

  test('preprod has the deployed issuer and Strnadi project', () {
    final configuration =
        Config.administrationForEnvironment(HostEnvironment.preprod)!;
    expect(configuration.issuer.toString(),
        'https://preprod-administration.strnadi.cz/');
    expect(configuration.projectId, '01a08608-44b7-7aba-8d0c-542148b30bf2');
  });

  test('requires explicit HTTPS origins and project GUID', () {
    for (final issuer in [
      'http://admin.example/',
      'https://u:p@admin.example/',
      'https://admin.example/path',
      'https://admin.example/?a=b',
      '',
      'https://tenant.example'
    ]) {
      expect(
          () => OAuthConfiguration(
              environment: 'prod',
              issuer: Uri.parse(issuer),
              tenantOrigin: fixture.config.tenantOrigin,
              projectId: fixture.projectId),
          throwsArgumentError);
    }
    expect(
        () => OAuthConfiguration(
            environment: 'preprod',
            issuer: fixture.config.issuer,
            tenantOrigin: fixture.config.tenantOrigin,
            projectId: ''),
        throwsArgumentError);
  });

  test('project, issuer, tenant and environment partition storage', () {
    final variants = [
      fixture.config,
      OAuthConfiguration(
          environment: 'prod',
          issuer: fixture.config.issuer,
          tenantOrigin: fixture.config.tenantOrigin,
          projectId: fixture.projectId),
      OAuthConfiguration(
          environment: 'dev',
          issuer: fixture.config.issuer,
          tenantOrigin: fixture.config.tenantOrigin,
          projectId: fixture.projectId),
      OAuthConfiguration(
          environment: 'preprod',
          issuer: Uri.parse('https://other.example/'),
          tenantOrigin: fixture.config.tenantOrigin,
          projectId: fixture.projectId),
      OAuthConfiguration(
          environment: 'preprod',
          issuer: fixture.config.issuer,
          tenantOrigin: Uri.parse('https://other.example/'),
          projectId: fixture.projectId),
      OAuthConfiguration(
          environment: 'preprod',
          issuer: fixture.config.issuer,
          tenantOrigin: fixture.config.tenantOrigin,
          projectId: '019a1234-1234-7123-8123-123456789abd'),
    ];
    expect(
        variants
            .map((config) => AdministrationSession(
                configuration: config,
                transport: fixture.FakeTransport(),
                store: fixture.MemoryStore(),
                browser: (_) async => '').storageKey)
            .toSet()
            .length,
        variants.length);
  });

  test('all public error categories resolve in every locale', () {
    for (final file in Directory('assets/lang').listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final json = jsonDecode(file.readAsStringSync());
      for (final kind in OAuthFailureKind.values) {
        dynamic value = json;
        for (final part in OAuthFailure(kind).translationKey.split('.')) {
          value = (value as Map)[part];
        }
        expect(value, isA<String>(), reason: '${file.path}: $kind');
        expect(value, isNot(isEmpty));
      }
    }
  });

  test(
      'production storage adapter writes scoped credentials, logout keeps unrelated keys',
      () async {
    FlutterSecureStorage.setMockInitialValues({'legacy-recovery': 'keep'});
    final transport = fixture.FakeTransport()
      ..respond = (fields) async => fields['grant_type'] == 'authorization_code'
          ? {
              'access_token': 'admin-secret',
              'refresh_token': 'refresh-secret',
              'expires_in': 3600,
              'token_type': 'Bearer'
            }
          : {
              'access_token':
                  fixture.jwt(fixture.start.add(const Duration(hours: 1))),
              'token_type': 'Bearer'
            };
    final session = AdministrationSession(
        configuration: fixture.config,
        transport: transport,
        store: const SecureStorageAuthSessionKeyValueStore(),
        now: () => fixture.start,
        browser: (uri) async =>
            'com.delta.strnadi://auth/callback?code=c&state=${uri.queryParameters['state']}');
    await session.signIn();
    final saved = await const FlutterSecureStorage().readAll();
    expect(
        saved.keys, unorderedEquals(['legacy-recovery', session.storageKey]));
    expect(jsonDecode(saved[session.storageKey]!)['refreshToken'],
        'refresh-secret');
    await session.signOut();
    expect(await const FlutterSecureStorage().readAll(),
        {'legacy-recovery': 'keep'});
  });
}
