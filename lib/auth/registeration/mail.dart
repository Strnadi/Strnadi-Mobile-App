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
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/auth/registeration/nameReg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strnadi/auth/registeration/passwordReg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/google_sign_in_service.dart' as gle;

import '../../config/config.dart';
import '../../md_renderer.dart';

Logger logger = Logger();

class RegMail extends StatefulWidget {
  const RegMail({super.key});

  @override
  State<RegMail> createState() => _RegMailState();
}

class _RegMailState extends State<RegMail> {
  bool _isChecked = false;
  final TextEditingController _emailController = TextEditingController();

  late bool _termsError = false;
  String? _emailErrorMessage;

  bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  void _showUserExistsPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uživatel již existuje'),
        content: const Text('Uživatel s tímto e-mailem již existuje.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkEmail(String email) async {
    final Uri url = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/users/exists',
      queryParameters: {
        'email': email,
      },
    );
    final response = await http.get(url);
    if ([200, 404].contains(response.statusCode)) {
      return false; // Email exists (or JWT received)
    } else if (response.statusCode == 409) {
      //_showUserExistsPopup();
      return true;
    } else {
      logger.w('Failed to check email: ${response.statusCode} | ${response.body}');
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    // Whether all fields are valid
    final bool formValid = isValidEmail(_emailController.text) && _isChecked && _emailErrorMessage == null;

    return Scaffold(
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                'Zadejte váš e-mail',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              // "E-mail" label
              Text(
                'E-mail',
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
                autocorrect: false,
                onChanged: (value) {
                  setState(() {
                    // Validate email format
                    if (!isValidEmail(value)) {
                      _emailErrorMessage = 'Email není v platném formátu';
                    } else {
                      // Clear the format error and check if email exists
                      _emailErrorMessage = null;
                      _checkEmail(value).then((emailExists) {
                        setState(() {
                          _emailErrorMessage = emailExists ? 'Email již existuje' : null;
                        });
                      });
                    }
                  });
                },
                decoration: InputDecoration(
                  fillColor: Colors.grey[200],
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                            ? const BorderSide(width: 0, color: Colors.transparent)
                            : const BorderSide(width: 2, color: Colors.grey),
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
                        fillColor: MaterialStateProperty.resolveWith((states) {
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
                              text:
                              'Zapojením do projektu občanské vědy Nářečí českých strnadů ',
                            ),
                            TextSpan(
                              text: 'souhlasím s podmínkami',
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
                                        mdPath: 'assets/docs/terms-of-services.md',
                                        title: 'Podmínky používání',
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
                    'Pro pokračování musíte souhlasit s podmínkami.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              // Larger "Pokračovat" button (full width)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _checkEmail(_emailController.text).then((emailExists) {
                      setState(() {
                        if (!isValidEmail(_emailController.text)) {
                          _emailErrorMessage = 'Email není v platném formátu';
                        } else if (emailExists) {
                          _emailErrorMessage = 'Email již existuje';
                        } else {
                          _emailErrorMessage = null;
                        }
                        _termsError = !_isChecked;
                      });
                      if (isValidEmail(_emailController.text) && _isChecked && !emailExists) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RegPassword(
                              email: _emailController.text,
                              jwt: '',
                              consent: true,
                            ),
                          ),
                        );
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    backgroundColor: formValid ? yellow : Colors.grey,
                    foregroundColor: formValid ? textColor : Colors.white,
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
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Nebo'),
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
                    if (!_isChecked) {
                      setState(() {
                        _termsError = true;
                      });
                      return;
                    }
                    gle.GoogleSignInService.signUpWithGoogle().then((user) {
                      if (user != null && user['status']!=409) {
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
                      }
                      else if(user != null && user['status']==409){
                        _showUserExistsPopup();
                      }
                    }).catchError((error) {
                        setState(() {
                          _emailErrorMessage = 'Přihlášení přes Google selhalo';
                        });
                        logger.e(error);
                        Sentry.captureException(error);
                      }
                    );
                    // Handle 'Continue with Google' logic here
                  },
                  icon: Image.asset(
                    'assets/images/google.webp',
                    height: 24,
                    width: 24,
                  ),
                  label: const Text(
                    'Pokračovat přes Google',
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 48),
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
    );
  }
}