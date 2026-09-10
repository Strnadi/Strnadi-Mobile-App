import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/oauth_configuration.dart';
import 'package:strnadi/auth/administration/oauth_session.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';

const projectId = '019a1234-1234-7123-8123-123456789abc';
const subject = '019a1234-5678-7123-8123-123456789abc';
final config = OAuthConfiguration(
    environment: 'preprod',
    issuer: Uri.parse('https://admin.example/'),
    tenantOrigin: Uri.parse('https://tenant.example'),
    projectId: projectId);
final start = DateTime.utc(2026, 9, 8);

class MemoryStore implements AuthSessionKeyValueStore {
  final values = <String, String>{'recording-recovery': 'keep'};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeTransport extends OAuthApi {
  final requests = <Map<String, String>>[];
  late Future<Map<String, dynamic>> Function(Map<String, String>) respond;
  @override
  Future<Map<String, dynamic>> postForm(
      Uri endpoint, Map<String, String> fields) {
    expect(endpoint, config.tokenEndpoint);
    expect(fields, isNot(contains('client_secret')));
    requests.add(Map.of(fields));
    return respond(fields);
  }
}

String jwt(DateTime expiry,
    {String owner = subject,
    String audience = 'project:$projectId',
    String issuer = 'https://admin.example/'}) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'RS256'})}.${encode({
        'sub': owner,
        'aud': audience,
        'iss': issuer,
        'exp': expiry.millisecondsSinceEpoch ~/ 1000
      })}.signature';
}

Matcher fails(OAuthFailureKind kind) =>
    throwsA(isA<OAuthFailure>().having((e) => e.kind, 'kind', kind));

