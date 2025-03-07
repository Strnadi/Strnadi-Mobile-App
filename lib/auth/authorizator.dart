/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/firebase/firebase.dart' as firebase;

enum AuthType { login, register }

class Authorizator extends StatefulWidget {
  final Widget login;
  final Widget register;

  const Authorizator({
    Key? key,
    required this.login,
    required this.register,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}

Future<bool> isLoggedIn() async {
  final secureStorage = FlutterSecureStorage();
  final token = await secureStorage.read(key: 'token');
  if (token != null) {
    final Uri url = Uri.parse('https://api.strnadi.cz/users')
        .replace(queryParameters: {'jwt': token});
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return true;

      } else {
        return false;
      }
    } catch (error) {
      Sentry.captureException(error);
      return false;
    }
  }
  return false;
}



class _AuthState extends State<Authorizator> {
  @override
  void initState() {
    super.initState();
    checkLoggedIn(); // token check if needed
  }

  @override
  Widget build(BuildContext context) {
    // Return the complete login screen without extra wrapping.
    return widget.login;
  }
  void _showMessage(String message) {
    // This will work fine now as long as it's called from a valid Material context.
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

  Future<void> checkLoggedIn() async{
    FlutterSecureStorage secureStorage = FlutterSecureStorage();
    if(await isLoggedIn()) {
      String? token = await secureStorage.read(key: 'token');

      if (token != null) {
        final Uri url = Uri.parse('https://api.strnadi.cz/users')
            .replace(queryParameters: {'jwt': token});

        final response = await http.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': token,
          }
        );

        final Map<String, dynamic> data = jsonDecode(response.body);
        secureStorage.write(key: 'user', value: data['firstName']);
        secureStorage.write(key: 'lastname', value: data['lastName']);
        // If you plan to navigate here, consider scheduling it in a post-frame callback.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LiveRec()),
        );
      }
    }
    else {
      _showMessage("Byli jste odhlášeni");
      secureStorage.delete(key: 'token');
      secureStorage.delete(key: 'user');
      secureStorage.delete(key: 'lastname');
      firebase.deleteToken();
    }
  }

}
