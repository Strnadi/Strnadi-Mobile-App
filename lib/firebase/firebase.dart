import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:logger/logger.dart';

final logger = Logger();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

void initFirebase() async {
  // Initialize Firebase.

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background message handler.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}

void initLocalNotifications() {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final String? payload = response.payload;
      // Handle notification tap here. For example, navigate to a specific screen:
      if (payload != null) {
        // Navigator.push(...);
      }
    },
  );
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  RemoteNotification? notification = message.notification;
  AndroidNotification? android = message.notification?.android;

  if (notification != null && android != null) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'your_channel_id', // Set a unique channel id
      'your_channel_name', // Set a human-readable channel name
      channelDescription: 'your_channel_description',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformChannelSpecifics,
      payload: 'your_payload_data', // Optional payload to handle taps.
    );
  }
}


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if necessary.
  await Firebase.initializeApp();
  logger.i("Handling a background message: ${message.messageId}");
  // You can process the message data here (for example, save it locally or update your UI state).
}

void initFirebaseMessaging() {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permissions (required for iOS).
  messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  ).then((NotificationSettings settings) {
    logger.i("User granted permission: ${settings.authorizationStatus}");
  });

  // Retrieve and log the FCM token.
  messaging.getToken().then((token) {
    logger.i("Firebase token: $token");
    // TODO: Send the token to your server if needed.
  });

  // Listen for token refresh.
  messaging.onTokenRefresh.listen((newToken) {
    logger.i("Firebase token refreshed: $newToken");
    // TODO: Send the new token to your server if necessary.
  });

  // Listen for foreground messages.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    logger.i("Received a foreground message: ${message.messageId}");
    if (message.notification != null) {
      logger.i("Message contains notification: ${message.notification}");
      _showLocalNotification(message);
    }
  });

  // Listen for when the app is opened from a terminated or background state via a notification.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    logger.i("Notification caused app to open: ${message.messageId}");
    // Handle navigation or state update if needed.
  });
}