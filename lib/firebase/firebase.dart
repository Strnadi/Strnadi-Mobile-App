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
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import '../config/config.dart';
import '../firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';
import 'package:strnadi/auth/authorizator.dart' as auth;
import 'package:jwt_decoder/jwt_decoder.dart';

final logger = Logger();

bool adding = false;

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
      'com.delta.strnadi', // Set a unique channel id
      'Strnadi', // Set a human-readable channel name
      channelDescription: 'Aplikace Strnadi',
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
      //payload: 'your_payload_data', // Optional payload to handle taps.
    );
  }
}

Future<void> _showLocalNotificationFromData(Map<String, dynamic> data) async {
  try {
    final String? langPref = (await Config.getLanguagePreference()).toString();
    final String lang = (langPref == null || langPref.isEmpty) ? 'en' : langPref;
    final Map<String, dynamic> lower = _toLowercaseKeys(data);


    final String? title = lower['title$lang']?.toString();
    final String? body = lower['body$lang']?.toString();
    logger.i('Got notification with data: $lower');
    if (title == null && body == null) {
      logger.w("No title/body for lang $lang in data; skipping");
      return;
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'com.delta.strnadi',
      'Strnadi',
      channelDescription: 'Aplikace Strnadi',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      platformChannelSpecifics,
    );
  } catch (e, st) {
    logger.e("Failed to show local notification from data", error: e, stackTrace: st);
  }
}

Map<String, dynamic> _toLowercaseKeys(Map<String, dynamic> data) {
  final Map<String, dynamic> lowercased = {};
  data.forEach((key, value) {
    if (value is Map<String, dynamic>) {
      lowercased[key.toLowerCase()] = _toLowercaseKeys(value);
    } else {
      lowercased[key.toLowerCase()] = value;
    }
  });
  return lowercased;
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
  if (message.data.isNotEmpty) {
    final hasLocalizedKeys = message.data.containsKey('titleEn') ||
        message.data.containsKey('bodyEn') ||
        message.data.containsKey('titleDe') ||
        message.data.containsKey('bodyDe') ||
        message.data.containsKey('titleCs') ||
        message.data.containsKey('bodyCs');
    if (hasLocalizedKeys) {
      await _showLocalNotificationFromData(message.data);
      // TODO save notification if needed with your own model
      return;
    }
  }
  // TODO save notification
  DatabaseNew.insertNotification(message);
}

Future<void> addDevice() async{
  if(adding) return;
  adding = true;

  while(!(await auth.isLoggedIn()==auth.AuthStatus.loggedIn)){
    await Future.delayed(Duration(seconds: 10));
  }

  try {
    FlutterSecureStorage secureStorage = FlutterSecureStorage();
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    String? token = await messaging.getToken();
    logger.i("Firebase token: $token");

    Uri url = Uri.https(Config.host, '/devices/add');
    DeviceInfo deviceInfo = await getDeviceInfo();
    String? jwt = await secureStorage.read(key: 'token');
    logger.i('JWT Token: $jwt SENDING NEW TOKEN TO SERVER');
    String? userIdS = await secureStorage.read(key: 'userId');
    while(userIdS ==  null){
      await Future.delayed(Duration(seconds: 1));
      userIdS = await secureStorage.read(key: 'userId');
    }
    int userId = int.parse(userIdS);
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'fcmToken': token,
        'devicePlatform': deviceInfo.platform,
        'deviceModel': deviceInfo.deviceModel,
        'userId': userId
      }),
    );
    if (response.statusCode == 200) {
      logger.i('Device added');
      FlutterSecureStorage().write(key: 'fcmToken', value: token);
      adding = false;
    }
    else {
      adding = false;
      logger.e('Failed to add device ${response.statusCode} | ${response.body}');
    }
  } catch(e, stackTrace){
    adding = false;
    logger.e(e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
  }
}

Future<void> updateDevice(String? oldToken, String? newToken) async{
  if(oldToken == null){
    logger.e('Old token is null sending new token');
    await addDevice();
    return;
  }
  if(newToken == null){
    logger.e('New token is null deleting token');
    deleteToken();
  }

  Uri url = Uri.https(Config.host, '/devices/update');

  try {
    String? jwt = await const FlutterSecureStorage().read(key: 'token');
    logger.i('JWT Token: $jwt SENDING NEW TOKEN TO SERVER');
    final response = await http.patch(url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
        body: jsonEncode({
          'newFCMToken': newToken,
          'oldFCMToken': oldToken
        })
    );
    if(response.statusCode == 200){
      logger.i('Device updated');
      FlutterSecureStorage().write(key: 'fcmToken', value: newToken);
    }
    else{
      logger.e('Failed to update device ${response.statusCode} | ${response.body}');
    }
  }
  catch(e, stackTrace){
    logger.e(e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
  }
}

Future<void> deleteToken()async{

  String? token = await FlutterSecureStorage().read(key: 'fcmToken');
  Uri uri = Uri.https(Config.host, '/devices/delete/$token');

  if(token == null){
    logger.i('No token to delete');
    return;
  }

  try{
    String? jwt = await FlutterSecureStorage().read(key: 'token');
    final response = await http.delete(uri, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt'
    });
    if (response.statusCode == 200){
      logger.i('Token deleted');
      FlutterSecureStorage().delete(key: 'fcmToken');
    }
    else{
      logger.e('Failed to delete token ${response.statusCode} | ${response.body}');

    }
  }
  catch (error) {
    logger.e(error);
    Sentry.captureException(error);
  }
}

Future<void> refreshToken() async{
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? oldToken = await FlutterSecureStorage().read(key: 'fcmToken');
  if(oldToken == null){
    await addDevice();
  }
  else{
    String? newToken = await messaging.getToken();
    if(newToken != oldToken){
      await updateDevice(oldToken, newToken!);
    }
    logger.i('Firebase token $newToken');
  }
}

Future<void> initFirebaseMessaging() async{
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permissions (required for iOS).
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  ).then((NotificationSettings settings) {
    logger.i("User granted permission: ${settings.authorizationStatus}");
  });

  FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  await refreshToken();

  // Listen for token refresh.
  messaging.onTokenRefresh.listen((newToken) async{
    logger.i("Token refreshed: $newToken");
    String? oldToken = await FlutterSecureStorage().read(key: 'fcmToken');
    if(oldToken != null) {
      await updateDevice(oldToken, newToken);
    } else {
      await addDevice();
    }
  });

  // Listen for foreground messages.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    logger.i("Received a foreground message: ${message.messageId}");
    if (message.notification != null) {
      logger.i("Message contains notification: ${message.notification?.body ?? "Empty"}");
      _showLocalNotification(message);
    } else if (message.data.isNotEmpty) {
      // Data-only (silent) push: decode and show locally
      _showLocalNotificationFromData(message.data);
    }
  });

  // Listen for when the app is opened from a terminated or background state via a notification.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    logger.i("Notification caused app to open: ${message.messageId}");
    // Handle navigation or state update if needed.
  });
}