void main() {
  for (final outcome in ['success', 'cancelled', 'unexpected']) {
    test('browser logout clears tokens first, outcome=$outcome', () async {
      final storage = MemoryStore();
      late AdministrationSession owner;
      owner = AdministrationSession(
        configuration: config,
        transport: FakeTransport(),
        store: storage,
        browser: (uri) async {
          expect(uri.path, '/connect/logout');
          expect(uri.queryParameters,
              {'redirect_uri': OAuthConfiguration.redirectUri});
          expect(storage.values.containsKey(owner.storageKey), false);
          if (outcome == 'cancelled')
            throw const OAuthFailure(OAuthFailureKind.cancelled);
          return outcome == 'unexpected'
              ? '${OAuthConfiguration.redirectUri}?error=access_denied'
              : OAuthConfiguration.redirectUri;
        },
      );
      storage.values[owner.storageKey] = 'old credentials';
      await owner.close();
      expect(await owner.endBrowserSession(), outcome == 'success');
      expect(storage.values, {'recording-recovery': 'keep'});
      await expectLater(owner.signIn(), fails(OAuthFailureKind.staleSession));
    });
  }

  late DateTime now;
  late MemoryStore store;
  late FakeTransport transport;
  late AdministrationSession session;
  late Uri opened;
  setUp(() {
    now = start;
    store = MemoryStore();
    transport = FakeTransport()
      ..respond = (fields) async {
        if (fields['grant_type']!.contains('token-exchange')) {
          return {
            'access_token': jwt(now.add(const Duration(minutes: 5))),
            'token_type': 'Bearer'
          };
        }
        return {
          'access_token': 'administration-only',
          'expires_in': 3600,
          'refresh_token':
              fields['grant_type'] == 'refresh_token' ? 'rotated' : 'original',
          'token_type': 'Bearer'
        };
      };
    session = AdministrationSession(
        configuration: config,
        transport: transport,
        store: store,
        now: () => now,
        browser: (uri) async {
          opened = uri;
          return '${OAuthConfiguration.redirectUri}?code=a%2Bb%26c&state=${uri.queryParameters['state']}';
        });
  });

  test('failed account switch cannot reuse the previous project token',
      () async {
    await session.signIn();
    final respond = transport.respond;
    transport.respond = (fields) async {
      if (fields['grant_type']!.contains('token-exchange')) {
        throw const OAuthFailure(OAuthFailureKind.exchangeDenied);
      }
      return respond(fields);
    };
    await expectLater(session.signIn(), fails(OAuthFailureKind.exchangeDenied));
    await expectLater(
        session.projectCredential(), fails(OAuthFailureKind.loginRequired));
    expect(store.values, {'recording-recovery': 'keep'});
  });

  test(
      'code exchange failure permits a fresh attempt without persisting credentials',
      () async {
    final respond = transport.respond;
    transport.respond =
        (_) async => throw const OAuthFailure(OAuthFailureKind.network);
    await expectLater(session.signIn(), fails(OAuthFailureKind.network));
    final oldState = opened.queryParameters['state'];
    expect(transport.requests.length, 1);
    expect(store.values, {'recording-recovery': 'keep'});
    transport.respond = respond;
    await session.signIn();
    expect(opened.queryParameters['state'], isNot(oldState));
    expect(transport.requests[1]['code_verifier'],
        isNot(transport.requests.first['code_verifier']));
  });

  test('refresh without rotation retains the original refresh token', () async {
    await session.signIn();
    now = now.add(const Duration(hours: 2));
    final respond = transport.respond;
    transport.respond = (fields) async {
      final result = await respond(fields);
      if (fields['grant_type'] == 'refresh_token')
        result.remove('refresh_token');
      return result;
    };
    await session.projectCredential();
    expect(jsonDecode(store.values[session.storageKey]!)['refreshToken'],
        'original');
  });

  test('RFC 7636 S256 vector and fresh independent random values', () {
    expect(
        PkceAttempt.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    final first = PkceAttempt.create();
    final second = PkceAttempt.create();
    expect(first.verifier.length, 43);
    expect(first.verifier, isNot(first.state));
    expect(first.verifier, isNot(second.verifier));
    expect(first.state, isNot(second.state));
  });

  test('code exchange uses same verifier and exact project exchange contract',
      () async {
    final credential = await session.signIn();
    expect(opened.queryParameters['code_challenge'],
        PkceAttempt.challengeFor(transport.requests.first['code_verifier']!));
    expect(opened.queryParameters['scope'], 'openid offline_access');
    expect(transport.requests.first['code'], 'a+b&c');
    expect(transport.requests.first['redirect_uri'],
        OAuthConfiguration.redirectUri);
    expect(transport.requests.last, {
      'grant_type': 'urn:ietf:params:oauth:grant-type:token-exchange',
      'subject_token': 'administration-only',
      'subject_token_type': 'urn:ietf:params:oauth:token-type:access_token',
      'client_id': 'strnadi-app',
      'project_id': projectId,
    });
    expect(credential.subject, subject);
    expect(credential.accessToken, isNot('administration-only'));
    expect(store.values, isNot(contains('token')));
    expect(store.values['recording-recovery'], 'keep');
  });

  for (final malformed in [
    '?code=c',
    '?code=c&state=wrong',
    '?state={state}',
    '?code=c&state={state}&state={state}',
    '?code=c&code=d&state={state}',
    '?code=&state={state}',
    '?code=c&state={state}#fragment',
    '?error=access_denied&code=c&state={state}',
  ]) {
    test('rejects callback $malformed without exchanging', () async {
      final invalid = AdministrationSession(
          configuration: config,
          transport: transport,
          store: store,
          browser: (uri) async =>
              OAuthConfiguration.redirectUri +
              malformed.replaceAll('{state}', uri.queryParameters['state']!));
      await expectLater(
          invalid.signIn(), fails(OAuthFailureKind.invalidCallback));
      expect(transport.requests, isEmpty);
    });
  }

  for (final target in [
    'https://auth/callback',
    'com.delta.strnadi://other/callback',
    'com.delta.strnadi://auth/callback/',
    'com.delta.strnadi://auth:443/callback',
    'com.delta.strnadi://user@auth/callback',
    'com.delta.strnadi://auth/%63allback',
    'COM.delta.strnadi://auth/callback'
  ]) {
    test('rejects wrong callback target $target', () {
      final attempt = PkceAttempt.create();
      expect(
          () =>
              attempt.consumeCallback('$target?code=c&state=${attempt.state}'),
          fails(OAuthFailureKind.invalidCallback));
    });
  }

  test('callback can only be consumed once', () {
    final attempt = PkceAttempt.create();
    final callback =
        '${OAuthConfiguration.redirectUri}?code=c&state=${attempt.state}';
    expect(attempt.consumeCallback(callback), 'c');
    expect(() => attempt.consumeCallback(callback),
        fails(OAuthFailureKind.invalidCallback));
  });

  test('project expiry exchanges without refreshing Administration', () async {
    await session.signIn();
    now = now.add(const Duration(minutes: 6));
    await session.projectCredential();
    expect(transport.requests.length, 3);
    expect(transport.requests.last['grant_type'], contains('token-exchange'));
  });

  test('independent Administration expiry does not renew a valid project token',
      () async {
    final respond = transport.respond;
    transport.respond = (fields) async {
      final result = await respond(fields);
      if (!fields['grant_type']!.contains('token-exchange')) {
        result['expires_in'] = 60;
      }
      return result;
    };
    await session.signIn();
    now = now.add(const Duration(minutes: 2));
    await session.projectCredential();
    expect(transport.requests.length, 2);
  });

  test('both expiries refresh with rotation then exchange; requests coalesce',
      () async {
    await session.signIn();
    now = now.add(const Duration(hours: 2));
    final credentials =
        await Future.wait(List.generate(8, (_) => session.projectCredential()));
    expect(credentials.map((c) => c.accessToken).toSet().length, 1);
    expect(transport.requests.length, 4);
    expect(transport.requests[2], {
      'grant_type': 'refresh_token',
      'refresh_token': 'original',
      'client_id': 'strnadi-app'
    });
    expect(jsonDecode(store.values[session.storageKey]!)['refreshToken'],
        'rotated');
  });

  test('rotation survives failed exchange and restart', () async {
    await session.signIn();
    now = now.add(const Duration(hours: 2));
    final respond = transport.respond;
    transport.respond = (fields) async {
      if (fields['grant_type']!.contains('token-exchange')) {
        throw const OAuthFailure(OAuthFailureKind.network);
      }
      return respond(fields);
    };
    await expectLater(
        session.projectCredential(), fails(OAuthFailureKind.network));
    expect(jsonDecode(store.values[session.storageKey]!)['refreshToken'],
        'rotated');
    transport.respond = respond;
    final restored = AdministrationSession(
        configuration: config,
        transport: transport,
        store: store,
        now: () => now,
        browser: (_) => throw StateError('no browser'));
    await restored.projectCredential(expectedSubject: subject);
    expect(
        transport.requests
            .where((r) => r['grant_type'] == 'refresh_token')
            .length,
        1);
  });

  for (final failure in [
    OAuthFailureKind.loginRequired,
    OAuthFailureKind.exchangeDenied
  ]) {
    test(
        'terminal $failure clears credentials, preserves recordings, never loops',
        () async {
      await session.signIn();
      now = now.add(const Duration(hours: 2));
      transport.respond = (_) async => throw OAuthFailure(failure);
      await expectLater(session.projectCredential(), fails(failure));
      expect(store.values, {'recording-recovery': 'keep'});
      await expectLater(
          session.projectCredential(), fails(OAuthFailureKind.loginRequired));
      expect(transport.requests.length, 3);
    });
  }

  test('network failure retains credentials and recovery data', () async {
    await session.signIn();
    final saved = Map.of(store.values);
    now = now.add(const Duration(hours: 2));
    transport.respond =
        (_) async => throw const OAuthFailure(OAuthFailureKind.network);
    await expectLater(
        session.projectCredential(), fails(OAuthFailureKind.network));
    expect(store.values, saved);
  });

  test('wrong account is rejected after refresh', () async {
    await session.signIn();
    now = now.add(const Duration(minutes: 6));
    transport.respond = (_) async => {
          'access_token':
              jwt(now.add(const Duration(hours: 1)), owner: 'other-account'),
          'token_type': 'Bearer'
        };
    await expectLater(
        session.projectCredential(), fails(OAuthFailureKind.loginRequired));
    expect(store.values, {'recording-recovery': 'keep'});
  });

  test(
      'wrong audience or Administration token cannot become project credential',
      () async {
    transport.respond =
        (fields) async => fields['grant_type'] == 'authorization_code'
            ? {
                'access_token': 'administration-only',
                'expires_in': 3600,
                'refresh_token': 'r',
                'token_type': 'Bearer'
              }
            : {
                'access_token': jwt(now.add(const Duration(hours: 1)),
                    audience: 'administration'),
                'token_type': 'Bearer'
              };
    await expectLater(
        session.signIn(), fails(OAuthFailureKind.invalidResponse));
    expect(store.values, {'recording-recovery': 'keep'});
  });

  test('late browser callback after scope close never exchanges', () async {
    final callback = Completer<String>();
    final opening = Completer<Uri>();
    final pending = AdministrationSession(
        configuration: config,
        transport: transport,
        store: store,
        browser: (uri) {
          opening.complete(uri);
          return callback.future;
        });
    final login = pending.signIn();
    final check = expectLater(login, fails(OAuthFailureKind.staleSession));
    final uri = await opening.future;
    await pending.close();
    callback.complete(
        '${OAuthConfiguration.redirectUri}?code=c&state=${uri.queryParameters['state']}');
    await check;
    expect(transport.requests, isEmpty);
  });

  test('late refresh after logout cannot restore session', () async {
    await session.signIn();
    now = now.add(const Duration(hours: 2));
    final response = Completer<Map<String, dynamic>>();
    final requested = Completer<void>();
    transport.respond = (_) {
      requested.complete();
      return response.future;
    };
    final renewal = session.projectCredential();
    final check = expectLater(renewal, fails(OAuthFailureKind.staleSession));
    await requested.future;
    await session.signOut();
    response.complete({
      'access_token': 'late',
      'refresh_token': 'late',
      'expires_in': 3600,
      'token_type': 'Bearer'
    });
    await check;
    expect(store.values, {'recording-recovery': 'keep'});
  });

  test(
      'scope keys partition environment and project; expected owner is enforced',
      () async {
    await session.signIn();
    final other = AdministrationSession(
        configuration: OAuthConfiguration(
            environment: 'dev',
            issuer: config.issuer,
            tenantOrigin: config.tenantOrigin,
            projectId: projectId),
        transport: transport,
        store: store,
        browser: (_) => throw StateError('no browser'));
    expect(other.storageKey, isNot(session.storageKey));
    await expectLater(
        other.projectCredential(), fails(OAuthFailureKind.loginRequired));
    await expectLater(session.projectCredential(expectedSubject: 'other'),
        fails(OAuthFailureKind.staleSession));
  });
}
