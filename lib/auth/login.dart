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
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart';
import '../recording/streamRec.dart';
import 'registeration/mail.dart';

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
        Navigator.push(
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

  void login() async {
    final url = Uri.https('strnadiapi.slavetraders.tech', '/auth/login');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text,
          'password': _passwordController.text,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        await const FlutterSecureStorage()
            .write(key: 'token', value: response.body);
        Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRec()));
      } else {
        logger.w('Login failed: ${response}');
        _showMessage('Přihlášení selhalo, zkuste to znovu');
      }
    } catch (error) {
      logger.e(error);
      _showMessage('Chyba připojení');
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Strnadi',
                  style: TextStyle(fontSize: 70, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Heslo',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Zapomenuté heslo?', style: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: login,
                child: const Text('Přihlásit se'),
              ),
              const SizedBox(height: 16),
              Center(
                child: RichText(
                  text: TextSpan(
                    text: 'Nemáte účet? ',
                    style: const TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: 'Zaregistrovat se',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        recognizer: _registerTapRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text.rich(
                  TextSpan(
                    text: 'pokračováním souhlasíte s ',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    children: [
                      TextSpan(
                        text: 'zásadami ochrany osobních údajů.',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
