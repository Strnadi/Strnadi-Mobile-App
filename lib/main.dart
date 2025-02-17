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
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:strnadi/database/soundDatabase.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// Create a global logger instance.
final logger = Logger();

void _showMessage(String message) {
  var context;
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

Future<void> main() async {
  await SentryFlutter.init(
        (options) {
      options.dsn = 'https://b1b107368f3bf10b865ea99f191b2022@o4508834111291392.ingest.de.sentry.io/4508834113519696'; // Replace with your actual DSN.
      // Enable performance tracing by setting a sample rate (adjust as needed)
      options.tracesSampleRate = 1.0;
    },
    appRunner: () => runZonedGuarded(() {
      // Capture Flutter framework errors.
      FlutterError.onError = (FlutterErrorDetails details) {
        logger.e("Flutter error caught", details.exception, details.stack);
        Sentry.captureException(details.exception, stackTrace: details.stack);
      };

      runApp(const MyApp());
    }, (error, stackTrace) {
      logger.e("Unhandled error caught", error, stackTrace);
      Sentry.captureException(error, stackTrace: stackTrace);
    }),
  );
}

void checkInternetConnection() async {
  if (await hasInternetAccess()){
    logger.i("Has Internet access");
  }
  else {
    logger.e("Does not have internet access");
    _showMessage("Nemáte připojení k internetu aplikace nebude fungovat");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// Initialization method for side effects.
  /// For proper lifecycle management, consider using a StatefulWidget.
  void initialize() {
    requestLocationPermission();
    checkInternetConnection();
    checkIfDbExists();
    logger.i("Database has been created.");
  }

  /// Request location permissions and log the process.
  Future<bool> requestLocationPermission() async {
    LocationPermission permission;

    // Check if location services are enabled.
    if (!await Geolocator.isLocationServiceEnabled()) {
      logger.w('Location services are disabled.');
      return false;
    }

    // Check current permission status.
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Request permission if denied.
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        logger.w('Location permission denied.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      logger.w('Location permissions are permanently denied.');
      return false;
    }

    logger.i("Location permission granted.");
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Note: Calling initialization here is for demonstration.
    // For proper lifecycle management, use a StatefulWidget.
    initialize();

    return MaterialApp(
      title: 'Welcome to Flutter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          shape: const ContinuousRectangleBorder(),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Authorizator(login: Login(), register: RegMail()),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // Trigger the traced operation when the button is pressed.
                await executeTracedOperation();
              },
              child: const Text('Execute Traced Operation'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Starts a Sentry transaction and calls a traced function.
Future<void> executeTracedOperation() async {
  // Start a Sentry transaction named "processOrderBatch()" with the operation type "task".
  final transaction = Sentry.startTransaction('processOrderBatch()', 'task');

  try {
    // Process the order batch within the transaction.
    await processOrderBatch(transaction);
  } catch (exception, stackTrace) {
    // Record the exception on the transaction and mark it with an error status.
    transaction.throwable = exception;
    transaction.status = const SpanStatus.internalError();
    Sentry.captureException(exception, stackTrace: stackTrace);
  } finally {
    // Ensure the transaction is finished.
    await transaction.finish();
  }
}

/// Processes an order batch using a child span for detailed tracing.
Future<void> processOrderBatch(ISentrySpan span) async {
  // Start a child span with a description of the operation.
  final innerSpan = span.startChild('task', description: 'operation');

  try {
    // Simulate some work, e.g., processing orders.
    await Future.delayed(const Duration(seconds: 2));
    // Insert your operation logic here.
  } catch (exception, stackTrace) {
    // Record the exception on the inner span and mark it with an error status.
    innerSpan.throwable = exception;
    innerSpan.status = const SpanStatus.notFound();
    Sentry.captureException(exception, stackTrace: stackTrace);
  } finally {
    // Finish the child span.
    await innerSpan.finish();
  }
}