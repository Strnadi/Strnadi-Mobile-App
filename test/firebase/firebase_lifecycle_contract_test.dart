import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firebase lifecycle source contract (no API or DB)', () {
    test('background notification persistence is awaited and normalized', () {
      final String firebase =
          File('lib/firebase/firebase.dart').readAsStringSync();
      final String repository =
          File('lib/database/src/database_repository.dart').readAsStringSync();

      expect(
          firebase, contains('await DatabaseNew.insertNotification(message)'));
      expect(
        firebase,
        isNot(contains(
          'await _showLocalNotificationFromData(message.data);\n'
          '      return;',
        )),
      );
      expect(repository, contains('notificationPersistenceValues('));
      expect(
          repository, contains('notificationBody: message.notification?.body'));
      expect(repository, isNot(contains('int.parse(message.messageType!)')));
      expect(repository, isNot(contains("'receivedAt': message.sentTime")));
      expect(repository, isNot(contains("'body': message.data.toString()")));
    });

    test('refreshing a missing Firebase token is normalized by coordinator',
        () {
      final String firebase =
          File('lib/firebase/firebase.dart').readAsStringSync();
      final String registration =
          File('lib/firebase/device_session_registration.dart')
              .readAsStringSync();

      expect(firebase, isNot(contains('updateDevice(oldToken, newToken!)')));
      expect(
        registration,
        contains('_normalizeDeviceToken('),
      );
      expect(registration, contains('DeviceTokenSyncStatus.noCurrentToken'));
    });

    test('device cleanup invalidates the Firebase installation token', () {
      final String firebase =
          File('lib/firebase/firebase.dart').readAsStringSync();

      expect(
        firebase,
        contains(
          'invalidateFirebaseToken: FirebaseMessaging.instance.deleteToken',
        ),
      );
      expect(firebase, contains('clearUnboundLocalToken: () async'));
      expect(firebase, contains('key: _legacyDeviceTokenKey'));
    });

    test('all logout paths deregister before clearing secure storage', () {
      final String userPage = File('lib/user/userPage.dart').readAsStringSync();
      expect(userPage, contains('runOrderedLogoutCleanup('));
      expect(
        userPage,
        contains('deleteDeviceToken: strnadiFirebase.deleteToken'),
      );
      expect(
        RegExp(
          r'clearAuthSession:\s*\(\)\s*=>\s*'
          r'activatedAuthSessions\.clearAllPreservingGeneration\(',
        ).hasMatch(userPage),
        isTrue,
      );

      final String userInfo =
          File('lib/user/settingsPages/userInfo.dart').readAsStringSync();
      final RegExp orderedCleanup = RegExp(
        r'await strnadiFirebase\.deleteToken\(\);\s*'
        r'await activatedAuthSessions\.clearAllPreservingGeneration\(',
      );
      expect(
        orderedCleanup.allMatches(userInfo),
        isNot(isEmpty),
        reason:
            'Profile logout must deregister while auth and fcmToken still exist.',
      );
    });

    test('Firebase tests contain no real API host or SQLite opening', () {
      for (final File file in Directory('test/firebase')
          .listSync()
          .whereType<File>()
          .where((File file) => file.path.endsWith('_test.dart'))) {
        final String source = file.readAsStringSync();
        expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
        expect(source, isNot(contains(<String>['open', 'Database('].join())));
        expect(
          source,
          isNot(contains(<String>['DatabaseNew', 'database'].join('.'))),
        );
      }
    });
  });
}
