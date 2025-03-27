import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'dart:io';

Logger logger = Logger();

class GoogleSignInService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '287278255232-2rfu5vd3j233uhn4ktacpfs7rep0s44d.apps.googleusercontent.com'
  );

  Future<String?> signInWithGoogle() async {
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
        return null;
      }

      logger.i('got auth');

      logger.i('google idToken: $idToken');

      //Send to BE
      Uri url = Uri.parse('https://api.strnadi.cz/auth/login-google');
      final response = await http.post(url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'idToken': idToken,
          })
      );
      if (response.statusCode == 200) {
        logger.i('Google sign in succesfull');
        final jwt = jsonDecode(response.body);
        return jwt;
      } else {
        throw Exception(
            'Sign in failed: ${response.statusCode} | ${response.body}');
      }
    } catch(e, stackTrace) {
      logger.e('Google sign in failed: ${e.toString()}', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<String> getIdToken() async{
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign in canceled');
    }
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    return idToken!;
  }

  // Future<String> signUpWithGoogle() async {
  //   final idToken = await getIdToken();
  //
  //   // Call your backend sign-up endpoint.
  //   // Replace the URL with your actual backend endpoint.
  //   final url = 'https://api.strnadi.cz/auth/signup-google';
  //   // final response = await http.post(
  //   //   Uri.parse(url),
  //   //   headers: {'Content-Type': 'application/json'},
  //   //   body: jsonEncode({
  //   //     'idToken': idToken,
  //   //     'accessToken': accessToken,
  //   //     'email': email,
  //   //   })
  //   // );
  //
  //   // if (response.statusCode != 200) {
  //   //   throw Exception('Sign up failed: ${response.body}');
  //   // }
  //
  //   // final jwt = jsonDecode(response.body);
  //   return jwt;
  // }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}