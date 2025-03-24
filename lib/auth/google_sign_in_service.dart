import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GoogleSignInService {
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Future<UserCredential> signInWithGoogle() async {
    // Trigger the authentication flow.
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // User canceled the sign in.
      throw Exception('Google sign in canceled');
    }

    // Obtain the auth details from the request.
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    // Create a new credential.
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Once signed in, return the UserCredential.
    return await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<Map<String, String>> signUpWithGoogle() async {
    // Trigger the authentication flow.
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign in canceled');
    }

    // Obtain the auth details from the request.
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    final accessToken = googleAuth.accessToken;
    final email = googleUser.email;

    // Call your backend sign-up endpoint.
    // Replace the URL with your actual backend endpoint.
    final url = 'https://yourbackend.com/api/signup';
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'accessToken': accessToken,
        'email': email,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Sign up failed: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return {
      'token': data['token'],
      'email': data['email'],
    };
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await FirebaseAuth.instance.signOut();
  }
}