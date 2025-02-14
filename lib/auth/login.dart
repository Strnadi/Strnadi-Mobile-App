/*
 * Copyright (C) 2024 [Your Name]
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
import 'package:strnadi/home.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Login extends StatefulWidget {
  const Login({ super.key });

  @override
  State<Login> createState() => _LoginState();

}

class _LoginState extends State<Login> {

  final _GlobalKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  void checkAuth() async {
    final secureStorage = FlutterSecureStorage();
    var containsKey = await secureStorage.containsKey(key: 'token');

    if (containsKey) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => HomePage()));
    }
  }

  void login() async{

    final secureStorage = FlutterSecureStorage();


    final email = _emailController.text;
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Please fill in both fields');
      return;
    }

    final url = Uri(scheme: 'https', host: 'strnadiapi.slavetraders.tech', path: '/auth/login');


    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 202 || response.statusCode == 200) { //202 -- Accepted
        final data = response.body;

        secureStorage.write(key: 'token', value: data.toString());

        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => HomePage()),
        );

      }
      else if (response.statusCode == 401){
        _showMessage('Uživatel s daným emailem a heslem neexistuje');
      }
      else {
        _showMessage('Nastala chyba :( Zkuste to znovu');
        print('Login failed: ${response.statusCode}');
        print('Error: ${response.body}');
      }
    } catch (error) {
      _showMessage('Nastala chyba :( Zkuste to znovu');
      print('An error occurred: $error');
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Login'),
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
    checkAuth();
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            const Text(
              'Navrat Krale',
              style: TextStyle(fontSize: 60),
            ),
            const SizedBox(height: 20),
            Form(
              key: _GlobalKey,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                          ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                            .hasMatch(value)) {
                          return 'Enter valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      textAlign: TextAlign.center,
                      controller: _passwordController,
                      decoration: InputDecoration(
                        label: RichText(
                          text: TextSpan(
                            text: 'Password',
                            children: const <TextSpan>[
                              TextSpan(
                                text: ' *',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter some text';
                        }
                        return null;
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ButtonStyle(
                            shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                          ),
                          onPressed: login,
                          child: const Text('Submit'),

                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
