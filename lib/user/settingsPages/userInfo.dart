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

class User {
  final int id;
  final String nickname;
  final String email;
  final String? password;
  final String firstName;
  final String lastName;
  final int postCode;
  final String city;
  final DateTime creationDate;
  final bool isEmailVerified;
  final bool consent;
  final String role;

  User({
    required this.id,
    required this.nickname,
    required this.email,
    this.password,
    required this.firstName,
    required this.lastName,
    required this.postCode,
    required this.city,
    required this.creationDate,
    required this.isEmailVerified,
    required this.consent,
    required this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      nickname: json['nickname'],
      email: json['email'],
      password: json['password'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      postCode: json['postCode'],
      city: json['city'],
      creationDate: DateTime.parse(json['creationDate']),
      isEmailVerified: json['isEmailVerified'],
      consent: json['consent'],
      role: json['role'],
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

  Future<void> fetchUser(String email, String jwt) async {
    final url = Uri.parse('https://api.strnadi.cz/users/$email');
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
      });
    } else {
      logger.i('Failed to load user: ${response.statusCode} ${response.body}');
      _showMessage("Nepodařilo se načíst uživatele");
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
            onPressed: () {
              UpdateUser();
            }, // Save action
            child: const Text('Uložit', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildTextField('Jméno', user?.firstName ?? 'Null'),
            _buildTextField('Příjmení',  user?.lastName ?? 'Null'),
            _buildTextField('Přezdívka', user?.nickname ?? 'Null'),
            _buildTextField('E-mail', user?.email ?? 'Null'),
            _buildTextField('PSČ', user?.postCode.toString() ?? 'Null'),
            ListTile(
              title: const Text('Kraj'),
              subtitle: Text(user?.city ?? 'Null'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {}, // Open region selection
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

  Widget _buildTextField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        ),
        controller: TextEditingController(text: value),
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
