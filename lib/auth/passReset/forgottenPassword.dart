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
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/passReset/resetEmailSent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../../config/config.dart';
import '../login.dart';

Logger logger = Logger();

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
                Text(t('signup.passwordReset.request.title'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Subheading
                Text(t('signup.passwordReset.request.subtitle'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 40),

                // Label for Email
                Text(t('login.inputs.emailLabel'),
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
                      return t('signup.passwordReset.request.errors.emptyEmail');
                    }
                    if (!RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                    ).hasMatch(value)) {
                      return t('login.errors.invalidEmailFormat');
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
                _showMessage(t('signup.passwordReset.request.errors.sendBeforeValid'));
              }
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              shadowColor: Colors.transparent,
              backgroundColor: yellow,
              foregroundColor: yellowishBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: Text(t('signup.passwordReset.request.buttons.sendLink')),
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
        _showMessage(t('signup.passwordReset.request.messages.sent'));
        Navigator.replace(context, newRoute: MaterialPageRoute(builder: (_) => ResetEmailSent(userEmail: email)), oldRoute: ModalRoute.of(context)!,);
      } else if(response.statusCode == 401) {
        logger.w('Unregistred email: ${response.statusCode} | ${response.body}');
        _showMessage(t('signup.passwordReset.request.messages.unregistered'));
      } else if(response.statusCode == 500) {
        logger.w('Server error: ${response.statusCode} | ${response.body}');
        _showMessage(t('signup.passwordReset.request.messages.serverError'));
      } else {
        logger.i('Failed to send password reset: ${response.statusCode}');
        _showMessage(t('signup.passwordReset.request.messages.genericFail'));
      }
    } catch (e, stackTrace) {
      logger.e('Error sending password reset request: $e', error: e, stackTrace: stackTrace);
      _showMessage(t('signup.passwordReset.request.messages.connectionError'));
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('signup.passwordReset.request.dialogTitle')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }
}