/*
 * Copyright (C) 2024 Marian Pecqueur && Jan Drobílek
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
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/login.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/auth/registeration/mailSent.dart';

final logger = Logger();

class RegPassword extends StatefulWidget {
  final dynamic email;
  final dynamic consent;
  final dynamic name;
  final dynamic surname;
  final dynamic nickname;

  const RegPassword(
      {super.key,
      required this.email,
      required this.consent,
      required this.name,
      required this.surname,
      required this.nickname});

  @override
  State<RegPassword> createState() => _RegPasswordState();
}

class _RegPasswordState extends State<RegPassword> {
  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _passwordController = TextEditingController();

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

  void register() async {
    final secureStorage = FlutterSecureStorage();

    final url = Uri(
        scheme: 'https',
        host: 'api.strnadi.cz',
        path: '/auth/sign-up');

    logger.i(jsonEncode({
      'email': widget.email,
      'password': _passwordController.text,
      'FirstName': widget.name,
      'LastName': widget.surname,
      'nickname': widget.nickname == "" ? null : widget.nickname
    }));

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': widget.email,
          'password': _passwordController.text,
          'FirstName': widget.name,
          'LastName': widget.surname,
          'nickname': widget.nickname == "" ? null : widget.nickname
        }),
      );

      if (response.statusCode == 201 ||
          response.statusCode == 200 ||
          response.statusCode == 202) {
        //201 -- Created
        final data = response.body;

        logger.i("Sign Up successful");

        secureStorage.write(key: 'token', value: data.toString());

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => Login()),
              (Route<dynamic> route) => false,
        );

      } else if (response.statusCode == 409) {
        _showMessage('Uživatel již existuje');
        logger.w("User already exists");
      } else {
        _showMessage('Nastala chyba :( Zkuste to znovu');
        logger.e(response);
        print('Sign up failed: ${response.statusCode}');
        print('Error: ${response.body}');
      }
    } catch (error) {
      logger.e(error);
      _showMessage('Nastala chyba :( Zkuste to znovu');
      print('An error occurred: $error');
    }
  }

  @override
  Widget build(BuildContext context) {

    final halfScreen = MediaQuery.of(context).size.height * 0.2;

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Form(
          key: _GlobalKey,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: halfScreen),
                  child: Column(
                    children: [
                      const Text(
                        'Nastav te si Heslo',
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          label: RichText(
                            text: TextSpan(
                              text: 'Heslo',
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
                        keyboardType: TextInputType.visiblePassword,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter some text';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ButtonStyle(
                        backgroundColor: MaterialStateProperty.all<Color>(Colors.black),
                        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                      ),
                      onPressed: () {
                        // Validate the form before proceeding with the registration
                        if (_GlobalKey.currentState?.validate() ?? false) {
                          // If validation is successful, call the register function
                          register();
                        } else {
                          // Optionally, show an error message if validation fails
                          _showMessage('Please fix the errors before proceeding.');
                        }
                      },
                      child: Text('Sign Up', style: TextStyle(color: Colors.white)),
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
}
