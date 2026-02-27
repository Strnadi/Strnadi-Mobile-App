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
import 'package:flutter/services.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/passReset/forgottenPassword.dart';
import 'dart:convert';

import '../../auth/google_sign_in_service.dart';
import '../../firebase/firebase.dart' as strnadiFirebase;

Logger logger = Logger();

class User {
  final String nickname;
  final String email;
  final String firstName;
  final String lastName;
  final int? postCode;
  final String? city;

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
      nickname: json['nickname'] ?? "",
      email: json['email'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      postCode: json['postCode'],
      city: json['city'],
    );
  }
}

class ProfileEditPage extends StatefulWidget {
  Function() refreshUserCallback;

  ProfileEditPage({Key? key, required this.refreshUserCallback})
      : super(key: key);

  @override
  _ProfileEditPageState createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const UserController _userController = UserController();
  User? user;

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _postCodeController = TextEditingController();

  Future<void> fetchUser(int userId, String jwt) async {
    final response = await _userController.getUserById(userId);
    final dynamic responseData = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;

    if (response.statusCode == 200) {
      logger.i('Fetched user: $responseData');

      setState(() {
        user = User.fromJson((responseData as Map).cast<String, dynamic>());
        _nicknameController.text = user!.nickname;
        _firstnameController.text = user!.firstName;
        _lastnameController.text = user!.lastName;
        _cityController.text = user!.city ?? '';
        _postCodeController.text = user!.postCode?.toString() ?? '';
        _emailController.text = user!.email;
      });
    } else {
      logger.i('Failed to load user: ${response.statusCode} ${response.data}');
      _showMessage(t("user.profile.dialogs.error.load"));
    }
  }

  Future<void> refreshUser(int userId) async {
    final secureStorage = FlutterSecureStorage();

    final response = await _userController.getUserById(userId);
    if (response.statusCode == 200) {
      final dynamic responseData = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      final data = (responseData as Map).cast<String, dynamic>();
      await secureStorage.write(key: 'user', value: data['firstName']);
      await secureStorage.write(key: 'lastname', value: data['lastName']);
      await secureStorage.write(key: 'nick', value: data['nickname']);
      await secureStorage.write(key: 'role', value: data['role']);
      await widget.refreshUserCallback();
      setState(() {
        user = User.fromJson(data);
      });
    }
  }

  Future<void> updateUser(
      String email, Map<String, dynamic> updatedData, String jwt) async {
    final secureStorage = FlutterSecureStorage();

    final id = await secureStorage.read(key: "userId");
    logger.i(jsonEncode(updatedData));

    final response =
        await _userController.updateUserById(int.parse(id!), updatedData);

    if (response.statusCode == 200) {
      await refreshUser(int.parse(id!));
      _showMessage(t("user.profile.dialogs.success.update"));
    } else {
      logger
          .i('Failed to update user: ${response.statusCode} ${response.data}');
      _showMessage(t("user.profile.dialogs.error.update"));
    }
  }

  Future<void> updateUserData() async {
    final secureStorage = FlutterSecureStorage();
    String? jwt = await secureStorage.read(key: 'token');

    if (user != null && jwt != null) {
      Map<String, dynamic> updatedData = {
        'nickname':
            _nicknameController.text.isEmpty ? null : _nicknameController.text,
        'firstName': _firstnameController.text.isEmpty
            ? null
            : _firstnameController.text,
        'lastName':
            _lastnameController.text.isEmpty ? null : _lastnameController.text,
        'postCode': _postCodeController.text.trim().isEmpty
            ? null
            : int.parse(_postCodeController.text.trim()),
        'city': _cityController.text.isEmpty ? null : _cityController.text,
      };

      updateUser(user!.email, updatedData, jwt);
    } else {
      _showMessage(t('user.profile.dialogs.error.load'));
    }
  }

  Future<void> extractEmailFromJwt() async {
    final secureStorage = FlutterSecureStorage();
    String? jwt = await secureStorage.read(key: 'token');

    try {
      if (jwt == null) {
        throw Exception('Jwt token invalid');
      }

      final int userId = int.parse((await secureStorage.read(key: 'userId'))!);

      fetchUser(userId, jwt);
    } catch (e, stackTrace) {
      logger.i("Error fetching user data: $e",
          error: e, stackTrace: stackTrace);
    }
  }

  void UpdateUser() {
    // Update user
    _showMessage(t('user.profile.dialogs.success.noChanges'));
  }

  Future<void> confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('user.profile.dialogs.deleteAccount.title')),
        content: Text(t('user.profile.dialogs.deleteAccount.message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('recListItem.dialogs.confirmDelete.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('recListItem.dialogs.confirmDelete.delete'),
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final secureStorage = FlutterSecureStorage();
      String? jwt = await secureStorage.read(key: 'token');
      String? userId = await secureStorage.read(key: 'userId');

      if (jwt == null || userId == null) {
        _showMessage(t('user.profile.dialogs.error.auth'));
        return;
      }

      final response = await _userController.deleteUserById(int.parse(userId));

      if (response.statusCode == 200) {
        _showMessage(t('user.profile.dialogs.deleteAccount.success'));
        logout(context);
      } else {
        _showMessage(t('user.profile.dialogs.deleteAccount.error'));
        logger.i('Delete failed: ${response.statusCode} | ${response.data}');
      }
    }
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
        title: Text(t('user.profile.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              onPressed: () {
                updateUserData();
              }, // Save action
              child: Text(t('postRecordingForm.recordingForm.buttons.save'),
                  style: TextStyle(color: Colors.white)),
            ),
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
                Text(t("user.profile.title"),
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 20),
                _buildTextField(
                    t('user.profile.fields.firstName'), _firstnameController),
                _buildTextField(
                    t('user.profile.fields.lastName'), _lastnameController),
                _buildTextField(
                    t('user.profile.fields.nickname'), _nicknameController),
                _buildTextField(
                    t('user.profile.fields.email'), _emailController,
                    readOnly: true),
                _buildTextField(t('user.profile.fields.city'), _cityController),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: t('user.profile.fields.postCode'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0)),
                    ),
                    controller: _postCodeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              title: Text(t('user.profile.buttons.changePassword')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ForgottenPassword()),
                );
              }, // Open password change
            ),
            ListTile(
              title: Text(t('user.profile.buttons.deleteAccount'),
                  style: TextStyle(color: Colors.red)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                confirmAndDeleteAccount();
              }, // Open delete account confirmation
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController txt,
      {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        ),
        controller: txt,
        readOnly: readOnly,
      ),
    );
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('auth.buttons.ok')))
        ],
      ),
    );
  }

  Future<void> logout(BuildContext context) async {
    FlutterSecureStorage secureStorage = FlutterSecureStorage();

    await GoogleSignInService.signOut();
    await secureStorage.deleteAll();
    await strnadiFirebase.deleteToken();

    Navigator.of(context)
        .pushNamedAndRemoveUntil('/authorizator', (route) => false);
  }
}
