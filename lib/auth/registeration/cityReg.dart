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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'dart:ffi';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/auth/registeration/passwordReg.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/login.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;

import '../../config/config.dart';
import 'emailSent.dart';
import 'overview.dart';

Logger logger = Logger();

class RegLocation extends StatefulWidget {
  final String email;
  final bool consent;
  final String? password;
  final String jwt;
  final String name;
  final String surname;
  final String nickname;
  final String? appleId;

  const RegLocation({super.key, required this.email, required this.consent, this.password, required this.jwt, required this.name, required this.surname, required this.nickname, this.appleId});

  @override
  State<RegLocation> createState() => _RegLocationState();
}

class _RegLocationState extends State<RegLocation> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _pscController = TextEditingController();
  final TextEditingController _obecController = TextEditingController();

  // Colors and styling constants
  static const Color textColor = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.error.title')),
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

  Future<void> register() async {
    final secureStorage = FlutterSecureStorage();

    final url = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/auth/sign-up',
    );

    final requestBody = jsonEncode({
      'email': widget.email,
      'password': widget.password,
      'FirstName': widget.name,
      'LastName': widget.surname,
      'nickname': widget.nickname.isEmpty ? null : widget.nickname,
      'city': _obecController.text,
      'postCode': _pscController.text.isNotEmpty ? int.parse(_pscController.text).toUnsigned(32) : null,
      'consent': widget.consent,
    });

    logger.i("Sign Up Request Body: $requestBody");

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwt}',
        },
        body: requestBody,
      );

      logger.i("Sign Up Response: ${response.body}");

      if ([200, 201, 202].contains(response.statusCode)) {
        // Store the token if returned
        await secureStorage.write(key: 'token', value: response.body.toString());
        await fb.refreshToken();

        // Navigate to the login screen (or next step)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VerifyEmail(userEmail: widget.email),
          ),
        );
      } else if (response.statusCode == 409) {
        GoogleSignInService.signOut();
        logger.w('Sign up failed: ${response.statusCode} | ${response.body}');
        _showMessage('Uživatel již existuje');
      } else {
        GoogleSignInService.signOut();
        _showMessage('Nastala chyba :( Zkuste to znovu');
        logger.e("Sign up failed: ${response.statusCode} | ${response.body}");
      }
    } catch (error) {
      GoogleSignInService.signOut();
      logger.e("An error occurred: $error");
      _showMessage('Nastala chyba :( Zkuste to znovu');
    }
  }

  bool get _isFormValid => true;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          Navigator.pop(context);
        }
      },
    child:  Scaffold(
      // White background, same as in your example
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Image.asset(
            'assets/icons/backButton.png',
            width: 30,
            height: 30,
          ),
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(context, '/authorizator', (Route<dynamic> route) => false);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(t('signup.city.title'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle / Description
                Text(t('signup.city.subtitle'),
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 32),

                // PSČ label
                Text(t('signup.city.post_code'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pscController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    fillColor: Colors.grey[200],
                    filled: true,
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // Obec label
                Text(t('signup.city.city'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _obecController,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    fillColor: Colors.grey[200],
                    filled: true,
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 32),

                // Pokračovat button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => RegOverview(name: widget.name, surname: widget.surname, nickname: widget.nickname, email: widget.email, postCode: _pscController.text, city: _obecController.text, password: widget.password, consent: widget.consent, jwt: widget.jwt, appleId: widget.appleId,)));
                        //register();
                        // Navigate to the next screen or handle logic
                        // e.g.: Navigator.push(context, MaterialPageRoute(builder: (_) => NextPage()));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      backgroundColor: _isFormValid ? yellow : Colors.grey,
                      foregroundColor: _isFormValid ? textColor : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    child: Text(t('signup.mail.buttons.continue')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Bottom segmented progress bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 48),
        child: Row(
          children: List.generate(5, (index) {
            // You can customize which segment(s) are considered "completed"
            // For example, if this page is the 2nd or 3rd step:
            bool completed = index < 4; // or index < 3, etc.
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: completed ? yellow : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ),
    )
    );
  }
}