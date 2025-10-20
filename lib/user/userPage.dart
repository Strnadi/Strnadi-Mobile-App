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
import 'dart:math';
import 'package:strnadi/localization/localization.dart';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/HealthCheck/serverHealth.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/user/settingsList.dart';
import '../config/config.dart';
import '../main.dart';
import 'package:strnadi/firebase/firebase.dart' as strnadiFirebase;

class UserPage extends StatefulWidget {
  const UserPage({Key? key}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  var secureStorage = const FlutterSecureStorage();

  late String userName = 'null';
  late String lastName = 'null';
  late String nickName = 'null';
  String? profileImagePath;
  bool _isConnected = true;

  final logger = Logger();

  @override
  void initState() {
    super.initState();
    setName();
    checkConnectivity();
    getUserData();
    getProfilePic(null);
  }

  void setName() async {
    setState(() async {
      userName = await secureStorage.read(key: 'firstName') ?? 'username';
      lastName = await secureStorage.read(key: 'lastName') ?? 'LastName';
      nickName = await secureStorage.read(key: 'nick') ?? 'nickName';
    });
  }

  Future<void> checkConnectivity() async {
    bool connected = await Config.hasBasicInternet;
    setState(() {
      _isConnected = connected;
    });
  }

  Future<File> convertBase64ToImage(
      String base64String, String fileName) async {
    // Decode the base64 string to bytes
    final bytes = base64Decode(base64String);

    // Get the directory to save the file
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');

    // Write the bytes to the file
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> getProfilePic(String? mail) async {
    var email;
    final jwt = await secureStorage.read(key: 'token');

    final id = await secureStorage.read(key: "userId");

    if (mail == null) {
      final jwt = await secureStorage.read(key: 'token');
      email = JwtDecoder.decode(jwt!)['sub'];
    } else {
      email = mail;
    }
    final url =
        Uri.parse('https://${Config.host}/users/${id}/get-profile-photo');
    logger.i(url);

    try {
      http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt'
      }).then((value) {
        if (value.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(value.body);
          convertBase64ToImage(
                  data['photoBase64'], 'profilePic.${data['format']}')
              .then((value) {
            logger.i("Profile picture downloaded");
            setState(() {
              profileImagePath = value.path;
            });
          });
        } else {
          logger.e(
              "Profile picture download failed with status code ${value.statusCode} ${value.body}");
        }
      });
    } catch (e) {
      throw UnimplementedError();
    }
  }

  void getUserData() async {
    final usernameExists = await secureStorage.containsKey(key: 'user');
    final id = await secureStorage.read(key: "userId");

    if (usernameExists) {
      var storedUserName = await secureStorage.read(key: 'user');
      var storedLastName = await secureStorage.read(key: 'lastname');
      setState(() {
        userName = storedUserName!;
        lastName = storedLastName!;
      });
      logger.i("User data loaded from cache");
      return;
    }

    final jwt = await secureStorage.read(key: 'token');
    final String email = JwtDecoder.decode(jwt!)['sub'];
    final Uri url = Uri(scheme: 'https', host: Config.host, path: '/users/$id');

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
      UploadProfilePic();

      await secureStorage.write(key: 'profileImage', value: pickedFile.path);
    }
  }

  Future<void> UploadProfilePic() async {
    final jwt = await secureStorage.read(key: 'token');
    final String email = JwtDecoder.decode(jwt!)['sub'];
    final id = await secureStorage.read(key: "userId");

    final url =
        Uri.parse("https://${Config.host}/users/$id/upload-profile-photo");
    final body = jsonEncode({
      'photoBase64': base64Encode(File(profileImagePath!).readAsBytesSync()),
      'format': profileImagePath!.split('.').last
    });
    try {
      http
          .post(
        url,
        headers: {
          'Authorization': 'Bearer $jwt',
          'Accept': '*/*',
          'Content-Type': 'application/json'
        },
        body: body,
      )
          .then((value) {
        if (value.statusCode == 200) {
          _showMessage(t('Profile picture uploaded'), context);
          logger.i("Profile picture uploaded");
        } else {
          _showMessage(t('Profile picture upload failed'), context);
          logger.e(
              "Profile picture upload failed with status code ${value.statusCode}");
        }
      });
    } catch (e) {
      throw UnimplementedError();
    }
  }

  Future<void> logout(BuildContext context) async {
    showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(t('logout.title')),
            content: Text(t('logout.message')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(t('logout.cancel')),
              ),
              TextButton(
                onPressed: () async {
                  await GoogleSignInService.signOut();
                  await secureStorage.deleteAll();
                  await strnadiFirebase.deleteToken();

                  Navigator.of(context).pushNamedAndRemoveUntil(
                      '/authorizator', (route) => false);
                },
                child: Text(t('logout.logout')),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      appBarTitle: '',
      logout: () => logout(context),
      content: SingleChildScrollView(
        child: Column(
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
                          : const AssetImage('./assets/images/default.jpg')
                              as ImageProvider,
                    ),
                  ),
                  Text(
                    "$userName $lastName",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text("($nickName)"),
                ],
              ),
            ),
            _isConnected
                ? MenuScreen()
                : Text(t(
                    'user.menu.error.noInternet')),
          ],
        ),
      ),
    );
  }

  void _showMessage(String s, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
    ));
  }
}
