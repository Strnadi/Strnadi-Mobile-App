import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:logger/logger.dart';

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

    final payload = {
      "message": {
        "token": deviceToken,
        "notification": {
          "title": title,
          "body": body,
        },
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
