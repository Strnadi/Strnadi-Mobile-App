import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Firebase production wiring contract (source only)', () {
    late String firebase;
    late String controller;
    late String bootstrap;
    late String mainSource;

    setUpAll(() {
      firebase = File('lib/firebase/firebase.dart').readAsStringSync();
      controller =
          File('lib/api/controllers/device_controller.dart').readAsStringSync();
      bootstrap = File('lib/bootstrap/app_bootstrap.dart').readAsStringSync();
      mainSource = File('lib/main.dart').readAsStringSync();
    });

    test('foreground pushes use one awaited display-and-persist helper', () {
      expect(firebase, contains('deliverForegroundNotification('));
      expect(firebase, contains('display: () => _displayForegroundMessage'));
      expect(
        firebase,
        contains('persist: () => DatabaseNew.insertNotification(message)'),
      );
      expect(
        firebase,
        contains('unawaited(_handleForegroundMessage(message))'),
      );
      expect(
        firebase,
        isNot(contains('unawaited(_showLocalNotification(message))')),
      );
    });

    test('all initialization calls are awaited and ordered', () {
      expect(firebase, contains('Future<void> initFirebase()'));
      expect(bootstrap, contains('await initFirebase();'));
      expect(
        bootstrap,
        contains('await initializeNotificationRuntime('),
      );
      expect(
        mainSource,
        contains('await AppBootstrap.initializeNotifications(logger);'),
      );
      expect(
        bootstrap,
        isNot(contains('unawaited(initFirebaseMessaging())')),
      );
      expect(
        bootstrap,
        isNot(contains('unawaited(initLocalNotifications())')),
      );
    });

    test('device registration has no logged-out or user-id polling loops', () {
      expect(firebase, isNot(contains('while (!(await auth.isLoggedIn()')));
      expect(firebase, isNot(contains('while (userIdS == null)')));
      expect(
          firebase, isNot(contains('Future.delayed(Duration(seconds: 10))')));
      expect(firebase, contains('activatedAuthSessions.capture()'));
      expect(firebase, contains('session == null || !session.verified'));
    });

    test('remote calls use captured auth, host, user, session, and environment',
        () {
      expect(firebase, contains('DeviceRegistrationScope('));
      expect(firebase, contains('sessionId: session.sessionId'));
      expect(firebase, contains('accessToken: session.accessToken'));
      expect(firebase, contains('environment: Config.hostEnvironment.name'));
      expect(firebase, contains('apiHost: Config.host'));
      expect(firebase, contains("host: scope.apiHost"));
      expect(firebase, contains("accessToken: scope.accessToken"));
      expect(firebase, contains("'userId': scope.userId"));
      expect(controller, contains("'Authorization': 'Bearer \$accessToken'"));
      expect(controller, contains('followRedirects: false'));
    });

    test('token refresh trusts only the scoped binding and shared coordinator',
        () {
      expect(firebase, contains("const String _deviceTokenBindingKey"));
      expect(firebase, contains('DeviceTokenSessionCoordinator('));
      expect(
        firebase,
        contains('currentTokenOverride: newToken'),
      );
      expect(
        firebase,
        isNot(contains(
          "String? oldToken = await FlutterSecureStorage().read("
          "key: 'fcmToken')",
        )),
      );
    });

    test('logout cleanup is serialized and uses the binding original host', () {
      expect(firebase, contains('cleanUpCurrentSession('));
      expect(firebase, contains('host: binding.apiHost'));
      expect(
        firebase,
        contains(
            'invalidateFirebaseToken: FirebaseMessaging.instance.deleteToken'),
      );
    });
  });
}
