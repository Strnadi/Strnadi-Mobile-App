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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/auth/email_validator.dart';
import 'package:strnadi/auth/appleAuth.dart' as apple;
import 'package:strnadi/auth/google_sign_in_service.dart' as google;
import 'package:strnadi/auth/registeration/nameReg.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/privacy/tracking_consent.dart';
import 'package:strnadi/navigation/session_navigation.dart';

import 'passReset/forgottenPassword.dart';
import 'registeration/mail.dart';
import 'unverifiedEmail.dart';

final logger = Logger();

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  static const AuthController _authController = AuthController();
  static const UserController _userController = UserController();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late TapGestureRecognizer _registerTapRecognizer;

  bool _isLoading = false;
  void _showLoader() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
  }

  void _hideLoader() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  void _trackLogin({
    required String method,
    required int userId,
    required bool verified,
  }) {
    unawaited(TrackingConsentManager.identifyUser(userId.toString()));
    unawaited(TrackingConsentManager.captureEvent(
      verified ? 'login_success' : 'login_requires_verification',
      properties: {'method': method},
    ));
  }

  void _finishCredentialAutofill() {
    // Triggers iOS/Android password managers to offer saving credentials.
    TextInput.finishAutofillContext(shouldSave: true);
  }

  @override
  void initState() {
    super.initState();

    _registerTapRecognizer = TapGestureRecognizer()
      ..onTap = () {
        if (_isLoading) return;
        _withLoader(() async {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const RegMail()),
          );
        });
      };
  }

  /// Helper function to show loader, run [fn], and then hide loader.
  Future<void> _withLoader(Future<void> Function() fn) async {
    _showLoader();
    try {
      await fn();
    } finally {
      _hideLoader();
    }
  }

  @override
  void dispose() {
    _registerTapRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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

        logger.i("Fetched user name: $firstName $lastName");
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

  void login() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      _showMessage(t('login.errors.emptyFieldsError'));
      return;
    }

    if (!EmailValidator.isValid(email)) {
      _showMessage(t('login.errors.invalidEmailError'));
      return;
    }

    try {
      final response = await _authController.login(
        email: email,
        password: _passwordController.text,
      );

      logger.i('Login response status: ${response.statusCode}');
      final String token = response.data.toString();

      if (response.statusCode == 200 || response.statusCode == 202) {
        _finishCredentialAutofill();
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        logger.i("user has logged in with status code ${response.statusCode}");
        if (await secureStorage.read(key: 'token') != null) {
          secureStorage.delete(key: 'token');
        }
        await secureStorage.write(key: 'token', value: token);

        final verifyResponse = await _authController.verifyJwt(token);

        int? userId;
        if (verifyResponse.statusCode == 403) {
          // If the JWT check returns 403, the account is not verified.
          final idResponse = await _userController.getUserIdFromToken();
          if (idResponse.statusCode != 200) {
            _showMessage(t('login.errors.idGetError'));
            return;
          }
          userId = int.parse(idResponse.data.toString());
          await secureStorage.write(key: 'userId', value: userId.toString());
          await cacheUserData(userId);
          _trackLogin(method: 'password', userId: userId, verified: false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EmailNotVerified(
                userEmail: email,
                userId: userId!,
              ),
            ),
          );
          return;
        } else {
          await secureStorage.write(key: 'token', value: token);
          final idResponse = await _userController.getUserIdFromToken();
          if (idResponse.statusCode != 200) {
            _showMessage(t('login.errors.idGetError'));
            return;
          }
          userId = int.parse(idResponse.data.toString());
          await secureStorage.write(key: 'userId', value: userId.toString());
          await cacheUserData(userId);
        }
        await secureStorage.write(key: 'verified', value: 'true');
        if (userId != null) {
          _trackLogin(method: 'password', userId: userId, verified: true);
        }
        logger.i('Login token stored');
        await fb.refreshToken();
        DatabaseNew.syncRecordings();
        await navigateToSessionLanding(context);
      } else if (response.statusCode == 403) {
        _finishCredentialAutofill();
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        await secureStorage.write(key: 'token', value: token);
        final idResponse = await _userController.getUserIdFromToken();
        if (idResponse.statusCode != 200) {
          _showMessage(t('login.errors.idGetError'));
          return;
        }
        int userId = int.parse(idResponse.data.toString());
        await secureStorage.write(key: 'userId', value: userId.toString());
        await cacheUserData(userId);
        _trackLogin(method: 'password', userId: userId, verified: false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmailNotVerified(
              userEmail: _emailController.text,
              userId: userId,
            ),
          ),
        );
      } else if (response.statusCode == 401) {
        _showMessage(t('login.errors.invalidCredentials'));
      } else {
        logger.w(
            'Login failed: Code: ${response.statusCode} message: ${response.data}');
        _showMessage(t('login.errors.loginFailed'));
      }
    } catch (error, stackTrace) {
      logger.e('An error has occured when logging in $error',
          error: error, stackTrace: stackTrace);
      Sentry.captureException(error, stackTrace: stackTrace);
      _showMessage(t('login.errors.connection'));
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
              child: Text(t('auth.buttons.ok')))
        ],
      ),
    );
  }

  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    const Color yellowishBlack = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    Widget mainContent = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Spacing from the top (additional to AppBar)
            const SizedBox(height: 20),

            // Title: "Přihlášení"
            Text(
              t('login.title'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- E-mail label and TextField ---
                  Text(
                    t('login.inputs.emailLabel'),
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
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
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
                    t('login.inputs.passwordLabel'),
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
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => login(),
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
                ],
              ),
            ),

            // "Zapomenuté heslo?" aligned to the right
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: !_isLoading
                    ? () {
                        _withLoader(() async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgottenPassword(),
                            ),
                          );
                        });
                      }
                    : null,
                child: Text(t('login.buttons.forgotPassword')),
              ),
            ),

            const SizedBox(height: 24),

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
                onPressed: () async {
                  logger.i('Google button clicked');
                  _showLoader();
                  try {
                    Map<String, dynamic>? data =
                        await google.GoogleSignInService.googleAuth();
                    if (data == null) {
                      logger.w('Google sign in returned null data');
                      return;
                    }
                    if (data['status'] == 200) {
                      logger.i(
                          'Google sign in successful, returned data: ${data.toString()}');
                      if (data['exists'] == false) {
                        // New user, proceed with registration
                        unawaited(TrackingConsentManager.captureEvent(
                            'signup_start',
                            properties: {'method': 'google'}));
                        logger.i(
                            'Google sign in: new user, proceeding to registration');
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RegName(
                                      name: data['firstName'] as String? ?? '',
                                      surname:
                                          data['lastName'] as String? ?? '',
                                      email: data['email'] as String? ?? '',
                                      jwt: data['jwt'] as String,
                                      consent: true,
                                    )));
                        return;
                      }
                      String? jwt = data['jwt'] as String?;
                      final secureStorage = const FlutterSecureStorage();
                      // Persist the token locally
                      await secureStorage.write(key: 'token', value: jwt);
                      await secureStorage.write(
                          key: 'verified', value: true.toString());
                      logger.i('Google sign‑in successful, token stored');

                      // Retrieve user‑id from backend
                      final idResponse =
                          await _userController.getUserIdFromToken();
                      if (idResponse.statusCode != 200) {
                        logger.e(
                            'Failed to retrieve user ID: ${idResponse.statusCode} | ${idResponse.data}');
                        _showMessage(t('login.errors.idGetError'));
                        return;
                      }
                      final userId = int.parse(idResponse.data.toString());
                      await secureStorage.write(
                          key: 'userId', value: userId.toString());
                      await cacheUserData(userId);
                      _trackLogin(
                        method: 'google',
                        userId: userId,
                        verified: true,
                      );
                      await fb.refreshToken();
                      await navigateToSessionLanding(context);
                    } else {
                      logger.w(
                          'Google sign in failed with status code: ${data['status']} | ${data.toString()}');
                      _showMessage(t('login.errors.loginFailed'));
                      return;
                    }
                  } catch (e, stackTrace) {
                    logger.e('Google sign-in error: $e',
                        error: e, stackTrace: stackTrace);
                    await Sentry.captureException(e, stackTrace: stackTrace);
                    _showMessage(t('login.errors.loginFailed'));
                    return;
                  } finally {
                    _hideLoader();
                  }
                },
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
                onPressed: () async {
                  _showLoader();
                  logger.i('Apple button clicked');

                  // Start Apple sign‑in flow
                  try {
                    final data = await apple.AppleAuth.signInAndGetJwt(null);
                    if (data == null) {
                      logger.w('Apple sign in return data null');
                      _hideLoader();
                      // User cancelled or sign‑in failed
                      return;
                    } else if (data['status'] == 200) {
                      logger.i(
                          'Apple sign in successful, returned data: ${data.toString()}');
                      if (data['exists'] == false) {
                        // New user, proceed with registration
                        unawaited(TrackingConsentManager.captureEvent(
                            'signup_start',
                            properties: {'method': 'apple'}));
                        _hideLoader();
                        logger.i(
                            'Apple sign in: new user, proceeding to registration');
                        Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => RegName(
                                      name: data['firstName'] as String? ?? '',
                                      surname:
                                          data['lastName'] as String? ?? '',
                                      email: data['email'] as String? ?? '',
                                      jwt: data['jwt'] as String,
                                      appleId:
                                          data['userIdentifier'] as String? ??
                                              '',
                                      consent: true,
                                    )));
                        return;
                      } else if (data['exists'] == true) {
                        // User exists, proceed with login
                      }
                    } else if (data['status'] == 400) {
                      _hideLoader();
                      logger.w('Apple sign in failed: no email returned');
                      _showMessage(t('auth.apple.error.no_email'));
                      return;
                    } else {
                      logger.w(
                          'Apple sign in failed with status code: ${data['status']} | ${data.toString()}');
                      _hideLoader();
                      _showMessage(t('auth.apple.error.login_failed'));
                      return;
                    }

                    // Check if we already have the user's full name
                    final String? firstName = data['firstName'] as String?;
                    final String? lastName = data['lastName'] as String?;
                    final String? email = data['email'] as String?;

                    if ((firstName != null &&
                        lastName != null &&
                        email != null &&
                        firstName.isEmpty &&
                        lastName.isEmpty &&
                        email.isEmpty)) {
                      // Missing profile data → go to the registration screen
                      _hideLoader();
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
                    final secureStorage = const FlutterSecureStorage();

                    // Persist the token locally
                    await secureStorage.write(key: 'token', value: jwt);
                    await secureStorage.write(
                        key: 'verified', value: true.toString());
                    logger.i('Apple sign‑in successful, token stored');

                    // Retrieve user‑id from backend
                    final idResponse =
                        await _userController.getUserIdFromToken();
                    if (idResponse.statusCode != 200) {
                      _hideLoader();
                      logger.w(
                          'Failed to retrieve user ID: ${idResponse.statusCode} | ${idResponse.data}');
                      _showMessage('login.errors.idGetError');
                      return;
                    }
                    final userId = int.parse(idResponse.data.toString());
                    logger.i('User ID retrieved: $userId');

                    await secureStorage.write(
                        key: 'userId', value: userId.toString());
                    _trackLogin(
                      method: 'apple',
                      userId: userId,
                      verified: true,
                    );
                    await fb.refreshToken();

                    // Get users data

                    await cacheUserData(userId);
                    _hideLoader();

                    await navigateToSessionLanding(context);
                  } catch (e, stackTrace) {
                    logger.e('Apple sign-in error: $e',
                        error: e, stackTrace: stackTrace);
                    await Sentry.captureException(e, stackTrace: stackTrace);
                    _hideLoader();
                    _showMessage(t('auth.apple.error.login_failed'));
                    return;
                  }
                },
                icon: Image.asset(
                  'assets/images/apple.png',
                  height: 24,
                  width: 24,
                ),
                label: Text(
                  t('login.buttons.appleSignIn'),
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
    );

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: Image.asset('assets/icons/backButton.png',
                  width: 30, height: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: mainContent,
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  login();
                },
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  backgroundColor: yellow,
                  foregroundColor: yellowishBlack,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
                child: Text(t('auth.buttons.login')),
              ),
            ),
          ),
        ),
        if (_isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
