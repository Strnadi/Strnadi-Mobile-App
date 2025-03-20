/*
 * Copyright (C) 2024 Marian Pecqueur && Jan Drobílek
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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_logging/sentry_logging.dart';
import 'package:strnadi/updateChecker.dart';
import 'firebase/firebase.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/callback_dispatcher.dart';
import 'package:workmanager/workmanager.dart';

// Create a global logger instance.
final logger = Logger();


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

Future<bool> hasInternetAccess() async {
  try {
    final result = await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException catch (_) {
    return false;
  }
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


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Config.loadConfig();

  await Config.loadFirebaseConfig();

  initFirebase();

  // Initialize workmanager with our callback.
  Workmanager().initialize(
    callbackDispatcher, // The top-level function
    isInDebugMode: false, // Set this to false for production
  );

  await SentryFlutter.init(
        (options) {
      options.dsn =
      'https://b1b107368f3bf10b865ea99f191b2022@o4508834111291392.ingest.de.sentry.io/4508834113519696';
      options.addIntegration(LoggingIntegration());
      options.profilesSampleRate = 1.0;
      options.tracesSampleRate = 1.0;
      options.experimental.replay.sessionSampleRate = 1.0;
      options.experimental.replay.onErrorSampleRate = 1.0;
      options.environment = kDebugMode? 'development' : 'production';
    },
    appRunner: () async{
      // Initialize your database and other services.
      logger.i('Loading database');
      await DatabaseNew.database;
      logger.i('Loaded Database');
      // Initialize Firebase Messaging.
      initFirebaseMessaging();
      // Initialize Firebase Local Messaging
      initLocalNotifications();
      // Run the app.
      runApp(const MyApp());
    },
  );
}

Future<void> checkInternetConnection(BuildContext context) async {
  if (await hasInternetAccess()) {
    logger.i("Has Internet access");
  } else {
    logger.e("Does not have internet access");
    _showMessage(
        context, "Nemáte připojení k internetu aplikace nebude fungovat");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Defer the check until after the first frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) async{
      await checkForUpdate(context);
      await _checkGooglePlayServices(context);
      await checkInternetConnection(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      // Directly include Authorizator which now returns a complete screen.
      body: Authorizator(login: const Login(), register: const RegMail()),
    );
  }
}
