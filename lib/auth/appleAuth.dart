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
// ignore_for_file: avoid_print

import 'dart:io' show Platform;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:strnadi/database/databaseNew.dart' hide logger;
import '../config/config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A simple model that contains the data returned by Apple after
/// a successful sign‑in.
class AppleAuthResult {
  final String userIdentifier;
  final String givenName;
  final String familyName;
  final String email;
  final String idToken;
  final String authorizationCode;

  const AppleAuthResult({
    required this.userIdentifier,
    required this.givenName,
    required this.familyName,
    required this.email,
    required this.idToken,
    required this.authorizationCode,
  });
}

/// Provides one static method to kick off the Apple Sign‑In flow.
///
/// On iOS/macOS this shows the native Apple dialog.
/// On Android it opens an in‑app browser tab and redirects back to the
/// callback you configured on developer.apple.com.
///
/// * The `redirectUri` **must** be exactly the same value you set
///   in the “Services ID” (e.g. `https://${Config.host}/auth/apple`).
/// * The `clientId` must be your full Services ID (e.g.
///   `com.your.bundleid.service`).
class AppleAuth {
  static Future<AppleAuthResult?> signIn() async {
    if (!Platform.isIOS && !Platform.isMacOS && !Platform.isAndroid) {
      throw UnsupportedError('Apple Sign‑In is not supported on this platform');
    }

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.fullName,
        AppleIDAuthorizationScopes.email,
      ],
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId:
            'web.delta.strnadi',
        redirectUri: Uri.parse('https://${Config.host}/auth/apple/callback'),
      ),
    );

    return AppleAuthResult(
      userIdentifier: credential.userIdentifier ?? '',
      givenName: credential.givenName ?? '',
      familyName: credential.familyName ?? '',
      email: credential.email ?? '',
      idToken: credential.identityToken ?? '',
      authorizationCode: credential.authorizationCode,
    );
  }

  /// Signs the user in with Apple **and** immediately exchanges the
  /// credentials with your backend to obtain a JWT specific to your app.
  ///
  /// The backend endpoint must accept a JSON body with the parameters below
  /// and respond with: `{ "jwt": "<token>" }`.
  ///
  /// Throws an [Exception] if the backend responds with anything other than
  /// HTTP 200.
  static Future<Map<String, dynamic>?> signInAndGetJwt(String? jwt) async {
    final result = await signIn();
    if (result == null) return null;
    Map<String, dynamic> body = {
      'authorizationCode': result.authorizationCode,
      'IdToken': result.idToken,
      'userIdentifier': result.userIdentifier,
      'email': result.email,
      'givenName': result.givenName,
      'familyName': result.familyName,
    };

    Map<String, String> headers = {
      'Content-Type': 'application/json',
      if (jwt != null) 'Authorization': 'Bearer $jwt',
    };

    final response = await http.post(
      // Change this URL if your backend listens elsewhere.
      Uri.parse('https://${Config.host}/auth/apple'),
      headers: headers,
      body: jsonEncode(body),
    );

    logger.t(body);

    logger.t(response.body);

    Map<String, dynamic> resp = {};
    if (response.statusCode == 200) {
      resp = jsonDecode(response.body) as Map<String, dynamic>;
      logger.i('Apple Sign-In successful');
    } else {
      logger.w(
          'Apple Sign-In failed with status code: ${response.statusCode} | ${response.body}');
    }
    resp.addAll({"status": response.statusCode});
    return resp;
  }
}
