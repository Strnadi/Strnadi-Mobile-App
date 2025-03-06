import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';


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

Future<DeviceInfo> getDeviceInfo() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String platform;
  String deviceModel;

  if (Platform.isAndroid) {
    platform = "Android";
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    deviceModel = androidInfo.model; // e.g., "Pixel 5"
  } else if (Platform.isIOS) {
    platform = "ios";
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    deviceModel = iosInfo.utsname.machine; // e.g., "iPhone14,2"
  } else {
    platform = "Unknown";
    deviceModel = "Unknown";
  }

  return DeviceInfo(platform: platform, deviceModel: deviceModel);
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if necessary.
  await Firebase.initializeApp();
  logger.i("Handling a background message: ${message.messageId}");
  // You can process the message data here (for example, save it locally or update your UI state).
}

Future<void> initFirebaseMessaging() async{
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
  messaging.getToken().then((token) async {
    logger.i("Firebase token: $token");

    Uri url = Uri.https('api.strnadi.cz', '/devices/device');

    try {
      DeviceInfo deviceInfo = await getDeviceInfo();
      
      while (FlutterSecureStorage().read(key: 'token') == null) {
        await Future.delayed(Duration(seconds: 1));
      }

      String? jwt = await const FlutterSecureStorage().read(key: 'token');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'newToken': token,
          'oldToken': null,
          'platform': deviceInfo.platform,
          'DeviceName' : deviceInfo.deviceModel
        }),
      );
      if (response.statusCode==200){
        logger.i('Token sent to server');
        FlutterSecureStorage().write(key: 'fcmToken', value: token);
      }
      else {
        logger.e('Failed to send token to server ${response.statusCode}');
      }
    }
    catch (error) {
      logger.e(error);
    }
  });

  // Listen for token refresh.
  messaging.onTokenRefresh.listen((newToken) async{

    String? oldToken = await FlutterSecureStorage().read(key: 'fcmToken');

    if (newToken == oldToken) return;

    logger.i("Firebase token refreshed: $newToken");
    Uri url = Uri.https('api.strnadi.cz', '/devices/device');

    try {
      String? jwt = await FlutterSecureStorage().read(key: 'token');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'newToken': newToken,
          'oldToken': oldToken
        }),
      );
      if (response.statusCode == 200){
        logger.i('Token refreshed');
      }
      else {
        logger.e('Failed to refresh token ${response.statusCode}');
      }
    }
    catch (error) {
      logger.e(error);
    }
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

void deleteToken() async{
  FirebaseMessaging.instance.deleteToken();

  String? oldToken = await FlutterSecureStorage().read(key: 'fcmToken');
  String? jwt = await FlutterSecureStorage().read(key: 'token');

  Uri uri = Uri.https('api.strnadi.cz', '/devices/device');

  try{
    final response = await http.post(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt'
    }, body: jsonEncode({
      'newToken': null,
      'oldToken': oldToken
    }));
    if (response.statusCode == 200){
      logger.i('Token deleted');
    }
    else{
      logger.e('Failed to delete token ${response.statusCode}');
    }
  }
  catch (error){
    logger.e(error);
  }

  FlutterSecureStorage().delete(key: 'fcmToken');
}