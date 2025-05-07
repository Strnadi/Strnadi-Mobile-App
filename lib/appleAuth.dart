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


import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// A service to handle Sign in with Apple.
class AppleAuthService {
  /// Initiates the Sign in with Apple flow and returns the credential.
  ///
  /// The returned [AuthorizationCredentialAppleID] contains the user's
  /// identity token, authorization code, and (optionally) email and full name.
  static Future<AuthorizationCredentialAppleID> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      return credential;
    } catch (e) {
      // Handle errors, e.g., user cancellation or network issues.
      throw Exception('Failed to sign in with Apple: $e');
    }
  }
}