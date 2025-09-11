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

import 'package:strnadi/localization/localization.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';

import '../../config/config.dart';
import 'changedPassword.dart';

final logger = Logger();

class ChangePassword extends StatefulWidget {
  final String jwt;

  const ChangePassword({
    super.key,
    required this.jwt,
  });

  @override
  State<ChangePassword> createState() => _RegPasswordState();
}

class _RegPasswordState extends State<ChangePassword> {
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

  /// Final check: all partial checks must pass
  bool _passwordMeetsRequirements(String password) {
    return _hasUpper &&
        _hasLower &&
        _hasDigit &&
        //_hasSymbol &&
        _hasLength;
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

  @override
  Widget build(BuildContext context) {
    bool reseting = false;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        Navigator.of(context).pushReplacementNamed('/authorizator');
      },
      child: Scaffold(
        // Minimal app bar (white background, no shadow)
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/authorizator');
            },
          ),
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
                  Text(t('Nastavte si heslo'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // "Heslo" label
                  Text(t('Heslo *'),
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
                      hintStyle: TextStyle(color: Colors.grey),
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
                          _obscurePassword ? Icons.visibility_off : Icons
                              .visibility,
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
                      if (value == null || value
                          .trim()
                          .isEmpty) {
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
                  Text(t('Zopakujte heslo *'),
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
                      hintStyle: TextStyle(color: Colors.grey),
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
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value == null || value
                          .trim()
                          .isEmpty) {
                        return 'Zopakujte heslo';
                      } else
                      if (value.trim() != _passwordController.text.trim()) {
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
                      Text(t('• Alespoň jedno velké písmeno'),
                        style: TextStyle(
                          color: _hasUpper ? Colors.green : textColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(t('• Alespoň jedno malé písmeno'),
                        style: TextStyle(
                          color: _hasLower ? Colors.green : textColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(t('• Alespoň jedna číslice (0–9)'),
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
                      Text(t('• Alespoň 8 znaků'),
                        style: TextStyle(
                          color: _hasLength ? Colors.green : textColor,
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
                      onPressed: () async {
                        if ((_formKey.currentState?.validate() ?? false) &&
                            !reseting) {
                          reseting = true;
                          bool result = await setNewPassword(widget.jwt,
                              _passwordController.text);
                          if (result) {
                            Navigator.replace(
                              context,
                              oldRoute: ModalRoute.of(context)!,
                              newRoute: MaterialPageRoute(
                                builder: (
                                    context) => const PasswordChangedScreen(),
                              ),
                            );
                          }
                          reseting = false;
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
                      child: Text(t('Pokračovat')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom segmented progress bar with extra bottom padding
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.only(
              left: 16, right: 16, top: 16, bottom: 48),
          child: Row(
            children: List.generate(5, (index) {
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
      ),
    );
  }

  Future<bool> setNewPassword(String jwt, String password) async {
    String? email = JwtDecoder.decode(jwt)['sub'];
    if (email == null) {
      return false;
    }
    final uri = Uri(scheme: 'https',
        host: Config.host,
        path: '/auth/$email/reset-password');
    final response = await http.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      logger.i('Password reset successful');
      return true;
    } else {
      logger.e('Failed to reset password: ${response.body}');
      return false;
    }
  }
}