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
import 'package:connectivity_plus/connectivity_plus.dart';

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
  late String userName = 'username';
  late String lastName = 'lastname';
  String? profileImagePath;
  bool _isConnected = true;

  final logger = Logger();
  final secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    checkConnectivity();
    getUserData();
    getProfilePic();
  }

  Future<void> checkConnectivity() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = connectivityResult != ConnectivityResult.none;
    });
  }

  Future<File> convertBase64ToImage(String base64String, String fileName) async {
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

    if (mail == null){
      final jwt = await secureStorage.read(key: 'token');
      email = JwtDecoder.decode(jwt!)['sub'];
    }
    else {
      email = mail;
    }
    final url = Uri.parse(
        'https://api.strnadi.cz/users/${email}/get-profile-photo');
    logger.i(url);

    try {
      http.get(url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt'
          }).then((value) {
        if (value.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(value.body);
          convertBase64ToImage(data['photoBase64'], 'profilePic.${data['format']}').then((value) {
            logger.i("Profile picture downloaded");
            setState(() {
              profileImagePath = value.path;
            });
          });
        }else{
          logger.e("Profile picture download failed with status code ${value.statusCode}");
        }
      });
    }
    catch (e) {
      throw UnimplementedError();
    }
  }

  void getUserData() async {
    final usernameExists = await secureStorage.containsKey(key: 'user');

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
    final Uri url = Uri(scheme: 'https', host: Config.host, path: '/users/$email');

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

    final url = Uri.parse("https://api.strnadi.cz/users/${email}/upload-profile-photo");
    final body = jsonEncode({
      'photoBase64': base64Encode(File(profileImagePath!).readAsBytesSync()),
      'format': profileImagePath!.split('.').last
    });
    try {
      http.post(url, headers: {
        'Authorization': 'Bearer $jwt',
        'Accept': '*/*',
        'Content-Type': 'application/json'
      }, body: body,
      ).then((value) {
        if (value.statusCode == 200) {
          _showMessage("Profile picture uploaded", context);
          logger.i("Profile picture uploaded");
        } else {
          _showMessage("Profile picture upload failed", context);
          logger.e("Profile picture upload failed with status code ${value.statusCode}");
        }
      });
    } catch (e) {
      throw UnimplementedError();
    }
  }

  Future<void> logout(BuildContext context) async {

    showDialog(context: context, builder: (context) {
      return AlertDialog(
        title: const Text('Odhlásit se'),
        content: const Text('Opravde se chcete odhlásit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              GoogleSignInService.signOut();
              await secureStorage.deleteAll();
              await strnadiFirebase.deleteToken();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => MyApp()),
                    (route) => false,
              );
            },
            child: const Text('Odhlásit se'),
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
                        : const AssetImage('./assets/images/default.jpg')
                    as ImageProvider,
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
          _isConnected ? MenuScreen() : Text('Osobní údaje nejsou dostupné bez připojení k internetu'),
        ],
      ),
    );
  }

  void _showMessage(String s, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
    ));
  }
}