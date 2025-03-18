import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:strnadi/config/config.dart';

Future<void> sendPushNotificationV1(String deviceToken, String title, String body) async {
  // Read secrets from your config.
  final projectId = Config.firebaseProjectId;
  final serviceAccountJson = Config.firebaseServiceAccountJson;

  // Define required scopes.
  const scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

  // Create credentials and obtain an authenticated HTTP client.
  final accountCredentials = ServiceAccountCredentials.fromJson(serviceAccountJson);
  final client = await clientViaServiceAccount(accountCredentials, scopes);

  // Construct the FCM v1 endpoint URL.
  final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

  // Build the push notification payload.
  final payload = {
    "message": {
      "token": deviceToken,
      "notification": {
        "title": title,
        "body": body,
      },
      // Optionally, add custom data:
      // "data": {"key1": "value1", "key2": "value2"}
    }
  };

  // Send the request.
  final response = await client.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload),
  );

  if (response.statusCode == 200) {
    print("Push notification sent successfully: ${response.body}");
  } else {
    print("Failed to send push notification. Status: ${response.statusCode}");
    print("Response: ${response.body}");
  }

  client.close();
}