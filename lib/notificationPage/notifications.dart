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
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:logger/logger.dart';

import '../config/config.dart';

final logger = Logger();

Future<Map<String, dynamic>> loadServiceAccountJson() async {
  //WARNING:  This loads your service account key directly from assets!
  final jsonString = await rootBundle.loadString('assets/firebase-secrets.json');
  return jsonDecode(jsonString);
}

Future<void> sendPushNotificationDirectly(String deviceToken, String title, String body) async {
  try {
    final serviceAccountJson = await loadServiceAccountJson();
    final projectId = serviceAccountJson['project_id'];
    if (projectId == null) {
      logger.e('Project ID not found.');
      return;
    }
    const scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
    final accountCredentials = ServiceAccountCredentials.fromJson(serviceAccountJson);

    // Create a client, this is the insecure part!!
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

    // Build a data-only, silent push. The client should read:
    //   final lang = data['lang'];
    //   final title = jsonDecode(data['title'])[lang];
    //   final message = jsonDecode(data['message'])[lang];
    const String iosBundleId = 'com.delta.strnadi';
    final String lang = Config.getLanguagePreference().toString();
    final Map<String, String> titleMap = {'en': title};
    final Map<String, String> messageMap = {'en': body};

    final payload = {
      "message": {
        "token": deviceToken,
        "data": {
          "lang": lang,
          "title": jsonEncode(titleMap),
          "message": jsonEncode(messageMap),
        },
        "apns": {
          "headers": {
            // Required on iOS 13+
            "apns-push-type": "background",
            // 5 for background, 10 for alert
            "apns-priority": "5",
            // Must equal your iOS bundle identifier
            "apns-topic": iosBundleId
          },
          "payload": {
            "aps": {
              // Silent/background push
              "content-available": 1
            }
          }
        },
        "android": {
          // Normal for data-only; use "high" if you need immediate delivery
          "priority": "normal"
        }
      }
    };

    final response = await client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      logger.i('Notification sent successfully.');
    } else {
      logger.e('Failed to send notification. Status: ${response.statusCode}, Body: ${response.body}');
    }
    client.close();

  } catch (e) {
    logger.e('Error sending notification directly: $e');
  }
}
