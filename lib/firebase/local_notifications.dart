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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/config/config.dart';

final _logger = Logger();

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationDetails _androidNotificationDetails =
    AndroidNotificationDetails(
  'com.delta.strnadi',
  'Strnadi',
  channelDescription: 'Aplikace Strnadi',
  importance: Importance.max,
  priority: Priority.high,
  ticker: 'ticker',
);

const NotificationDetails _notificationDetails = NotificationDetails(
  android: _androidNotificationDetails,
  iOS: DarwinNotificationDetails(),
);

Future<void> initLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );
}

Future<void> showLocalNotification(
  String title,
  String? body, {
  int? id,
}) async {
  try {
    await flutterLocalNotificationsPlugin.show(
      id ?? _notificationId(),
      title,
      body,
      _notificationDetails,
    );
  } catch (e, st) {
    _logger.e('Failed to show local notification', error: e, stackTrace: st);
  }
}

Future<void> showLocalNotificationFromData(Map<String, dynamic> data) async {
  try {
    final String lang = Config.StringFromLanguagePreference(
      await Config.getLanguagePreference(),
    );
    final Map<String, dynamic> lower = _toLowercaseKeys(data);

    final String? title = lower['title$lang']?.toString();
    final String? body = lower['body$lang']?.toString();
    _logger.i('Got notification with data: $lower');
    if (title == null && body == null) {
      _logger.w('No title/body for lang $lang in data; skipping');
      return;
    }

    await showLocalNotification(title ?? '', body);
  } catch (e, st) {
    _logger.e(
      'Failed to show local notification from data',
      error: e,
      stackTrace: st,
    );
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

int _notificationId() {
  return DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
}
