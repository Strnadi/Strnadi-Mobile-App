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
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'login.dart';

class ForgottenPassword extends StatefulWidget {
  const ForgottenPassword({Key? key}) : super(key: key);

  @override
  _ForgottenPasswordState createState() => _ForgottenPasswordState();
}

class _ForgottenPasswordState extends State<ForgottenPassword> {

  final TextEditingController _emailController = TextEditingController();

  final _GlobalKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {

    // this doesn't makes sense but it works so i will leave it here
    final halfScreen = MediaQuery.of(context).size.height * 0.2;

    return Scaffold(
      body: Center(
        child: Form(
          key: _GlobalKey,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: halfScreen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      const Text(
                        'Zadejte Váš Email Pro Resetování Hesla',
                        style: TextStyle(fontSize: 40, color: Colors.black),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _emailController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          label: RichText(
                            text: TextSpan(
                              text: 'Email',
                              children: const <TextSpan>[
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          if (!RegExp(
                              r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                              .hasMatch(value)) {
                            return 'Enter valid email';
                          }
                          return null;
                        },
                        onFieldSubmitted: (value) {
                          if (_GlobalKey.currentState?.validate() ?? false) {
                            requestPasswordReset(_emailController.text);
                          } else {
                            // Optionally, show an error message if validation fails
                          }
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all<Color>(
                                Colors.black,
                              ),
                              shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                                RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                              ),
                            ),
                            onPressed: () {
                              if (_GlobalKey.currentState?.validate() ?? false) {
                                // Proceed to the next screen if the form is valid
                                requestPasswordReset(_emailController.text);
                              } else {
                                // Optionally, show an error message if validation fails
                                _showMessage('Please fix the errors before proceeding.');
                              }
                            },
                            child: const Text('Resetovat Heslo', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: RichText(
                    text: TextSpan(
                      text: 'By continuing, you agree to the ',
                      style: const TextStyle(color: Colors.black),
                      children: [
                        TextSpan(
                          text: 'Terms of Service',
                          style: const TextStyle(color: Colors.blue),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              launchUrl(Uri.parse('https://new.strnadi.cz/podminky-pouzivani'));
                            },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final uri = Uri.parse('https://api.strnadi.cz/auth/request-password-reset?email=$email');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        _showMessage("Email byl odeslán");
        Navigator.push(context, MaterialPageRoute(builder: (_) => const Login()));
      } else {
        print('Failed to send password reset: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending password reset request: $e');
    }
  }
  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register'),
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