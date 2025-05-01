

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