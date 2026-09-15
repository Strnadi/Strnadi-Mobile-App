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
import 'package:strnadi/api/api_logging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:strnadi/logging/app_logger.dart';

AppLogger logger = AppLogger(scope: 'auth.google_sign_in_service');
const AuthController _authController = AuthController();

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  static const List<String> _scopeHint = ['email', 'profile'];
  static const String _serverClientId =
      '287278255232-2rfu5vd3j233uhn4ktacpfs7rep0s44d.apps.googleusercontent.com';

  static String? _sanitizeEmail(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _extractEmailFromIdToken(String idToken) {
    try {
      return _sanitizeEmail(JwtDecoder.decode(idToken)['email']);
    } catch (e, stackTrace) {
      logger.w(
        'Failed to decode Google idToken email: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<void> _ensureInitialized() {
    return _initialization ??= _googleSignIn.initialize(
      serverClientId: _serverClientId,
    );
  }

  static bool _isUserCancellation(GoogleSignInException exception) {
    return exception.code == GoogleSignInExceptionCode.canceled ||
        exception.code == GoogleSignInExceptionCode.interrupted ||
        exception.code == GoogleSignInExceptionCode.uiUnavailable;
  }

  static Future<GoogleSignInAccount?> _interactiveSignIn() async {
    await _ensureInitialized();
    try {
      return await _googleSignIn.authenticate(scopeHint: _scopeHint);
    } on GoogleSignInException catch (exception) {
      if (_isUserCancellation(exception)) {
        return null;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> googleAuth({String? jwt}) async {
    logger.i('Starting google auth process');
    try {
      final GoogleSignInAccount? googleUser = await _interactiveSignIn();
      if (googleUser == null) {
        // User canceled the sign in.
        logger.w('google sign in canceled');
        return null;
        //throw Exception('Google sign in canceled');
      }

      // Obtain the auth details from the request.
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      late String idToken;
      if (googleAuth.idToken != null) {
        idToken = googleAuth.idToken!;
      } else {
        logger.e('Google sign in failed: idToken is null');
        signOut();
        return null;
      }

      final accountEmail = _sanitizeEmail(googleUser.email);
      final tokenEmail = _extractEmailFromIdToken(idToken);
      final googleEmail = accountEmail ?? tokenEmail;
      logger.i('got auth');

      logger.i('google idToken received');

      final response = await _authController.googleSignIn(
        idToken: idToken,
        email: googleEmail,
        token: jwt,
      );

      Map<String, dynamic> product = {"status": response.statusCode};

      if (response.statusCode != 200) {
        logger.w(
          'Google sign in failed with status ${response.statusCode}.',
          failure: apiFailureForResult(response),
        );
        return product;
      }
      final dynamic raw = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (raw is Map) {
        product.addAll(raw.cast<String, dynamic>());
      }
      product['email'] = _sanitizeEmail(product['email']) ?? googleEmail ?? '';
      logger.i('Google sign in successful');
      return product;
    } catch (e, stackTrace) {
      logger.e(
        'Error processing Google Auth: $e',
        error: e,
        stackTrace: stackTrace,
      );

      return null;
    }
  }

  static Future<String?> signInWithGoogle() async {
    // Trigger the authentication flow.
    try {
      logger.i('starting google sign in');
      final GoogleSignInAccount? googleUser = await _interactiveSignIn();
      if (googleUser == null) {
        // User canceled the sign in.
        logger.w('google sign in canceled');
        return null;
        //throw Exception('Google sign in canceled');
      }

      // Obtain the auth details from the request.
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      late String idToken;
      if (googleAuth.idToken != null) {
        idToken = googleAuth.idToken!;
      } else {
        logger.e('Google sign in failed: idToken is null');
        signOut();
        return null;
      }

      logger.i('got auth');

      logger.i('google idToken received');

      final response = await _authController.loginGoogle(idToken: idToken);
      if (response.statusCode == 200) {
        logger.i('Google sign in succesfull');
        final jwt = response.data.toString();
        return jwt;
      } else {
        final error = Exception(
          'Sign in failed with status ${response.statusCode}.',
        );
        AppFailureRegistry.attach(error, apiFailureForResult(response));
        throw error;
      }
    } catch (e, stackTrace) {
      signOut();
      logger.e(
        'Google sign in failed: ${e.toString()}',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Future<String> getIdToken() async {
    final GoogleSignInAccount? googleUser = await _interactiveSignIn();
    if (googleUser == null) {
      final error = Exception('Google sign in canceled');
      final stackTrace = StackTrace.current;
      AppFailureRegistry.attach(
        error,
        AppFailure(
          reason: 'Google sign in was cancelled',
          expected: true,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    return idToken!;
  }

  static Future<Map<String, dynamic>?> signUpWithGoogle() async {
    final idToken = await getIdToken();
    final email = _extractEmailFromIdToken(idToken);

    logger.i('Google sign-up identity contains email: ${email != null}.');

    final response = await _authController.signUpGoogle(
      idToken: idToken,
      email: email,
    );

    if (response.statusCode == 409) {
      GoogleSignInService.signOut();
      logger.w('User already exists');
      return {'status': 409};
    } else if (response.statusCode != 200) {
      GoogleSignInService.signOut();
      logger.w(
        'Google sign up failed with status ${response.statusCode}.',
        failure: apiFailureForResult(response),
      );
      return {'status': response.statusCode};
    }

    final dynamic raw = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (raw is! Map) {
      return {'status': response.statusCode};
    }
    Map<String, dynamic> user = raw.cast<String, dynamic>();
    user.addEntries({'status': response.statusCode}.entries);
    return user;
  }

  static Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }
}
