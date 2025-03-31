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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/HealthCheck/serverHealth.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/user/settingsList.dart';
import '../main.dart';
import 'package:strnadi/firebase/firebase.dart' as strnadiFirebase;
import 'package:strnadi/debug_menu.dart';

class UserPage extends StatefulWidget {
  const UserPage({Key? key}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late String userName = 'username';
  late String lastName = 'lastname';
  String? profileImagePath;

  final logger = Logger();
  final secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    getUserData();
  }

  void getUserData() async {
    final usernameExists = await secureStorage.containsKey(key: 'user');
    final profileImageExists = await secureStorage.containsKey(key: 'profileImage');

    if (usernameExists) {
      var storedUserName = await secureStorage.read(key: 'user');
      var storedLastName = await secureStorage.read(key: 'lastname');
      var storedProfileImage = profileImageExists ? await secureStorage.read(key: 'profileImage') : null;
      setState(() {
        userName = storedUserName!;
        lastName = storedLastName!;
        profileImagePath = storedProfileImage;
      });
      logger.i("User data loaded from cache");
      return;
    }

    final jwt = await secureStorage.read(key: 'token');
    final String email = JwtDecoder.decode(jwt!)['sub'];
    final Uri url = Uri.parse('https://api.strnadi.cz/users/$email');

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
        secureStorage.write(key: 'lastname', value: data['lastName']);
      }
    } catch (error) {
      Sentry.captureException(error);
    }
  }

  Future<void> pickProfileImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        profileImagePath = pickedFile.path;
      });
      await secureStorage.write(key: 'profileImage', value: pickedFile.path);
    }
  }

  Future<void> logout(BuildContext context) async {
    await secureStorage.deleteAll();
    await strnadiFirebase.deleteToken();

    GoogleSignInService.signOut();
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
                GestureDetector(
                  onTap: pickProfileImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: profileImagePath != null
                        ? FileImage(File(profileImagePath!))
                        : const AssetImage('./assets/images/default.jpg') as ImageProvider,
                  ),
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
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DebugMenuPage()),
              );
            },
            child: const Text('Open Debug Menu'),
          ),
          MenuScreen(),
        ],
      ),
    );
  }
}