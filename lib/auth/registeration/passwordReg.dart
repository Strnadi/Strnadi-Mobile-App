/*
 * Copyright (C) 2025
 * Marian Pecqueur && Jan Drobílek
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
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/login.dart';

final logger = Logger();

class RegPassword extends StatefulWidget {
  final String email;
  final bool consent;
  final String name;
  final String surname;
  final String nickname;

  const RegPassword({
    super.key,
    required this.email,
    required this.consent,
    required this.name,
    required this.surname,
    required this.nickname,
  });

  @override
  State<RegPassword> createState() => _RegPasswordState();
}

class _RegPasswordState extends State<RegPassword> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for the password and its confirmation
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
  TextEditingController();

  // Whether the password fields are hidden
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Colors from your design
  static const Color textColor = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);

  /// Individual checks for each requirement
  bool get _hasUpper =>
      RegExp(r'[A-Z]').hasMatch(_passwordController.text);
  bool get _hasLower =>
      RegExp(r'[a-z]').hasMatch(_passwordController.text);
  bool get _hasDigit =>
      RegExp(r'\d').hasMatch(_passwordController.text);
  // bool get _hasSymbol =>
  //     RegExp('[!@#\$%^&*(),.?":{}|<>_\-–=+~;\'\\/]')
  //         .hasMatch(_passwordController.text);
  bool get _hasLength =>
      _passwordController.text.length >= 8;

  /// Checks that the password does NOT contain the user’s name or email.
  /// Adjust if you prefer a more advanced check (e.g., partial matches).
  bool get _doesNotContainNameOrEmail {
    final pass = _passwordController.text.toLowerCase();
    final name = widget.name.toLowerCase();
    final email = widget.email.toLowerCase();
    // If either name or email is empty or short, you may want to skip
    // but for simplicity, we do a simple substring check:
    return !pass.contains(name) && !pass.contains(email);
  }

  /// Final check: all partial checks must pass
  bool _passwordMeetsRequirements(String password) {
    return _hasUpper &&
        _hasLower &&
        _hasDigit &&
        //_hasSymbol &&
        _hasLength &&
        _doesNotContainNameOrEmail;
  }

  /// Overall form is valid if both fields are non-empty, match each other, and meet the requirements.
  bool get _isFormValid {
    final pass = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    return pass.isNotEmpty &&
        confirm.isNotEmpty &&
        pass == confirm &&
        _passwordMeetsRequirements(pass);
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chyba'),
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

  Future<void> register() async {
    final secureStorage = FlutterSecureStorage();

    final url = Uri(
      scheme: 'https',
      host: 'api.strnadi.cz',
      path: '/auth/sign-up',
    );

    final requestBody = jsonEncode({
      'email': widget.email,
      'password': _passwordController.text,
      'FirstName': widget.name,
      'LastName': widget.surname,
      'nickname': widget.nickname.isEmpty ? null : widget.nickname,
      'consent': widget.consent,
    });

    logger.i("Sign Up Request Body: $requestBody");

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      logger.i("Sign Up Response: ${response.body}");

      if ([200, 201, 202].contains(response.statusCode)) {
        // Store the token if returned
        await secureStorage.write(key: 'token', value: response.body.toString());

        // Navigate to the login screen (or next step)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const Login()),
              (Route<dynamic> route) => false,
        );
      } else if (response.statusCode == 409) {
        _showMessage('Uživatel již existuje');
      } else {
        _showMessage('Nastala chyba :( Zkuste to znovu');
        logger.e("Sign up failed: ${response.statusCode} | ${response.body}");
      }
    } catch (error) {
      logger.e("An error occurred: $error");
      _showMessage('Nastala chyba :( Zkuste to znovu');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Minimal app bar (white background, no shadow)
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      backgroundColor: Colors.white,

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Nastavte si heslo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 24),

                // "Heslo" label
                const Text(
                  'Heslo *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    fillColor: Colors.grey[200],
                    filled: true,
                    hintText: 'Zadejte heslo',
                    hintStyle: const TextStyle(color: Colors.grey),
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
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Zadejte heslo';
                    } else if (!_passwordMeetsRequirements(value)) {
                      return 'Heslo nesplňuje požadavky';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),

                // "Zopakujte heslo" label
                const Text(
                  'Zopakujte heslo *',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),

                // Confirm password field
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  decoration: InputDecoration(
                    fillColor: Colors.grey[200],
                    filled: true,
                    hintText: 'Zopakujte heslo',
                    hintStyle: const TextStyle(color: Colors.grey),
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
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Zopakujte heslo';
                    } else if (value.trim() != _passwordController.text.trim()) {
                      return 'Hesla se neshodují';
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Password requirements, each line lights up green if met
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• Alespoň jedno velké písmeno',
                      style: TextStyle(
                        color: _hasUpper ? Colors.green : textColor,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '• Alespoň jedno malé písmeno',
                      style: TextStyle(
                        color: _hasLower ? Colors.green : textColor,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '• Alespoň jedna číslice (0–9)',
                      style: TextStyle(
                        color: _hasDigit ? Colors.green : textColor,
                        fontSize: 14,
                      ),
                    ),
                    // Text(
                    //   '• Alespoň jeden symbol (!@#\$%^&*…?)',
                    //   style: TextStyle(
                    //     color: _hasSymbol ? Colors.green : textColor,
                    //     fontSize: 14,
                    //   ),
                    // ),
                    Text(
                      '• Alespoň 8 znaků',
                      style: TextStyle(
                        color: _hasLength ? Colors.green : textColor,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '• Nepoužívejte vaše jméno nebo email',
                      style: TextStyle(
                        color: _doesNotContainNameOrEmail
                            ? Colors.green
                            : textColor,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // "Pokračovat" button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        register();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      backgroundColor: _isFormValid ? yellow : Colors.grey,
                      foregroundColor: _isFormValid ? textColor : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                    child: const Text('Pokračovat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // Bottom segmented progress bar with extra bottom padding
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 32),
        child: Row(
          children: List.generate(6, (index) {
            // Fill first 2 segments to show "2 out of 6" progress
            final bool completed = index < 2;
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
    );
  }
}