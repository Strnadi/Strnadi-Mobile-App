/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:strnadi/auth/unverifiedEmail.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/firebase/firebase.dart' as firebase;
import 'package:strnadi/database/databaseNew.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strnadi/auth/login.dart';
import 'package:flutter/gestures.dart'; // Needed for TapGestureRecognizer
import 'package:strnadi/md_renderer.dart';

import '../config/config.dart';

Logger logger = Logger();

enum AuthType { login, register }

class Authorizator extends StatefulWidget {
  final Widget login;
  final Widget register;

  const Authorizator({
    Key? key,
    required this.login,
    required this.register,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}

enum AuthStatus { loggedIn, loggedOut, notVerified }


Future<AuthStatus> isLoggedIn() async {
  final secureStorage = FlutterSecureStorage();
  final token = await secureStorage.read(key: 'token');
  if (token != null) {
    final Uri url = Uri(scheme: 'https', host: Config.host, path: 'auth/verify-jwt', queryParameters: {'jwt': token});

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      logger.i('Response: ${response.statusCode} | ${response.body}');

      if (response.statusCode == 200) {
        return AuthStatus.loggedIn;
      } else if (response.statusCode == 403) {
        return AuthStatus.notVerified;
      }
      else {
        return AuthStatus.loggedOut;
      }
    } catch (error) {
      Sentry.captureException(error);
      return AuthStatus.loggedOut;
    }
  }
  return AuthStatus.loggedOut;
}

class _AuthState extends State<Authorizator> {
  @override
  void initState() {
    super.initState();
    checkLoggedIn(); // token check if needed
  }

  @override
  Widget build(BuildContext context) {
    // Example color definitions
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          // Ensures scroll if the screen is too short on small devices
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              children: [
                // Spacing from the top
                const SizedBox(height: 40),

                // Bird image
                Image.asset(
                  'assets/images/ncs_logo_tall_large.png', // Update path if needed
                  width: 200,
                  height: 200,
                ),

                const SizedBox(height: 32),

                // Main title
                const Text(
                  'Nářečí českých strnadů',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),

                const SizedBox(height: 8),

                // Subtitle
                const Text(
                  'Nahrávejte, mapujte, dobývejte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: textColor,
                  ),
                ),

                const SizedBox(height: 40),

                // "Založit účet" button (yellow background, no elevation)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegMail()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0, // No elevation
                      shadowColor: Colors.transparent, // Remove shadow
                      backgroundColor: yellow,
                      foregroundColor: textColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Založit účet', style: TextStyle(color: textColor),),
                  ),
                ),

                const SizedBox(height: 16),

                // "Přihlásit se" button (outlined)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const Login()));
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: Colors.grey[200]!, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Přihlásit se', style: TextStyle(color: textColor)),
                  ),
                ),

                // Add some space to ensure the bottom disclaimer isn't too close
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
      // Disclaimer pinned at bottom
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'pokračováním souhlasíte se zásadami',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _launchURL(),
                child: const Text(
                  'ochrany osobních údajů.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> checkLoggedIn() async {
    final secureStorage = FlutterSecureStorage();
    final AuthStatus status = await isLoggedIn();
    if (status == AuthStatus.loggedIn) {
      String? token = await secureStorage.read(key: 'token');
      if (token == null) return;

      String email = JwtDecoder.decode(token)['sub'];
      final Uri url = Uri.parse('https://${Config.host}/users/$email').replace(queryParameters: {'jwt': token});

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final Map<String, dynamic> data = jsonDecode(response.body);
      secureStorage.write(key: 'user', value: data['firstName']);
      secureStorage.write(key: 'lastname', value: data['lastName']);

      logger.i('Syncing recordings on login');
      DatabaseNew.syncRecordings();
      logger.i('Syncing recordings on login done');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LiveRec()),
      );
    } else if(status == AuthStatus.notVerified) {
      String? token = await secureStorage.read(key: 'token');
      if (token == null) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EmailNotVerified(userEmail: JwtDecoder.decode(token!)['sub'])),
      );
    } else {
      // If there is a token but user is not logged in (invalid token),
      // remove it and show message.
      if (await secureStorage.read(key: 'token') != null) {
        _showMessage("Byli jste odhlášeni");
        secureStorage.delete(key: 'token');
        secureStorage.delete(key: 'user');
        secureStorage.delete(key: 'lastname');
        firebase.deleteToken();
      }
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MDRender(mdPath: 'assets/docs/terms-of-services.md', title: 'Podmínky používání',)),
    );
  }
}
