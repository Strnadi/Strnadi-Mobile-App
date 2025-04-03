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
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/auth/forgottenPassword.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:strnadi/archived/login.dart';

import '../../config/config.dart';

class User {
  final String nickname;
  final String email;
  final String firstName;
  final String lastName;
  final int postCode;
  final String city;

  User({
    required this.nickname,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.postCode,
    required this.city,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      nickname: json['nickname'],
      email: json['email'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      postCode: json['postCode'],
      city: json['city'],
    );
  }

}

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({Key? key}) : super(key: key);

  @override
  _ProfileEditPageState createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {

  User? user;

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _pscController = TextEditingController();

  Future<void> fetchUser(String email, String jwt) async {
    final url = Uri.parse('https://${Config.host}/users/$email');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
    );

    if (response.statusCode == 200) {
      setState(() {
        user = User.fromJson(jsonDecode(response.body));
        _nicknameController.text = user!.nickname;
        _firstnameController.text = user!.firstName;
        _lastnameController.text = user!.lastName;
        _pscController.text = user!.postCode.toString();
      });
    } else {
      logger.i('Failed to load user: ${response.statusCode} ${response.body}');
      _showMessage("Nepodařilo se načíst uživatele");
    }
  }

  Future<void> updateUser(String email, Map<String, dynamic> updatedData, String jwt) async {
    final url = Uri.parse('https://${Config.host}/users/$email');


    logger.i(jsonEncode(updatedData));

    final response = await http.patch(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode(updatedData),
    );

    if (response.statusCode == 200) {
      _showMessage("Údaje byly úspěšně aktualizovány");
    } else {
      logger.i('Failed to update user: ${response.statusCode} ${response.body}');
      _showMessage("Nepodařilo se aktualizovat údaje");
    }
  }

  void updateUserData() async {
    final secureStorage = FlutterSecureStorage();
    String? jwt = await secureStorage.read(key: 'token');

    if (user != null && jwt != null) {
      Map<String, dynamic> updatedData = {
        'nickname': _nicknameController.text,
        'firstName': _firstnameController.text,
        'lastName': _lastnameController.text,
        'postCode': int.parse(_pscController.text),
        'city': user!.city,
      };

      updateUser(user!.email, updatedData, jwt);
    } else {
      _showMessage('Nepodařilo se načíst uživatele nebo token');
    }
  }

  Future<void> extractEmailFromJwt() async {

    final secureStorage = FlutterSecureStorage();
    String? jwt = await secureStorage.read(key: 'token');

    try {
      final parts = jwt!.split('.');
      if (parts.length != 3) {
        throw Exception('Invalid token');
      }

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final Map<String, dynamic> jsonPayload = jsonDecode(payload);

      fetchUser(jsonPayload['sub'], jwt); // Assuming the email is in "sub
    } catch (e) {
      logger.i("Error decoding JWT: $e");
    }
  }

  void UpdateUser() {
    // Update user
    _showMessage('Nic se nezměnilo');
  }


  @override
  void initState() {
    super.initState();
    extractEmailFromJwt();
  }
   


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Osobní údaje'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              updateUserData();
            }, // Save action
            child: const Text('Uložit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text("Profilové údaje", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 20),
                  _buildTextField('Jméno', _firstnameController),
                  _buildTextField('Příjmení', _lastnameController),
                  _buildTextField('Přezdívka', _nicknameController),
                  _buildTextField('PSČ', _pscController),
                  ListTile(
                    title: const Text('Kraj'),
                    subtitle: Text(user?.city ?? 'Null'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {}, // Open region selection
                  ),
                ],
              ),
              const Divider(),
              ListTile(
                title: const Text('Změna hesla'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ForgottenPassword()),
                  );
                }, // Open password change
              ),
              ListTile(
                title: const Text('Chci si smazat účet', style: TextStyle(color: Colors.red)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {}, // Open delete account confirmation
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildTextField(String label, TextEditingController txt) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        ),
        controller: txt,
      ),
    );
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
}
