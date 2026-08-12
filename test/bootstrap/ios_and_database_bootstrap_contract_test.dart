import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS cold-start and privacy contracts', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final project =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

    test('a cold-start link cannot bypass background and Flutter setup', () {
      final workmanager = appDelegate.indexOf(
        'WorkmanagerPlugin.setPluginRegistrantCallback(registerPlugins)',
      );
      final flutterLaunch = appDelegate.indexOf(
        'let didFinishLaunching = super.application(',
      );
      final linkForward = appDelegate.indexOf(
        'ColdStartLinkForwarder.forward(',
      );
      final launchReturn = appDelegate.indexOf(
        'return didFinishLaunching',
        linkForward,
      );

      expect(workmanager, greaterThanOrEqualTo(0));
      expect(flutterLaunch, greaterThan(workmanager));
      expect(linkForward, greaterThan(flutterLaunch));
      expect(launchReturn, greaterThan(linkForward));

      final didFinishBody =
          appDelegate.substring(workmanager, launchReturn + 26);
      expect(didFinishBody, isNot(contains('return true')));
    });

    test('cold-start link forwarding has a native fake-driven unit test', () {
      final helper =
          File('ios/Runner/ColdStartLinkForwarder.swift').readAsStringSync();
      final nativeTests =
          File('ios/RunnerTests/RunnerTests.swift').readAsStringSync();

      expect(helper, contains('guard let url else'));
      expect(helper, contains('handler(url)'));
      expect(nativeTests,
          contains('testColdStartLinkForwarderForwardsExactlyOnce'));
      expect(
          nativeTests, contains('testColdStartLinkForwarderIgnoresMissingURL'));
    });

    test('Firebase uses delegate swizzling when no manual APNs bridge exists',
        () {
      expect(infoPlist, isNot(contains('FirebaseAppDelegateProxyEnabled')));
      expect(
        appDelegate,
        isNot(contains('didRegisterForRemoteNotificationsWithDeviceToken')),
      );
      expect(
        appDelegate,
        isNot(contains('didFailToRegisterForRemoteNotificationsWithError')),
      );
      expect(appDelegate, isNot(contains('Messaging.messaging().apnsToken')));
    });

    test('production Info.plist has no insecure transport exception', () {
      expect(infoPlist, isNot(contains('NSExceptionAllowsInsecureHTTPLoads')));
      expect(infoPlist, isNot(contains('NSAllowsArbitraryLoads')));
      expect(infoPlist, isNot(contains('NSExceptionDomains')));
    });

    test('all permission descriptions are localized in English, Czech, German',
        () {
      const requiredKeys = <String>[
        'NSCameraUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSUserNotificationUsageDescription',
        'NSUserTrackingUsageDescription',
      ];

      for (final language in <String>['en', 'cs', 'de']) {
        final strings = File(
          'ios/Runner/$language.lproj/InfoPlist.strings',
        ).readAsStringSync();
        for (final key in requiredKeys) {
          expect(
            RegExp('^"$key" = ".+";\$', multiLine: true).hasMatch(strings),
            isTrue,
            reason: '$language is missing $key',
          );
        }
      }

      expect(project, contains('InfoPlist.strings in Resources'));
      expect(project, contains('en.lproj/InfoPlist.strings'));
      expect(project, contains('cs.lproj/InfoPlist.strings'));
      expect(project, contains('de.lproj/InfoPlist.strings'));
      expect(project, contains('ColdStartLinkForwarder.swift in Sources'));
    });
  });

  group('database bootstrap source contracts', () {
    final bootstrap =
        File('lib/bootstrap/app_bootstrap.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    test('production adapter delegates every database phase and rethrows', () {
      final start = bootstrap.indexOf(
        'static Future<void> initializeDatabase(Logger logger)',
      );
      final end = bootstrap.indexOf(
        'static Future<void> initializeNotifications',
        start,
      );
      final method = bootstrap.substring(start, end);

      expect(method, contains('await runDatabaseBootstrap('));
      expect(method, contains('await DatabaseNew.initDb();'));
      expect(method, contains('DatabaseNew.runPostMigrationBackfills'));
      expect(method, contains('DatabaseNew.enforceMaxRecordings'));
      expect(method, contains('DatabaseNew.checkSendingRecordings'));
      expect(method, contains('rethrow;'));
    });

    test('normal app and notifications launch only after database succeeds',
        () {
      final start = main.indexOf('Future<void> runAppBootstrap() async');
      final end = main.indexOf(
        'await AppBootstrap.runWithTelemetry(',
        start,
      );
      final method = main.substring(start, end);
      final database = method.indexOf(
        'await AppBootstrap.initializeDatabase(logger)',
      );
      final notifications = method.indexOf(
        'await AppBootstrap.initializeNotifications(logger)',
      );
      final normalApp = method.indexOf('runApp(MyApp(key: _myAppKey))');
      final errorApp = method.indexOf('DatabaseBootstrapErrorApp(');

      expect(database, greaterThanOrEqualTo(0));
      expect(notifications, greaterThan(database));
      expect(normalApp, greaterThan(notifications));
      expect(method, contains('try {'));
      expect(method, contains('catch (error, stackTrace)'));
      expect(errorApp, greaterThan(normalApp));
      expect(method, contains('onRetry: launchDatabaseBackedApp'));
    });

    test('bootstrap test files cannot open a real API or database', () {
      final testSources = Directory('test/bootstrap')
          .listSync()
          .whereType<File>()
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(testSources, isNot(contains(<String>['D', 'io('].join())));
      expect(testSources, isNot(contains(<String>['ht', 'tp.'].join())));
      expect(testSources, isNot(contains(<String>['sq', 'flite'].join())));
      expect(
        testSources,
        isNot(contains(<String>['DatabaseNew', 'database'].join('.'))),
      );
      expect(
        testSources,
        isNot(contains(<String>['open', 'Database('].join())),
      );
    });

    test('database error translations exist in every app language', () {
      for (final language in <String>['en', 'cs', 'de']) {
        final root = jsonDecode(
          File('assets/lang/$language.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        final bootstrap = root['bootstrap'] as Map<String, dynamic>;
        final error = bootstrap['databaseError'] as Map<String, dynamic>;

        expect(error['title'],
            isA<String>().having((v) => v, 'title', isNotEmpty));
        expect(
          error['message'],
          isA<String>().having((v) => v, 'message', isNotEmpty),
        );
        expect(error['retry'],
            isA<String>().having((v) => v, 'retry', isNotEmpty));
      }
    });
  });
}
