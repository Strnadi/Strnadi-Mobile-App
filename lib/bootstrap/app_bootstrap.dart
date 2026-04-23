import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';
import 'package:strnadi/callback_dispatcher.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/firebase/firebase.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:workmanager/workmanager.dart';

class AppBootstrap {
  AppBootstrap._();

  static bool _configLoaded = false;

  static Future<void> initializeBeforeConsent() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    await ensureConfigLoaded();
    unawaited(DynamicIcon.refreshAllDialects());
    _initializeWorkmanager();
    await Localization.load(null);
    _initializeForegroundTask();
  }

  static Future<void> initializeRuntimeServices() async {
    await ensureConfigLoaded();
    initFirebase();
  }

  static Future<void> initializeDatabase(Logger logger) async {
    logger.i('Loading database');
    try {
      await DatabaseNew.initDb();
      await DatabaseNew.runPostMigrationBackfills();
      await DatabaseNew.enforceMaxRecordings();
      await DatabaseNew.checkSendingRecordings();
    } catch (e, stack) {
      logger.e('Error initializing database: $e', error: e, stackTrace: stack);
    }
    logger.i('Loaded Database');
  }

  static void initializeNotifications() {
    initFirebaseMessaging();
    initLocalNotifications();
  }

  static Future<void> runWithTelemetry({
    required bool trackingAuthorized,
    required Future<void> Function() appRunner,
    required Logger logger,
  }) async {
    if (!trackingAuthorized) {
      logger.i('Tracking consent denied - starting without Sentry telemetry.');
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options
          ..dsn =
              'https://b1b107368f3bf10b865ea99f191b2022@o4508834111291392.ingest.de.sentry.io/4508834113519696'
          ..addIntegration(LoggingIntegration())
          ..profilesSampleRate = 1.0
          ..tracesSampleRate = 1.0
          ..replay.sessionSampleRate = 1.0
          ..replay.onErrorSampleRate = 1.0
          ..environment = kDebugMode ? 'development' : 'production';
      },
      appRunner: appRunner,
    );
  }

  static Future<void> ensureConfigLoaded() async {
    if (_configLoaded) return;
    await Config.loadConfig();
    await Config.loadFirebaseConfig();
    _configLoaded = true;
  }

  static void _initializeWorkmanager() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static void _initializeForegroundTask() {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'strnadi_hlavni_sluzba',
        channelName: 'Strnadi – služba na pozadí',
        channelDescription:
            'Trvalá notifikace služby Strnadi, která zajišťuje chod aplikace i při běhu na pozadí.',
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(600000),
        autoRunOnBoot: true,
        allowWakeLock: true,
      ),
    );
  }
}
