/*
 * Copyright (C) 2024 Marian Pecqueur && Jan Dorbilek
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

import 'package:strnadi/auth/authorizator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'package:strnadi/archived/recorderWithSpectogram.dart';

class Register extends StatefulWidget {
  const Register({super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _NickController = TextEditingController();
  final TextEditingController _NameController = TextEditingController();
  final TextEditingController _SurnameController = TextEditingController();

  late bool _termsAgreement = false;

  void register() async {
    final secureStorage = FlutterSecureStorage();
    final email = _emailController.text;
    final password = _passwordController.text;
    final name = _NameController.text;
    final surname = _SurnameController.text;
    final nickname = _NickController.text == "" ? _NickController.text : null;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in both fields');
      return;
    }

    if (!RegExp(
            r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
        .hasMatch(email)) {
      _showMessage('Please fill in valid email');
      return;
    }

    // TODO add consent field to the registration form
    final url = Uri.parse('https://api.strnadi.cz/auth/sign-up');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
          'FirstName': name,
          'LastName': surname,
          'nickname': nickname,
          'consent': true // TODO add consent field to the registration form
        }),
      );

      if (response.statusCode == 201) {
        //201 -- Created
        final data = response.body;

        secureStorage.write(key: 'token', value: data.toString());

        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RecorderWithSpectogram()),
        );
      } else {
        print('Sign up failed: ${response.statusCode}');
        print('Error: ${response.body}');
        _showMessage("Sign up failed: ${response.statusCode}");
      }
    } catch (error) {
      print('An error occurred: $error');
      _showMessage("An error occurred: $error");
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

  @override
  Widget build(BuildContext context) {

    return Scaffold(
        appBar: AppBar(title: const Text('Registrace')),
        body: Center(
          child: Form(
            key: _GlobalKey,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Strnadi',
                    style: TextStyle(fontSize: 60),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _NickController,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _NameController,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _SurnameController,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Surname',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _emailController,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    textAlign: TextAlign.center,
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.visiblePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter some text';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  CheckboxListTile(
                    title: const Text('I agree to the terms and conditions'),
                    value: _termsAgreement,
                    onChanged: (value) {
                      setState(() {
                        _termsAgreement = value!;
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ButtonStyle(
                          shape:
                              WidgetStateProperty.all<RoundedRectangleBorder>(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                        ),
                        onPressed: register,
                        child: const Text('Submit'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
  }
}
