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
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/passReset/newPassword.dart';
import 'package:strnadi/auth/unverifiedEmail.dart';
import 'package:strnadi/updateChecker.dart';
import 'auth/emailVerificationResult/notSuccessVerify.dart';
import 'auth/emailVerificationResult/successVerify.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:strnadi/maintanance.dart';
import 'package:strnadi/config/config.dart'; // ensure Config and ServerHealth are in scope
import 'package:strnadi/database/databaseNew.dart';
import 'deep_link_handler.dart';
import 'package:strnadi/bootstrap/app_bootstrap.dart';
import 'package:strnadi/localization/localization.dart';

import 'privacy/tracking_consent.dart';

// Create a global logger instance.
final logger = Logger();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<_MyAppState> myAppKey = GlobalKey<_MyAppState>();

class UploadProgressBridge {
  static const String portName = 'upload_progress_port';
  static final UploadProgressBridge instance = UploadProgressBridge._();
  UploadProgressBridge._();

  ReceivePort? _port;

  void start() {
    // Ensure we always own the mapping
    try {
      IsolateNameServer.removePortNameMapping(portName);
    } catch (_) {}
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(_port!.sendPort, portName);

    _port!.listen((msg) {
      try {
        if (msg is List && msg.isNotEmpty) {
          final String kind = msg[0] as String;
          if (kind == 'update' && msg.length >= 4) {
            final int partId = msg[1] as int;
            final int sent = msg[2] as int;
            final int total = msg[3] as int;
            UploadProgressBus.update(partId, sent, total);
          } else if (kind == 'done' && msg.length >= 2) {
            final int partId = msg[1] as int;
            UploadProgressBus.markDone(partId);
          }
        }
      } catch (e) {
        logger.d('[UploadProgressBridge] error: $e');
      }
    });
    logger.d('[UploadProgressBridge] started and listening on $portName');
  }

  void stop() {
    try {
      _port?.close();
    } catch (_) {}
    try {
      IsolateNameServer.removePortNameMapping(portName);
    } catch (_) {}
    logger.d('[UploadProgressBridge] stopped');
  }
}

void _showMessage(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('Login')),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('auth.buttons.ok')),
        ),
      ],
    ),
  );
}

Future<void> _checkGooglePlayServices(BuildContext context) async {
  // Check only on Android devices.
  if (Platform.isAndroid) {
    final availability = await GoogleApiAvailability.instance
        .checkGooglePlayServicesAvailability();
    if (availability != GooglePlayServicesAvailability.success) {
      // Attempt to prompt the user to update/install Google Play Services.
      await GoogleApiAvailability.instance.makeGooglePlayServicesAvailable();
      // Re-check availability after attempting resolution.
      final newAvailability = await GoogleApiAvailability.instance
          .checkGooglePlayServicesAvailability();
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
    WidgetsFlutterBinding.ensureInitialized();
    // Register global upload progress bridge so background isolates can report to UI
    UploadProgressBridge.instance.start();

    await AppBootstrap.initializeBeforeConsent();

    // 4) Handle tracking consent before finishing app bootstrap
    final trackingAuthorized =
        await TrackingConsentManager.ensureTrackingConsent();

    // 5) Continue with app bootstrap directly
    await _continueBootstrap(trackingAuthorized: trackingAuthorized);
  }, (error, stack) {
    if (TrackingConsentManager.isAuthorized) {
      Sentry.captureException(error, stackTrace: stack);
    }
  });
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
      final trackingAuthorized =
          await TrackingConsentManager.ensureTrackingConsent();
      await _continueBootstrap(trackingAuthorized: trackingAuthorized);
    }
    setState(() {}); // rebuild UI based on _granted
  }

  @override
  Widget build(BuildContext context) {
    return _granted
        ? const SizedBox
            .shrink() // bude ihned nahrazeno runApp(MyApp) ve _continueBootstrap
        : const PermissionScreen();
  }
}

Future<void> _continueBootstrap({required bool trackingAuthorized}) async {
  await AppBootstrap.initializeRuntimeServices();

  DeepLinkHandler().setNavigatorKey(navigatorKey);

  Future<void> runAppBootstrap() async {
    // Check server health before app initialization
    final health = await Config.checkServerHealth();
    if (health == ServerHealth.maintenance) {
      runApp(MaterialApp(home: const MaintenancePage()));
      return;
    }

    await AppBootstrap.initializeDatabase(logger);
    AppBootstrap.initializeNotifications();

    runApp(MyApp(key: myAppKey));

    // Initialize deep links after the first frame so the Navigator exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkHandler().initialize();
    });
  }

  await AppBootstrap.runWithTelemetry(
    trackingAuthorized: trackingAuthorized,
    logger: logger,
    appRunner: runAppBootstrap,
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Config.onHostEnvironmentChanged = refreshBadge;
    TrackingConsentManager.ensureObserver();
    unawaited(TrackingConsentManager.captureEvent('app_opened', properties: {
      'environment': Config.hostEnvironment.name,
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Config.onHostEnvironmentChanged == refreshBadge) {
      Config.onHostEnvironmentChanged = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // When the app returns to foreground, reconcile any stale sending flags
      DatabaseNew.checkSendingRecordings();
    }
  }

  bool debugBadge = Config.hostEnvironment == HostEnvironment.dev;

  void refreshBadge() {
    setState(() => debugBadge = Config.hostEnvironment == HostEnvironment.dev);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: (debugBadge),
      title: 'Strnadi',
      navigatorKey: navigatorKey,
      navigatorObservers: TrackingConsentManager.navigatorObservers,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.blue,
          secondary: const Color(0xFF2D2B18),
        ),
        fontFamily: 'Bricolage Grotesque',
      ),
      home: Authorizator(),
      onGenerateRoute: (settings) {
        final name = settings.name ?? '';
        switch (name) {
          case '/ucet/email-neoveren':
            return MaterialPageRoute(
              settings: const RouteSettings(name: '/email-not-verified'),
              builder: (_) => EmailVerificationFailed(),
            );
          case '/ucet/email-overen':
            return MaterialPageRoute(
              settings: const RouteSettings(name: '/email-verified'),
              builder: (_) => EmailVerified(),
            );
          case '/ucet/obnova-hesla':
            final args = settings.arguments as Map<String, dynamic>?;
            final token = args?['token'] as String? ?? '';
            return MaterialPageRoute(
              settings: const RouteSettings(name: '/reset-password'),
              builder: (_) => ChangePassword(jwt: token),
            );
          default:
            return null; // fall through to routes/onUnknownRoute
        }
      },
      onUnknownRoute: (settings) =>
          MaterialPageRoute(builder: (_) => Authorizator()),
      routes: {
        '/authorizator': (context) => Authorizator(),
        '/reset-password': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
              as Map<String, dynamic>?;
          final token = args?['token'] ?? '';
          return ChangePassword(jwt: token);
        },
        '/email-not-verified': (context) => EmailVerificationFailed(),
        '/email-verified': (context) => EmailVerified(),
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
      appBar: null,
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
          t('Aplikace potřebuje povolení k mikrofonu a notifikacím.\n'
              'Prosím povolte je v nastavení a spusťte Strnadi znovu.'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
