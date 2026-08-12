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
import 'dart:async';

import 'package:strnadi/localization/localization.dart';

import 'package:flutter/material.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/passReset/password_reset_flow.dart';
import 'package:strnadi/navigation/session_navigation.dart';
import 'changedPassword.dart';

final logger = Logger();
const AuthController _authController = AuthController();

typedef PasswordResetSubmitter = Future<int?> Function({
  required String email,
  required String token,
  required String password,
});

class ChangePassword extends StatefulWidget {
  final String jwt;
  final PasswordResetSubmitter? submitPasswordReset;

  const ChangePassword({
    super.key,
    required this.jwt,
    this.submitPasswordReset,
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
  bool _resetting = false;

  // Colors from your design
  static const Color textColor = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);

  /// Individual checks for each requirement
  bool get _hasUpper => RegExp(r'[A-Z]').hasMatch(_passwordController.text);

  bool get _hasLower => RegExp(r'[a-z]').hasMatch(_passwordController.text);

  bool get _hasDigit => RegExp(r'\d').hasMatch(_passwordController.text);

  // bool get _hasSymbol =>
  //     RegExp('[!@#\$%^&*(),.?":{}|<>_\-–=+~;\'\\/]')
  //         .hasMatch(_passwordController.text);
  bool get _hasLength => _passwordController.text.length >= 8;

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await navigateToSessionLanding(context);
      },
      child: Scaffold(
        // Minimal app bar (white background, no shadow)
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await navigateToSessionLanding(context);
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
                  Text(
                    t('signup.password.title'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // "Heslo" label
                  Text(
                    t('signup.password.password'),
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
                      hintText: t('signup.password.password_hint'),
                      hintStyle: TextStyle(color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
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
                        return t('signup.password.password_hint');
                      } else if (!_passwordMeetsRequirements(value)) {
                        return t('signup.password.errors.req_not_met');
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // "Zopakujte heslo" label
                  Text(
                    t('signup.password.repeat_password'),
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
                      hintText: t('signup.password.password_again_hint'),
                      hintStyle: TextStyle(color: Colors.grey),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2),
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
                      if (value == null || value.trim().isEmpty) {
                        return t('signup.password.password_again_hint');
                      } else if (value.trim() !=
                          _passwordController.text.trim()) {
                        return t('signup.password.errors.password_match_err');
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
                        t('signup.password.password_req.capital_letter'),
                        style: TextStyle(
                          color: _hasUpper ? Colors.green : textColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        t('signup.password.password_req.lovercase_letter'),
                        style: TextStyle(
                          color: _hasLower ? Colors.green : textColor,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        t('signup.password.password_req.digit'),
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
                        t('signup.password.password_req.lenght_req'),
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
                      key: const Key('change-password-submit'),
                      onPressed: _resetting
                          ? null
                          : () => unawaited(_submitNewPassword()),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: _isFormValid ? yellow : Colors.grey,
                        foregroundColor:
                            _isFormValid ? textColor : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                      ),
                      child: Text(t('signup.password.buttons.continue')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom segmented progress bar with extra bottom padding
        bottomNavigationBar: Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 48),
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

  Future<void> _submitNewPassword() async {
    if (_resetting || !mounted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _resetting = true);
    try {
      final String? email = passwordResetEmailFromToken(widget.jwt);
      if (email == null) {
        _showMessage(
          t('signup.passwordReset.change.errors.invalidLink'),
        );
        return;
      }

      final int? status = widget.submitPasswordReset == null
          ? (await _authController.setResetPassword(
              email: email,
              token: widget.jwt,
              password: _passwordController.text,
            ))
              .statusCode
          : await widget.submitPasswordReset!(
              email: email,
              token: widget.jwt,
              password: _passwordController.text,
            );
      if (!mounted) return;

      if (status == 200) {
        unawaited(
          Navigator.of(context).pushReplacement<void, void>(
            MaterialPageRoute<void>(
              builder: (_) => const PasswordChangedScreen(),
            ),
          ),
        );
      } else {
        logger.e('Failed to reset password ($status).');
        _showMessage(
          t('signup.passwordReset.change.errors.failed'),
        );
      }
    } catch (error, stackTrace) {
      logger.e(
        'Password reset request failed.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showMessage(
          t('signup.passwordReset.change.errors.connection'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(t('signup.passwordReset.request.dialogTitle')),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
