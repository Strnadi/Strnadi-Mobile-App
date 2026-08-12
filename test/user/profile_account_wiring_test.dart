import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profile/account production wiring (source only)', () {
    test('profile photo cache is owner and environment scoped', () {
      final String source = File('lib/user/userPage.dart').readAsStringSync();

      expect(source, contains('profilePhotoCacheKey('));
      expect(source, contains('ownerUserId: session.userId'));
      expect(source, contains('environment: Config.hostEnvironment.name'));
      expect(source, contains('ProfilePhotoPublishCoordinator'));
      expect(source, contains('publishBoundedCandidate('));
      expect(source, contains('candidateLength: candidateFile.length'));
      expect(source, contains('readCandidate: candidateFile.readAsBytes'));
      expect(source, isNot(contains('readAsBytesSync')));
      expect(source, isNot(contains("'profilePic_\$")));
      expect(source, isNot(contains("removeFile('profilePic_")));
    });

    test('selected photo is not made visible before successful publication',
        () {
      final String source = File('lib/user/userPage.dart').readAsStringSync();
      final int upload =
          source.indexOf('_photoPublisher.publishBoundedCandidate(');
      final int visible =
          source.indexOf('setState(() => profileImagePath = cachedPath)');

      expect(upload, greaterThan(0));
      expect(visible, greaterThan(upload));
      expect(source, isNot(contains('profileImagePath = pickedFile.path')));
      expect(source, isNot(contains("key: 'profileImage'")));
    });

    test('profile code never logs names or local image paths', () {
      final String source = File('lib/user/userPage.dart').readAsStringSync();

      expect(source, isNot(contains('Loaded name from local storage')));
      expect(source, isNot(contains('Loaded profile picture from cache:')));
      expect(source, isNot(contains('Profile picture downloaded \$')));
      for (final String line in source.split('\n')) {
        if (!line.contains('logger.')) continue;
        expect(line, isNot(contains('profileImagePath')));
        expect(line, isNot(contains('file.path')));
        expect(line, isNot(contains('userName')));
        expect(line, isNot(contains('lastName')));
      }
    });

    test('profile editor uses canonical keys and a single-flight save', () {
      final String source =
          File('lib/user/settingsPages/userInfo.dart').readAsStringSync();

      expect(source, contains('profileFirstNameStorageKey'));
      expect(source, contains('profileLastNameStorageKey'));
      expect(source, contains('profileNicknameStorageKey'));
      expect(source, contains('_saveFlight.run('));
      expect(source, contains('await _refreshUser(session, host)'));
      expect(source, contains('parseSuccessfulUserProfile('));
      expect(source, isNot(contains("key: 'user'")));
      expect(source, isNot(contains("key: 'lastname'")));
      expect(source, isNot(contains('int.parse(_postCodeController')));
      expect(source, isNot(contains('extractEmailFromJwt')));
    });

    test('both user-page logout branches await ordered identity cleanup', () {
      final String source = File('lib/user/userPage.dart').readAsStringSync();

      expect(
        RegExp(r'await runOrderedLogoutCleanup\(').allMatches(source),
        hasLength(2),
      );
      expect(source, isNot(contains('unawaited(TrackingConsentManager')));
      expect(source, contains('resetAnalyticsIdentity:'));
      expect(source, contains('clearAuthSession:'));
    });

    test('connected accounts use verified activated-session ownership', () {
      final String source =
          File('lib/user/settingsPages/connectedPlatforms.dart')
              .readAsStringSync();

      expect(source, contains('activatedAuthSessions.capture()'));
      expect(source, contains('snapshot.verified'));
      expect(source, contains('session.accessToken'));
      expect(source, contains('host: session.host'));
      expect(source, contains('Config.host == observed.host'));
      expect(source, isNot(contains("read(key: 'userId')")));
      expect(source, isNot(contains('FlutterSecureStorage')));
    });

    test('connected account copy is localized and failure state is retryable',
        () {
      final String source =
          File('lib/user/settingsPages/connectedPlatforms.dart')
              .readAsStringSync();

      expect(source, contains("t('user.connectedAccounts.allConnected')"));
      expect(source, contains("t('user.connectedAccounts.loadFailed')"));
      expect(source, contains("t('user.connectedAccounts.retry')"));
      expect(source, contains('_loadFailed = true'));
      expect(source, contains('_isRefreshing = false'));
      expect(source, isNot(contains('Váš účet')));
      expect(source, isNot(contains('Pokračovat přes')));
      expect(source, isNot(contains('Již propojeno')));
    });

    test('account status controllers require explicit captured auth', () {
      final String source =
          File('lib/api/controllers/auth_controller.dart').readAsStringSync();
      final int google =
          source.indexOf('Future<Response<dynamic>> hasGoogleId');
      final int apple = source.indexOf('Future<Response<dynamic>> hasAppleId');
      final String checks = source.substring(
          google,
          source.indexOf(
            'Future<Response<dynamic>> resendVerificationEmail',
            apple,
          ));

      expect(checks, contains('required String accessToken'));
      expect(checks, contains('required String host'));
      expect(checks, contains("'Authorization': 'Bearer \$accessToken'"));
      expect(
        checks,
        contains("extra: const <String, Object>{'authRequired': true}"),
      );
      expect(checks, isNot(contains("'authRequired': false")));
      expect(checks, contains('followRedirects: false'));
    });
  });

  test('source-contract tests cannot use a real API or database', () {
    final String source =
        File('test/user/profile_account_wiring_test.dart').readAsStringSync();
    expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
    expect(source, isNot(contains(<String>['open', 'Database('].join())));
    expect(source, isNot(contains(<String>['Database', 'New'].join())));
  });
}
