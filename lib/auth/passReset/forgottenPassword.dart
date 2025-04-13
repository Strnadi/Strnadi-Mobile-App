/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
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
import 'package:strnadi/auth/passReset/resetEmailSent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../../config/config.dart';
import '../login.dart';

class ForgottenPassword extends StatefulWidget {
  const ForgottenPassword({Key? key}) : super(key: key);

  @override
  _ForgottenPasswordState createState() => _ForgottenPasswordState();
}

class _ForgottenPasswordState extends State<ForgottenPassword> {
  final TextEditingController _emailController = TextEditingController();
  final _GlobalKey = GlobalKey<FormState>();

  // Example color constants (match these to the ones in your Login screen)
  static const Color yellowishBlack = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // AppBar with custom back button
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/icons/backButton.png',
            width: 30,
            height: 30,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Form(
            key: _GlobalKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Some spacing from top
                const SizedBox(height: 20),

                // Heading
                const Text(
                  'Zadejte váš e-mail pro změnu hesla',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Subheading
                Text(
                  'Na tento e-mail vám pošleme instrukce pro reset hesla',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 40),

                // Label for Email
                Text(
                  'E-mail',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),

                // E-mail text field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textAlign: TextAlign.start,
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
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vyplňte prosím e-mail';
                    }
                    if (!RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                    ).hasMatch(value)) {
                      return 'Zadejte platný e-mail';
                    }
                    return null;
                  },
                  onFieldSubmitted: (value) {
                    if (_GlobalKey.currentState?.validate() ?? false) {
                      requestPasswordReset(_emailController.text);
                    }
                  },
                ),

                // Spacing for bottom
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),

      // Button pinned to the bottom
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (_GlobalKey.currentState?.validate() ?? false) {
                requestPasswordReset(_emailController.text);
              } else {
                _showMessage('Zadejte platný e-mail před odesláním.');
              }
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor: Colors.transparent,
              backgroundColor: yellow,
              foregroundColor: yellowishBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: const Text('Poslat odkaz'),
          ),
        ),
      ),
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final uri = Uri(scheme: 'https', host: Config.host, path: '/auth/$email/reset-password');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        _showMessage("E-mail s pokyny pro reset hesla byl odeslán.");
        Navigator.replace(context, newRoute: MaterialPageRoute(builder: (_) => ResetEmailSent(userEmail: email)), oldRoute: ModalRoute.of(context)!,);
      } else if(response.statusCode == 401) {
        logger.w('Unregistred email: ${response.statusCode} | ${response.body}');
        _showMessage("Zadaný e-mail není registrován.");
      } else if(response.statusCode == 500) {
        logger.w('Server error: ${response.statusCode} | ${response.body}');
        _showMessage("Server je momentálně nedostupný. Zkuste to prosím později.");
      } else {
        logger.i('Failed to send password reset: ${response.statusCode}');
        _showMessage("Nepodařilo se odeslat reset hesla. Zkuste to prosím znovu.");
      }
    } catch (e, stackTrace) {
      logger.e('Error sending password reset request: $e', error: e, stackTrace: stackTrace);
      _showMessage("Chyba při odesílání požadavku. Zkontrolujte připojení.");
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset hesla'),
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
}