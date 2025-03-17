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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../recording/streamRec.dart';
import 'forgottenPassword.dart';
import 'registeration/mail.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;

final logger = Logger();

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late TapGestureRecognizer _registerTapRecognizer;

  @override
  void initState() {
    super.initState();
    _registerTapRecognizer = TapGestureRecognizer()
      ..onTap = () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RegMail()),
        );
      };
  }

  @override
  void dispose() {
    _registerTapRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void login() async {
    final url = Uri.https('api.strnadi.cz', '/auth/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        await const FlutterSecureStorage()
            .write(key: 'token', value: response.body);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LiveRec()));
      } else if (response.statusCode == 401) {
        _showMessage('Špatné jméno nebo heslo');
      } else {
        logger.w('Login failed: Code: ${response.statusCode} message: ${response.body}');
        _showMessage('Přihlášení selhalo, zkuste to znovu');
      }
    } catch (error, stackTrace) {
      logger.e('An error has occured when logging in $error', error: error, stackTrace: stackTrace);
      Sentry.captureException(error, stackTrace: stackTrace);
      _showMessage('Chyba připojení');
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'))
        ],
      ),
    );
  }

  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    const Color yellowishBlack = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    return Scaffold(
      backgroundColor: Colors.white,
      // AppBar with a back button at the top
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset('assets/icons/backButton.png', width: 30, height: 30),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spacing from the top (additional to AppBar)
              const SizedBox(height: 20),

              // Title: "Přihlášení"
              const Text(
                'Přihlášení',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 40),

              // --- E-mail label and TextField ---
              Text(
                'E-mail',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  fillColor: Colors.grey[200],
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  // More rounded border
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Heslo (Password) label and TextField ---
              Text(
                'Heslo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  fillColor: Colors.grey[200],
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  suffixIcon: IconButton(
                    icon: _obscurePassword
                        ? Image.asset(
                      'assets/icons/visOn.png',
                      width: 30,
                      height: 30,
                    )
                        : Image.asset(
                      'assets/icons/visOff.png',
                      width: 30,
                      height: 30,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),

              // "Zapomenuté heslo?" aligned to the right
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // Handle "Forgot password" here
                  },
                  child: const Text('Zapomenuté heslo?'),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      // Login button moved to bottomNavigationBar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              login();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: yellow,
              foregroundColor: yellowishBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: const Text('Přihlásit se'),
          ),
        ),
      ),
    );
  }
}
