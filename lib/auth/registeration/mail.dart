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
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/email_input_formatter.dart';
import 'package:strnadi/auth/email_validator.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/auth/registeration/nameReg.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/auth/registeration/passwordReg.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/google_sign_in_service.dart' as gle;
import 'package:strnadi/auth/appleAuth.dart' as apple;
import '../../firebase/firebase.dart' as fb;
import '../../md_renderer.dart';
import 'package:strnadi/navigation/session_navigation.dart';

Logger logger = Logger();

class RegMail extends StatefulWidget {
  const RegMail({super.key});

  @override
  State<RegMail> createState() => _RegMailState();
}

class _RegMailState extends State<RegMail> {
  static const UserController _userController = UserController();

  bool _isChecked = false;
  final TextEditingController _emailController = TextEditingController();

  late bool _termsError = false;
  String? _emailErrorMessage;
  int _emailValidationGeneration = 0;

  bool _isLoading = false;

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  // Guards against duplicate presses and ensures loader is shown/hidden
  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // already running; ignore duplicate press
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  Future<void> cacheUserData(int userID) async {
    try {
      final response = await _userController.getUserById(userID);
      if (response.statusCode == 200) {
        final dynamic raw = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (raw is! Map) {
          logger.w('Failed to parse user profile payload: ${raw.runtimeType}');
          return;
        }
        final Map<String, dynamic> jsonResponse = raw.cast<String, dynamic>();
        String firstName = jsonResponse['firstName'];
        String lastName = jsonResponse['lastName'];
        String nick = jsonResponse['nickname'];
        String role = jsonResponse['role'];
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        await secureStorage.write(key: 'firstName', value: firstName);
        await secureStorage.write(key: 'lastName', value: lastName);
        await secureStorage.write(key: 'nick', value: nick);
        await secureStorage.write(key: 'role', value: role);

        logger.i('Fetched user profile metadata.');
      } else {
        logger.w(
            'Failed to fetch user name. Status code: ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      logger.e('Error fetching user name: $error',
          error: error, stackTrace: stackTrace);
      await Sentry.captureException(error, stackTrace: stackTrace);
    }
  }

  bool isValidEmail(String email) {
    return EmailValidator.isValid(email);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('auth.buttons.ok')))
        ],
      ),
    );
  }

  Future<bool> _checkEmail(String email) async {
    final normalizedEmail = EmailValidator.normalize(email);
    final response = await _userController.checkEmailExists(normalizedEmail);
    if ([200, 404].contains(response.statusCode)) {
      return false; // Email exists (or JWT received)
    } else if (response.statusCode == 409) {
      //_showUserExistsPopup();
      return true;
    } else {
      logger.w('Failed to check email; status ${response.statusCode}.');
      return true;
    }
  }

  String _normalizeEmailInput() {
    final email = EmailValidator.normalize(_emailController.text);
    if (_emailController.text != email) {
      _emailController.value = TextEditingValue(
        text: email,
        selection: TextSelection.collapsed(offset: email.length),
      );
    }
    return email;
  }

  Future<void> _validateEmailAvailability(String value) async {
    final int generation = ++_emailValidationGeneration;
    final String email = EmailValidator.normalize(value);
    if (!isValidEmail(email)) {
      if (!mounted || generation != _emailValidationGeneration) return;
      setState(() {
        _emailErrorMessage = t('signup.mail.errors.mail_format_err');
      });
      return;
    }

    if (mounted) {
      setState(() {
        _emailErrorMessage = null;
      });
    }
    final bool emailExists = await _checkEmail(email);
    if (!mounted ||
        generation != _emailValidationGeneration ||
        EmailValidator.normalize(_emailController.text) != email) {
      return;
    }
    setState(() {
      _emailErrorMessage =
          emailExists ? t('signup.mail.errors.mail_exists') : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    // Whether all fields are valid
    final bool formValid = isValidEmail(_emailController.text) &&
        _isChecked &&
        _emailErrorMessage == null;

    // Optional: Prevent back navigation during loading
    return WillPopScope(
        onWillPop: () async => !_isLoading,
        child: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: IconButton(
                  icon: Image.asset('assets/icons/backButton.png',
                      width: 30, height: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              backgroundColor: Colors.white,
              body: SafeArea(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        t('signup.mail.title'),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // "E-mail" label
                      Text(
                        t('login.inputs.emailLabel'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Email TextField
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textCapitalization: TextCapitalization.none,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        inputFormatters: const [LowerCaseEmailInputFormatter()],
                        autofillHints: const [
                          AutofillHints.newUsername,
                          AutofillHints.email,
                        ],
                        onChanged: (value) {
                          unawaited(_validateEmailAvailability(value));
                        },
                        decoration: InputDecoration(
                          fillColor: Colors.grey[200],
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          errorText: _emailErrorMessage,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Smaller grey background for terms
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Custom checkbox
                            CheckboxTheme(
                              data: CheckboxThemeData(
                                side: _isChecked
                                    ? const BorderSide(
                                        width: 0, color: Colors.transparent)
                                    : const BorderSide(
                                        width: 2, color: Colors.grey),
                              ),
                              child: Checkbox(
                                value: _isChecked,
                                onChanged: (bool? newValue) {
                                  setState(() {
                                    _isChecked = newValue ?? false;
                                  });
                                },
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                fillColor:
                                    MaterialStateProperty.resolveWith((states) {
                                  if (states.contains(MaterialState.selected)) {
                                    return Colors.black;
                                  }
                                  return Colors.white;
                                }),
                                checkColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(color: Colors.black),
                                  children: [
                                    TextSpan(
                                      text: t('signup.mail.consent.con1'),
                                    ),
                                    TextSpan(
                                      text: t('signup.mail.consent.con2'),
                                      style: TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => MDRender(
                                                mdPath:
                                                    'assets/docs/terms-of-services.md',
                                                title: t('auth.terms.title'),
                                              ),
                                            ),
                                          );
                                        },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_termsError)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            t('signup.mail.errors.continue_consent'),
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Larger "Pokračovat" button (full width)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: !_isLoading
                              ? () {
                                  _withLoader(() async {
                                    final email = _normalizeEmailInput();
                                    try {
                                      final bool emailExists =
                                          await _checkEmail(email);
                                      if (!mounted) return;
                                      setState(() {
                                        if (!isValidEmail(email)) {
                                          _emailErrorMessage = t(
                                              'signup.mail.errors.mail_format_err');
                                        } else if (emailExists) {
                                          _emailErrorMessage = t(
                                              'signup.mail.errors.mail_exists');
                                        } else {
                                          _emailErrorMessage = null;
                                        }
                                        _termsError = !_isChecked;
                                      });
                                      if (isValidEmail(email) &&
                                          _isChecked &&
                                          !emailExists) {
                                        if (!context.mounted) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => RegPassword(
                                              email: email,
                                              jwt: '',
                                              consent: true,
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (_) {
                                      // _checkEmail already exposes the
                                      // localized request failure.
                                    }
                                  });
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            backgroundColor: formValid ? yellow : Colors.grey,
                            foregroundColor:
                                formValid ? textColor : Colors.white,
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

                      const SizedBox(height: 32),

                      // Google sign-in section
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(t('login.or')),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.grey.shade300,
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: !_isLoading
                              ? () {
                                  if (!_isChecked) {
                                    setState(() {
                                      _termsError = true;
                                    });
                                    return;
                                  }
                                  _withLoader(() async {
                                    try {
                                      logger.i('Google button clicked');
                                      Map<String, dynamic>? data = await gle
                                          .GoogleSignInService.googleAuth();
                                      if (data == null) {
                                        logger.w(
                                            'Google sign in returned null data');
                                        return;
                                      }
                                      if (data['status'] == 200) {
                                        logger.i(
                                            'Google sign in succeeded; existing=${data['exists']}.');
                                        if (data['exists'] == false) {
                                          // New user, proceed with registration
                                          logger.i(
                                              'Google sign in: new user, proceeding to registration');
                                          if (!context.mounted) return;
                                          Navigator.pushReplacement(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) => RegName(
                                                        name: data['firstName']
                                                                as String? ??
                                                            '',
                                                        surname: data[
                                                                    'lastName']
                                                                as String? ??
                                                            '',
                                                        email: data['email']
                                                                as String? ??
                                                            '',
                                                        jwt: data['jwt']
                                                            as String,
                                                        consent: true,
                                                      )));
                                          return;
                                        }
                                        final String? jwt =
                                            data['jwt'] as String?;
                                        if (jwt == null || jwt.trim().isEmpty) {
                                          _showMessage(
                                              t('login.errors.loginFailed'));
                                          return;
                                        }
                                        final AuthSessionTransition transition =
                                            await activatedAuthSessions
                                                .beginTokenTransition(jwt);

                                        // Retrieve user‑id from backend
                                        final idResponse = await _userController
                                            .getUserIdFromToken();
                                        if (idResponse.statusCode != 200) {
                                          logger.e(
                                              'Failed to retrieve user ID; status ${idResponse.statusCode}.');
                                          _showMessage(
                                              t('login.errors.idGetError'));
                                          return;
                                        }
                                        final int? userId = int.tryParse(
                                            idResponse.data.toString());
                                        if (userId == null || userId <= 0) {
                                          _showMessage(
                                              t('login.errors.idGetError'));
                                          return;
                                        }
                                        await activatedAuthSessions.activate(
                                          transition,
                                          userId,
                                          verified: true,
                                        );
                                        logger.i(
                                            'Google sign-in session activated');
                                        await cacheUserData(userId);
                                        await fb.refreshToken();
                                        if (!context.mounted) return;
                                        await navigateToSessionLanding(context);
                                      } else {
                                        logger.w(
                                            'Google sign in failed with status ${data['status']}.');
                                        _showMessage(
                                            t('login.errors.loginFailed'));
                                        return;
                                      }
                                    } catch (error, stackTrace) {
                                      logger.e('Google sign in error: $error',
                                          error: error, stackTrace: stackTrace);
                                      await Sentry.captureException(error,
                                          stackTrace: stackTrace);
                                      _showMessage(
                                          t('login.errors.loginFailed'));
                                    }
                                    /*
                      await gle.GoogleSignInService.signUpWithGoogle().then((user) {
                        if (user != null && user['status'] != 409) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RegName(
                                email: JwtDecoder.decode(user['jwt'])['sub'],
                                jwt: user['jwt'],
                                name: user['firstName'],
                                surname: user['lastName'],
                                consent: true,
                              ),
                            ),
                          );
                        } else if (user != null && user['status'] == 409) {
                          _showUserExistsPopup();
                        }
                      }).catchError((error) {
                        setState(() {
                          _emailErrorMessage = t('signup.mail.errors.google_login_failed');
                        });
                        logger.e(error);
                        Sentry.captureException(error);
                      });
                      */
                                  });
                                }
                              : null,
                          icon: Image.asset(
                            'assets/images/google.webp',
                            height: 24,
                            width: 24,
                          ),
                          label: Text(
                            t('login.buttons.googleSignIn'),
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: !_isLoading
                              ? () {
                                  if (!_isChecked) {
                                    setState(() => _termsError = true);
                                    return;
                                  }
                                  _withLoader(() async {
                                    logger.i('Apple button clicked');
                                    try {
                                      final data =
                                          await apple.AppleAuth.signInAndGetJwt(
                                              null);
                                      if (data == null) {
                                        logger.w(
                                            'Apple sign in return data null');
                                        return;
                                      } else if (data['status'] == 200) {
                                        logger.i(
                                            'Apple sign in succeeded; existing=${data['exists']}.');
                                        if (data['exists'] == false) {
                                          logger.i(
                                              'Apple sign in: new user, proceeding to registration');
                                          if (!context.mounted) return;
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => RegName(
                                                name: data['firstName']
                                                        as String? ??
                                                    '',
                                                surname: data['lastName']
                                                        as String? ??
                                                    '',
                                                email:
                                                    data['email'] as String? ??
                                                        '',
                                                jwt: data['jwt'] as String,
                                                appleId: data['userIdentifier']
                                                        as String? ??
                                                    '',
                                                consent: true,
                                              ),
                                            ),
                                          );
                                          return;
                                        } else if (data['exists'] == true) {
                                          // User exists, proceed with login
                                        }
                                      } else if (data['status'] == 400) {
                                        logger.w(
                                            'Apple sign in failed: no email returned');
                                        _showMessage(
                                            t('auth.apple.error.no_email'));
                                        return;
                                      } else {
                                        logger.w(
                                            'Apple sign in failed with status ${data['status']}.');
                                        _showMessage(
                                            t('auth.apple.error.login_failed'));
                                        return;
                                      }

                                      final String? firstName =
                                          data['firstName'] as String?;
                                      final String? lastName =
                                          data['lastName'] as String?;
                                      final String? email =
                                          data['email'] as String?;

                                      if ((firstName != null &&
                                          lastName != null &&
                                          email != null &&
                                          firstName.isEmpty &&
                                          lastName.isEmpty &&
                                          email.isEmpty)) {
                                        if (!context.mounted) return;
                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => RegName(
                                              name: firstName,
                                              surname: lastName,
                                              email: email,
                                              jwt: data['jwt'] as String,
                                              consent: true,
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      final String jwt = data['jwt'] as String;
                                      final AuthSessionTransition transition =
                                          await activatedAuthSessions
                                              .beginTokenTransition(jwt);
                                      logger.i(
                                          'Apple sign-in token transition started');

                                      final idResponse = await _userController
                                          .getUserIdFromToken();
                                      if (idResponse.statusCode != 200) {
                                        logger.w(
                                            'Failed to retrieve user ID; status ${idResponse.statusCode}.');
                                        _showMessage(
                                            t('login.errors.idGetError'));
                                        return;
                                      }
                                      final int? userId = int.tryParse(
                                          idResponse.data.toString());
                                      if (userId == null || userId <= 0) {
                                        _showMessage(
                                            t('login.errors.idGetError'));
                                        return;
                                      }
                                      logger.i('Apple login owner resolved.');

                                      await activatedAuthSessions.activate(
                                        transition,
                                        userId,
                                        verified: true,
                                      );
                                      await fb.refreshToken();
                                      await cacheUserData(userId);

                                      if (!context.mounted) return;
                                      await navigateToSessionLanding(context);
                                    } catch (e, stackTrace) {
                                      logger.e('Apple sign in error: $e');
                                      Sentry.captureException(e,
                                          stackTrace: stackTrace);
                                      _showMessage(
                                          t('auth.apple.error.login_failed'));
                                    }
                                  });
                                }
                              : null,
                          icon: Image.asset(
                            'assets/images/apple.png',
                            height: 24,
                            width: 24,
                          ),
                          label: Text(
                            t('signup.mail.buttons.con_apple'),
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, top: 16, bottom: 48),
                child: Row(
                  children: List.generate(5, (index) {
                    bool completed = index < 1;
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
            if (_isLoading)
              Positioned.fill(
                child: AbsorbPointer(
                  absorbing: true,
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
          ],
        ));
  }
}
