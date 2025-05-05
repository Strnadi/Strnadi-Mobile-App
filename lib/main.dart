/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:strnadi/auth/passReset/newPassword.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';
import 'package:strnadi/updateChecker.dart';
import 'firebase/firebase.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:strnadi/maintanance.dart';
import 'package:strnadi/config/config.dart'; // ensure Config and ServerHealth are in scope
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/callback_dispatcher.dart';
import 'package:workmanager/workmanager.dart';
import 'deep_link_handler.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

// Create a global logger instance.
final logger = Logger();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void _showMessage(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Login'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<void> _checkGooglePlayServices(BuildContext context) async {
  // Check only on Android devices.
  if (Platform.isAndroid) {
    final availability =
        await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability();
    if (availability != GooglePlayServicesAvailability.success) {
      // Attempt to prompt the user to update/install Google Play Services.
      await GoogleApiAvailability.instance.makeGooglePlayServicesAvailable();
      // Re-check availability after attempting resolution.
      final newAvailability =
          await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability();
      if (newAvailability != GooglePlayServicesAvailability.success) {
        _showMessage(
          context,
          'Google Play Services are required for this app to function properly.',
        );
      }
    }
  }
}

void main() {
  runZonedGuarded(() async {
    await _bootstrap();
  }, (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Firebase jako první
  await Firebase.initializeApp();

  // 3) Foreground‑task
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

  // 2) Spusť UI s kontrolou povolení
  runApp(const PermissionGate());
  return; // zbytek se spustí až po udělení povolení
}
// PermissionGate widget – controls runtime permissions and continues app bootstrap
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  Future<void> _request() async {
    final mic = await perm.Permission.microphone.request();
    final notif = await perm.Permission.notification.request();
    _granted = mic.isGranted && notif.isGranted;
    if (_granted) {
      await _continueBootstrap();
    }
    setState(() {}); // rebuild UI based on _granted
  }

  @override
  Widget build(BuildContext context) {
    return _granted
        ? const SizedBox.shrink() // bude ihned nahrazeno runApp(MyApp) ve _continueBootstrap
        : const PermissionScreen();
  }
}

Future<void> _continueBootstrap() async {
  // 4) Ostatní inicializace
  await Config.loadConfig();
  await Config.loadFirebaseConfig();
  initFirebase();

  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  DeepLinkHandler().setNavigatorKey(navigatorKey);

  await SentryFlutter.init(
    (options) {
      options
        ..dsn =
            'https://b1b107368f3bf10b865ea99f191b2022@o4508834111291392.ingest.de.sentry.io/4508834113519696'
        ..addIntegration(LoggingIntegration())
        ..profilesSampleRate = 1.0
        ..tracesSampleRate = 1.0
        ..experimental.replay.sessionSampleRate = 1.0
        ..experimental.replay.onErrorSampleRate = 1.0
        ..environment = kDebugMode ? 'development' : 'production';
    },
    appRunner: () async {
      // Check server health before app initialization
      final health = await Config.checkServerHealth();
      if (health == ServerHealth.maintenance) {
        runApp(MaterialApp(home: const MaintenancePage()));
        return;
      }

      // Initialize your database and other services.
      logger.i('Loading database');
      try {
        await DatabaseNew.database.timeout(const Duration(seconds: 10));
      } catch (e, stack) {
        logger.e('Error initializing database: $e', error: e, stackTrace: stack);
      }
      logger.i('Loaded Database');

      // Init Firebase messaging + lokální notifikace
      initFirebaseMessaging();
      initLocalNotifications();

      // Deep‑linky
      DeepLinkHandler().initialize();

      runApp(const MyApp());
    },
  );
  return;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Strnadi',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.blue,
          secondary: const Color(0xFF2D2B18),
        ),
        fontFamily: 'Bricolage Grotesque',
      ),
      home: const HomeScreen(),
      routes: {
        '/authorizator': (context) => Authorizator(),
        '/reset-password': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
          final token = args?['token'] ?? '';
          return ChangePassword(jwt: token);
        },
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Defer the check until after the first frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await checkForUpdate(context);
      await _checkGooglePlayServices(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            settings: const RouteSettings(name: '/authorizator'),
            builder: (context) => Authorizator(),
          );
        },
      ),
    );
  }
}

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Aplikace potřebuje povolení k mikrofonu a notifikacím.\n'
          'Prosím povolte je v nastavení a spusťte Strnadi znovu.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
