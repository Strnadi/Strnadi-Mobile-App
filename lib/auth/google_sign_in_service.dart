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
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Logger logger = Logger();
const AuthController _authController = AuthController();

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  static const List<String> _scopeHint = ['email', 'profile'];
  static const String _serverClientId =
      '287278255232-2rfu5vd3j233uhn4ktacpfs7rep0s44d.apps.googleusercontent.com';

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
      logger.i('got auth');

      logger.i('google idToken received');

      final response = await _authController.googleSignIn(
        idToken: idToken,
        token: jwt,
      );

      Map<String, dynamic> product = {"status": response.statusCode};

      if (response.statusCode != 200) {
        logger.w(
            'Google sign in failed: ${response.statusCode} | ${response.data}');
        return product;
      }
      final dynamic raw = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      if (raw is Map) {
        product.addAll(raw.cast<String, dynamic>());
      }
      logger.i('Google sign in successful');
      return product;
    } catch (e, stackTrace) {
      logger.e('Error processing Google Auth: $e',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
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
        throw Exception(
            'Sign in failed: ${response.statusCode} | ${response.data}');
      }
    } catch (e, stackTrace) {
      signOut();
      logger.e('Google sign in failed: ${e.toString()}',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static Future<String> getIdToken() async {
    final GoogleSignInAccount? googleUser = await _interactiveSignIn();
    if (googleUser == null) {
      throw Exception('Google sign in canceled');
    }
    final GoogleSignInAuthentication googleAuth = googleUser.authentication;
    final idToken = googleAuth.idToken;
    return idToken!;
  }

  static Future<Map<String, dynamic>?> signUpWithGoogle() async {
    final idToken = await getIdToken();

    logger.i('Google email: ${JwtDecoder.decode(idToken)['sub']}');

    final response = await _authController.signUpGoogle(idToken: idToken);

    if (response.statusCode == 409) {
      GoogleSignInService.signOut();
      logger.w('User already exists');
      return {'status': 409};
    } else if (response.statusCode != 200) {
      GoogleSignInService.signOut();
      logger.w('Sign up failed: ${response.statusCode} | ${response.data}');
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
