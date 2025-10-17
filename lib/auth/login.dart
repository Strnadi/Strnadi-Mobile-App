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
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/auth/launch_warning.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:url_launcher/url_launcher.dart';
import '../recording/streamRec.dart';
import 'passReset/forgottenPassword.dart';
import 'registeration/mail.dart';
import 'unverifiedEmail.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;
import 'package:strnadi/auth/google_sign_in_service.dart' as google;
import 'package:strnadi/auth/appleAuth.dart' as apple;
import 'package:strnadi/auth/registeration/nameReg.dart';

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
        Navigator.pushReplacement(
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

  void CacheUserData(int userID) {
    Uri url = Uri(scheme: 'https', host: Config.host, path: '/users/$userID');

    http.get(url, headers: {'Content-Type': 'application/json'}).then(
        (http.Response response) {
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);
        String firstName = jsonResponse['firstName'];
        String lastName = jsonResponse['lastName'];
        String nick = jsonResponse['nickname'];
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        secureStorage.write(key: 'firstName', value: firstName);
        secureStorage.write(key: 'lastName', value: lastName);
        secureStorage.write(key: 'nick', value: nick);

        logger.i("Fetched user name: $firstName $lastName");
      } else {
        logger.w(
            'Failed to fetch user name. Status code: ${response.statusCode}');
      }
    }).catchError((error, stackTrace) {
      logger.e('Error fetching user name: $error',
          error: error, stackTrace: stackTrace);
      Sentry.captureException(error, stackTrace: stackTrace);
    });
  }

  void login() async {
    final url = Uri.https(Config.host, '/auth/login');

    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showMessage("Vyplňte email i heslo");
      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(_emailController.text)) {
      _showMessage("Zadejte platný e-mail");
      return;
    }


    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      logger.i('Login response: ${response.statusCode} | ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 202) {
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        logger.i("user has logged in with status code ${response.statusCode}");
        if (await secureStorage.read(key: 'token') != null) {
          secureStorage.delete(key: 'token');
        }
        await secureStorage.write(
            key: 'token', value: response.body.toString());

        final verifyUrl = Uri.https(Config.host, '/auth/verify-jwt');

        final verifyResponse = await http.get(
          verifyUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${response.body.toString()}',
          },
        );

        if (verifyResponse.statusCode == 403) {
          // If the JWT check returns 403, the account is not verified.
          Uri url =
              Uri(scheme: 'https', host: Config.host, path: '/users/get-id');
          var response = await http.get(url, headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await secureStorage.read(key: 'token')}',
          });
          int userId = int.parse(response.body);
          await secureStorage.write(key: 'userId', value: userId.toString());
          CacheUserData(userId);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => EmailNotVerified(
                userEmail: _emailController.text,
                userId: userId,
              ),
            ),
          );
          return;
        } else {
          await secureStorage.write(
              key: 'token', value: response.body.toString());
          Uri url =
              Uri(scheme: 'https', host: Config.host, path: '/users/get-id');
          var idResponse = await http.get(url, headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${response.body.toString()}',
          });
          int userId = int.parse(idResponse.body);
          await secureStorage.write(key: 'userId', value: userId.toString());
          CacheUserData(userId);
        }
        await secureStorage.write(key: 'verified', value: 'true');
        logger.i(response.body);
        await fb.refreshToken();
        DatabaseNew.syncRecordings();
        DatabaseNew.updateRecordingsMail();
        logger.i(DatabaseNew.getAllRecordings());
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
            settings: const RouteSettings(name: '/Recorder'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      } else if (response.statusCode == 403) {
        FlutterSecureStorage secureStorage = FlutterSecureStorage();
        await secureStorage.write(
            key: 'token', value: response.body.toString());
        Uri url =
            Uri(scheme: 'https', host: Config.host, path: '/users/get-id');
        var idResponse = await http.get(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await secureStorage.read(key: 'token')}',
        });
        int userId = int.parse(idResponse.body);
        await secureStorage.write(key: 'userId', value: userId.toString());
        CacheUserData(userId);
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
            'Login failed: Code: ${response.statusCode} message: ${response.body}');
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

    return Scaffold(
      backgroundColor: Colors.white,
      // AppBar with a back button at the top
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon:
              Image.asset('assets/icons/backButton.png', width: 30, height: 30),
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
                      autofillHints: const [AutofillHints.email],
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
                      autofillHints: const [AutofillHints.password],
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
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgottenPassword(),
                      ),
                    );
                    // Handle "Forgot password" here
                  },
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
                  onPressed: () {
                    logger.i('Button clicked');
                    //google.GoogleSignInService _googleSignInService = google.GoogleSignInService();
                    google.GoogleSignInService.signInWithGoogle()
                        .then((jwt) => {
                              if (jwt != null)
                                {
                                  FlutterSecureStorage()
                                      .write(key: 'token', value: jwt),
                                  http.get(
                                      Uri.parse(
                                          'https://${Config.host}/users/get-id'),
                                      headers: {
                                        'Content-Type': 'application/json',
                                        'Authorization': 'Bearer $jwt',
                                      }).then((http.Response response) => {
                                        FlutterSecureStorage().write(
                                            key: 'userId',
                                            value: response.body.toString()),
                                      }),
                                  fb.refreshToken(),
                                  DatabaseNew.updateRecordingsMail(),
                                  Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => LiveRec()))
                                }
                            });
                    // Handle 'Continue with Google' logic here
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
                    logger.i('Apple button clicked');

                    // Start Apple sign‑in flow
                    try {
                      final data = await apple.AppleAuth.signInAndGetJwt(null);
                      if (data == null) {
                        logger.w('Apple sign in return data null');
                        // User cancelled or sign‑in failed
                        return;
                      } else if (data['status'] == 200) {
                        logger.i(
                            'Apple sign in successful, returned data: ${data.toString()}');
                        if (data['exists'] == false) {
                          // New user, proceed with registration
                          logger.i(
                              'Apple sign in: new user, proceeding to registration');
                          Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => RegName(
                                        name:
                                            data['firstName'] as String? ?? '',
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
                        logger.w('Apple sign in failed: no email returned');
                        _showMessage(t('auth.apple.error.no_email'));
                        return;
                      } else {
                        logger.w(
                            'Apple sign in failed with status code: ${data['status']} | ${data.toString()}');
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
                      logger.i('Apple sign‑in successful, token stored');

                      DatabaseNew.updateRecordingsMail();
                      // Retrieve user‑id from backend
                      final idResponse = await http.get(
                        Uri.parse('https://${Config.host}/users/get-id'),
                        headers: {
                          'Content-Type': 'application/json',
                          'Authorization': 'Bearer $jwt',
                        },
                      );
                      if (idResponse.statusCode != 200) {
                        logger.w(
                            'Failed to retrieve user ID: ${idResponse.statusCode} | ${idResponse.body}');
                        _showMessage('Chyba při získávání ID uživatele');
                        return;
                      }
                      logger.i('User ID retrieved: ${idResponse.body}');

                      await secureStorage.write(
                          key: 'userId', value: idResponse.body);
                      await fb.refreshToken();

                      // Get users data

                      CacheUserData(int.parse(idResponse.body));

                      // Go to recorder screen
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => LiveRec()),
                      );
                    } catch (e, stackTrace) {
                      logger.e('Apple sign-in error: $e',
                          error: e, stackTrace: stackTrace);
                      Sentry.captureException(e, stackTrace: stackTrace);
                      _showMessage(t('auth.apple.error.login_failed'));
                      return;
                    }
                  },
                  icon: Image.asset(
                    'assets/images/apple.png',
                    height: 24,
                    width: 24,
                  ),
                  label: const Text(
                    'Pokračovat přes Apple',
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
              elevation: 0,
              shadowColor: Colors.transparent,
              backgroundColor: yellow,
              foregroundColor: yellowishBlack,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: Text(t('auth.buttons.login')),
          ),
        ),
      ),
    );
  }
}
