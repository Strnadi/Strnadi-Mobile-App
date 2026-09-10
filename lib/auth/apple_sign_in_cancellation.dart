import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Closing Apple's native sheet or Android browser tab is not a failed login.
Future<T?> requestAppleSignIn<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on SignInWithAppleAuthorizationException catch (error) {
    if (error.code == AuthorizationErrorCode.canceled) return null;
    rethrow;
  }
}
