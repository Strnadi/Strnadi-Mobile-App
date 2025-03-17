// dart
// lib/user/userPage.dart
/*
 \* Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 \* This program is free software: you can redistribute it and/or modify
 \* it under the terms of the GNU General Public License as published by
 \* the Free Software Foundation, either version 3 of the License, or
 \* (at your option) any later version.
 \*
 \* This program is distributed in the hope that it will be useful,
 \* but WITHOUT ANY WARRANTY; without even the implied warranty of
 \* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 \* GNU General Public License for more details.
 \*
 \* along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/HealthCheck/serverHealth.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/user/settingsList.dart';
import '../main.dart';
import 'package:strnadi/firebase/firebase.dart' as strnadiFirebase;

class UserPage extends StatefulWidget {
  const UserPage({Key? key}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late String userName = 'username';
  late String lastName = 'lastname';

  final logger = Logger();

  @override
  void initState() {
    super.initState();
    getUsername();
  }

  void getUsername() async {
    final secureStorage = const FlutterSecureStorage();
    final usernameExists = await secureStorage.containsKey(key: 'user');
    if (usernameExists) {
      var storedUserName = await secureStorage.read(key: 'user');
      var storedLastName = await secureStorage.read(key: 'lastname');
      setState(() {
        userName = storedUserName!;
        lastName = storedLastName!;
      });
      logger.i("user name was cached");
      return;
    }

    final jwt = await secureStorage.read(key: 'token');
    final String email = await JwtDecoder.decode(jwt!)['sub'];
    final Uri url = Uri.parse('https://api.strnadi.cz/users/${email}');

    print("url: $url");

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt'
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          userName = data['firstName'];
          lastName = data['lastName'];
        });
        secureStorage.write(key: 'user', value: data['firstName']);
        secureStorage.write(key: "lastname", value: data['lastName']);
      }
    } catch (error) {
      Sentry.captureException(error);
    }
  }

  void logout(BuildContext context) {
    final localStorage = const FlutterSecureStorage();
    localStorage.delete(key: 'token');
    localStorage.delete(key: 'user');
    localStorage.delete(key: 'lastname');

    strnadiFirebase.deleteToken();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MyApp()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'User Page',
      logout: () => logout(context),
      content: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            height: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage:
                      const AssetImage('./assets/images/default.jpg'),
                ),
                Text(
                  "$userName $lastName",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          MenuScreen()
        ],
      ),
    );
  }
}
