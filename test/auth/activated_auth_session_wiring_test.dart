import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activated auth production wiring (source only; no API or DB)', () {
    test('active credential writers use the two-phase session manager', () {
      final Map<String, List<String>> requiredCalls = <String, List<String>>{
        'lib/auth/authorizator.dart': <String>[
          'beginTokenTransition(',
          'activateCurrentToken(',
          'activatedAuthSessions.activate(',
          'activatedAuthSessions.invalidate(',
        ],
        'lib/auth/login.dart': <String>[
          'beginTokenTransition(',
          'activatedAuthSessions.activate(',
        ],
        'lib/auth/registeration/cityReg.dart': <String>[
          'beginTokenTransition(',
          'activatedAuthSessions.activate(',
        ],
        'lib/auth/registeration/overview.dart': <String>[
          'beginTokenTransition(',
          'activatedAuthSessions.activate(',
        ],
        'lib/auth/registeration/mail.dart': <String>[
          'beginTokenTransition(',
          'activatedAuthSessions.activate(',
        ],
        'lib/auth/registeration/emailSent.dart': <String>[
          'beginTokenTransition(',
          'activatedAuthSessions.activate(',
        ],
        'lib/auth/unverifiedEmail.dart': <String>[
          'activatedAuthSessions.invalidate(',
        ],
      };

      for (final MapEntry<String, List<String>> entry
          in requiredCalls.entries) {
        final String source = File(entry.key).readAsStringSync();
        expect(
          source,
          contains("package:strnadi/auth/activated_auth_session.dart"),
          reason: '${entry.key} must import the activated-session boundary.',
        );
        for (final String requiredCall in entry.value) {
          expect(
            source,
            contains(requiredCall),
            reason: '${entry.key} must call $requiredCall.',
          );
        }
      }
    });

    test('no active auth screen independently writes session-owned keys', () {
      final RegExp directCredentialWrite = RegExp(
        r'''write\s*\(\s*key:\s*['"](?:token|userId|verified)['"]''',
        multiLine: true,
      );
      final List<File> authSources = Directory('lib/auth')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) => !file.path.endsWith('activated_auth_session.dart'),
          )
          .toList();

      expect(authSources, isNotEmpty);
      for (final File sourceFile in authSources) {
        expect(
          sourceFile.readAsStringSync(),
          isNot(matches(directCredentialWrite)),
          reason:
              '${sourceFile.path} must commit credentials through the session manager.',
        );
      }
    });

    test('password login rejects every non-200/non-403 JWT verification', () {
      final String source = File('lib/auth/login.dart').readAsStringSync();
      final int loginStart = source.indexOf('Future<void> _performLogin()');
      final int loginEnd = source.indexOf('void _showMessage', loginStart);
      final String login = source.substring(loginStart, loginEnd);

      final int verify = login.indexOf('verifyJwt(token)');
      final int classify =
          login.indexOf('classifyJwtVerificationStatus(', verify);
      final int rejected = login.indexOf(
        'verification == JwtVerificationDisposition.rejected',
        classify,
      );
      final int invalidate =
          login.indexOf('activatedAuthSessions.invalidate()', rejected);
      final int resolveOwner =
          login.indexOf('_userController.getUserIdFromToken()', invalidate);

      expect(verify, greaterThanOrEqualTo(0));
      expect(classify, greaterThan(verify));
      expect(rejected, greaterThan(classify));
      expect(invalidate, greaterThan(rejected));
      expect(resolveOwner, greaterThan(invalidate));
    });

    test('password submit is single-flight and disables while active', () {
      final String source = File('lib/auth/login.dart').readAsStringSync();

      expect(source, contains('final AsyncSingleFlight _loginSingleFlight'));
      expect(source, contains('if (_loginSingleFlight.isRunning) return;'));
      expect(source, contains('_loginSingleFlight.run(_performLogin)'));
      expect(
        source,
        contains(
          'onPressed: _loginSingleFlight.isRunning ? null : login',
        ),
      );
    });

    test('upload capture and current checks require the activated marker', () {
      final String source =
          File('lib/database/src/database_repository_api.dart')
              .readAsStringSync();
      final String service =
          File('lib/database/recording_upload_service.dart').readAsStringSync();

      expect(
        source,
        contains('captureActivatedRecordingUploadSession('),
      );
      expect(
        source,
        contains(
          'captureActivatedSession: activatedAuthSessions.capture',
        ),
      );
      expect(source, contains('await activatedAuthSessions.isCurrent('));
      expect(service, contains('logicalSessionId: activated.sessionId'));
      expect(
        service,
        contains('activated == null || !activated.verified'),
      );
      expect(source, contains('sessionId: session.logicalSessionId'));
      expect(source, contains('verified: true'));

      final int providerStart =
          source.indexOf('class _SecureStorageRecordingUploadSessions');
      final int providerEnd =
          source.indexOf('class _ConfigRecordingUploadPolicy');
      final String provider = source.substring(providerStart, providerEnd);
      expect(provider, isNot(contains("_storage.read(key: 'token')")));
      expect(provider, isNot(contains("_storage.read(key: 'userId')")));
    });

    test('session navigation never trusts the standalone verified key', () {
      final String navigation =
          File('lib/navigation/session_navigation.dart').readAsStringSync();
      final String verificationScreen =
          File('lib/auth/unverifiedEmail.dart').readAsStringSync();

      expect(navigation, contains('await activatedAuthSessions.capture()'));
      expect(navigation, contains('session?.verified != true'));
      expect(navigation, isNot(contains("read(key: 'verified')")));
      expect(
        verificationScreen,
        contains('await activatedAuthSessions.capture()'),
      );
      expect(
        verificationScreen,
        isNot(contains("read(key: 'verified')")),
      );
    });

    test('recording review and scheduling require an activated session', () {
      final String source =
          File('lib/PostRecordingForm/RecordingForm.dart').readAsStringSync();

      expect(
        RegExp(r'await activatedAuthSessions\.capture\(\)')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(source, contains('session?.verified != true'));
      expect(source, contains('uploadSession?.verified != true'));
      expect(source, contains('recording.mail = session!.subject'));
      expect(source, isNot(contains("read(key: 'token')")));
      expect(source, isNot(contains("read(key: 'userId')")));
      expect(source, isNot(contains('JwtDecoder.decode')));
    });

    test('guest adoption is transactionally pinned to one activated session',
        () {
      final String source =
          File('lib/database/src/database_repository.dart').readAsStringSync();
      final int methodStart =
          source.indexOf('static Future<void> updateRecordingsMail()');
      final int methodEnd = source.indexOf(
        'static Future<Map<String, Object?>> '
        '_requireCurrentEnvironmentRecordingParent',
      );
      final String method = source.substring(methodStart, methodEnd);

      expect(method, contains('sessionProvider.capture()'));
      expect(method, contains('validateRecordingUploadSession(session)'));
      expect(method, contains('db.transaction<void>'));
      expect(
        RegExp(r'_requireRecordingSessionCurrent\(sessionProvider, session\)')
            .allMatches(method),
        hasLength(2),
      );
      expect(method, isNot(contains("read(key: 'token')")));
      expect(method, isNot(contains("read(key: 'userId')")));
    });

    test('visible recording reads require one activated owner snapshot', () {
      final String source =
          File('lib/database/src/database_repository.dart').readAsStringSync();
      final int listStart =
          source.indexOf('static Future<List<Recording>> getRecordings()');
      final int capturedListStart = source.indexOf(
        'static Future<List<Recording>> _getRecordingsForCapturedSession',
        listStart,
      );
      final String visibleReads =
          source.substring(listStart, capturedListStart);
      final int byIdStart = source.indexOf(
        'static Future<Recording?> getRecordingFromDbById(',
      );
      final int noMailStart = source.indexOf(
        'static Future<Recording?> getRecordingFromDbByIdNoMail(',
        byIdStart,
      );
      final String byId = source.substring(byIdStart, noMailStart);

      expect(visibleReads, contains('_captureRecordingOwnerSnapshot()'));
      expect(
        visibleReads,
        contains('_requireRecordingOwnerSnapshotCurrent(ownerSnapshot)'),
      );
      expect(
        visibleReads,
        contains('(userId IS NULL OR userId = ?)'),
      );
      expect(visibleReads, isNot(contains('captureReviewed = 1')));
      expect(visibleReads, isNot(contains("read(key: 'token')")));
      expect(visibleReads, isNot(contains('_accountEmailFromToken')));
      expect(byId, contains('_captureRecordingOwnerSnapshot()'));
      expect(
        byId,
        contains('_getVisibleRecordingsForOwnerSnapshot('),
      );
      expect(byId, isNot(contains("read(key: 'token')")));
    });

    test('automatic cache pruning is pinned to one activated session', () {
      final String source =
          File('lib/database/src/database_repository.dart').readAsStringSync();
      final int start =
          source.indexOf('static Future<void> enforceMaxRecordings()');
      final int end =
          source.indexOf('static Future<Database> get database', start);
      final String method = source.substring(start, end);

      expect(method, contains('sessionProvider.capture()'));
      expect(method, contains('validateRecordingUploadSession(session)'));
      expect(method, contains('(r.userId IS NULL OR r.userId = ?)'));
      expect(
        RegExp(r'_requireRecordingSessionCurrent\(sessionProvider, session\)')
            .allMatches(method)
            .length,
        greaterThanOrEqualTo(4),
      );
      expect(method, isNot(contains("read(key: 'token')")));
      expect(method, isNot(contains('JwtDecoder.decode')));
    });

    test('all logout paths invalidate first and preserve session generation',
        () {
      for (final String path in <String>[
        'lib/user/userPage.dart',
        'lib/user/settingsPages/userInfo.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(source, contains('clearAllPreservingGeneration('));
        expect(source, isNot(contains('await secureStorage.deleteAll();')));
      }
    });

    test('auth logs do not print credential payloads', () {
      for (final String path in <String>[
        'lib/auth/authorizator.dart',
        'lib/auth/appleAuth.dart',
        'lib/auth/google_sign_in_service.dart',
        'lib/auth/login.dart',
        'lib/auth/registeration/cityReg.dart',
        'lib/auth/registeration/overview.dart',
        'lib/auth/registeration/mail.dart',
        'lib/auth/registeration/emailSent.dart',
        'lib/auth/unverifiedEmail.dart',
        'lib/auth/passReset/newPassword.dart',
        'lib/auth/passReset/forgottenPassword.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        for (final String forbidden in <String>[
          'Sign Up Request Body:',
          'Sign Up Response:',
          'returned data:',
          r'| ${response.data}',
          r'| ${data.toString()}',
          'logger.t(body)',
          'logger.t(response.data)',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '$path must not log secret authentication payloads.',
          );
        }
      }
    });
  });
}
