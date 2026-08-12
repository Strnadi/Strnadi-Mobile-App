import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';
import 'package:strnadi/bootstrap/database_bootstrap.dart';
import 'package:strnadi/callback_dispatcher.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/firebase/firebase.dart';
import 'package:strnadi/firebase/firebase_runtime_initialization.dart';
import 'package:strnadi/firebase/local_notifications.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/recording/recording_foreground_service.dart';
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
    await _initializeForegroundTask();
  }

  static Future<void> initializeRuntimeServices() async {
    await ensureConfigLoaded();
    await initFirebase();
  }

  static Future<void> initializeDatabase(Logger logger) async {
    logger.i('Loading database');
    try {
      await runDatabaseBootstrap(
        openDatabase: () async {
          await DatabaseNew.initDb();
        },
        runPostMigrationBackfills: DatabaseNew.runPostMigrationBackfills,
        enforceRecordingLimit: DatabaseNew.enforceMaxRecordings,
        reconcileInterruptedUploads: DatabaseNew.checkSendingRecordings,
      );
    } catch (error, stackTrace) {
      logger.e(
        'Error initializing database.',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    logger.i('Loaded Database');
  }

  static Future<void> initializeNotifications(Logger logger) async {
    final NotificationRuntimeInitializationResult result =
        await initializeNotificationRuntime(
      initializeLocalNotifications: initLocalNotifications,
      initializeMessaging: initFirebaseMessaging,
    );
    if (result.localNotificationsError != null) {
      logger.w(
        'Local notification initialization failed.',
        error: result.localNotificationsError,
      );
    }
    if (result.messagingError != null) {
      logger.w(
        'Firebase messaging initialization failed.',
        error: result.messagingError,
      );
    }
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
          // Sentry currently exposes profiling behind an experimental API.
          // ignore: experimental_member_use
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
    _configLoaded = true;
  }

  static void _initializeWorkmanager() {
    Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> _initializeForegroundTask() async {
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
        // Audio capture lives in the app isolate and cannot survive process
        // death. Restarting this service on boot would therefore show a stale
        // recording notification without recording any audio.
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );

    try {
      // A previous build used a sticky service. Reconcile it before any app UI
      // is shown so an orphaned paused notification cannot survive relaunch.
      await reconcileStaleRecordingForegroundService(
        service: const FlutterRecordingForegroundService(),
      );
    } catch (error) {
      // Foreground-service cleanup must not make the entire app unlaunchable.
      // Recorder entry and task startup both retry the same reconciliation.
      debugPrint(
        'Failed to reconcile stale recording foreground service: $error',
      );
    }
  }
}
