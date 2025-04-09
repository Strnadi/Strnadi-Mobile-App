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
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'dart:io';

import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/config.dart';

Logger logger = Logger();

class GoogleSignInService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '287278255232-2rfu5vd3j233uhn4ktacpfs7rep0s44d.apps.googleusercontent.com'
  );

  static Future<String?> signInWithGoogle() async {
    // Trigger the authentication flow.
    try {
      logger.i('starting google sign in');
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign in.
        logger.w('google sign in canceled');
        return null;
        //throw Exception('Google sign in canceled');
      }

      // Obtain the auth details from the request.
      final GoogleSignInAuthentication googleAuth = await googleUser
          .authentication;

      String idToken = '';
      if(googleAuth.idToken != null) {
        idToken = googleAuth.idToken!;
      }
      else {
        logger.e('Google sign in failed: idToken is null');
        signOut();
        return null;
      }

      logger.i('got auth');

      logger.i('google idToken: $idToken');

      //Send to BE
      Uri url = Uri.parse('https://${Config.host}/auth/login-google');
      final response = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'idToken': idToken,
          })
      );
      if (response.statusCode == 200) {
        logger.i('Google sign in succesfull');
        final jwt = response.body;
        return jwt;
      } else {
        throw Exception(
            'Sign in failed: ${response.statusCode} | ${response.body}');
      }
    } catch(e, stackTrace) {
      signOut();
      logger.e('Google sign in failed: ${e.toString()}', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  static Future<String> getIdToken() async{
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign in canceled');
    }
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    return idToken!;
  }

  static Future<Map<String, dynamic>?> signUpWithGoogle() async {
    final idToken = await getIdToken();

    logger.i('Google email: ${JwtDecoder.decode(idToken)['sub']}');

    // Call your backend sign-up endpoint.
    // Replace the URL with your actual backend endpoint.
    final url = 'https://${Config.host}/auth/sign-up-google';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
      })
    );

    if(response.statusCode == 409){
      GoogleSignInService.signOut();
      logger.w('User already exists');
      return {'status': 409};
    } else if (response.statusCode != 200) {
      GoogleSignInService.signOut();
      logger.w('Sign up failed: ${response.statusCode} | ${response.body}');
      return null;
    }

    Map<String,dynamic> user = jsonDecode(response.body);
    return user;
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}