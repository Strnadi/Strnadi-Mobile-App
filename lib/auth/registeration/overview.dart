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

import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;
import 'package:logger/logger.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'emailSent.dart';

class RegOverview extends StatefulWidget {
  final String email;
  final bool consent;
  final String? password;
  final String jwt;
  final String name;
  final String surname;
  final String nickname;
  final String postCode;
  final String city;
  final String? appleId;

  const RegOverview({
    Key? key,
    required this.email,
    required this.consent,
    this.password,
    required this.jwt,
    required this.name,
    required this.surname,
    required this.nickname,
    required this.postCode,
    required this.city,
    this.appleId,
  }) : super(key: key);

  @override
  State<RegOverview> createState() => _RegOverviewState();
}

class _RegOverviewState extends State<RegOverview> {
  static const Color textColor = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);
  final Logger logger = Logger();

  bool _isLoading = false;
  bool _marketingConsent = false;

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // prevent duplicate presses
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.error.title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> register() async {
    final secureStorage = FlutterSecureStorage();
    final url = Uri(
      scheme: 'https',
      host: Config.host,
      path: '/auth/sign-up',
    );

    final requestBody = jsonEncode({
      'email': widget.email,
      'password': widget.password,
      'FirstName': widget.name,
      'LastName': widget.surname,
      'nickname': widget.nickname.isEmpty ? null : widget.nickname,
      'city': widget.city.isNotEmpty ? widget.city : null,
      'postCode':
          widget.postCode.isNotEmpty ? int.tryParse(widget.postCode) : null,
      'appleId': widget.appleId,
      'consent': widget.consent && _marketingConsent,
    });

    logger.i("Sign Up Request Body: $requestBody");

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwt}',
        },
        body: requestBody,
      );

      logger.i("Sign Up Response: ${response.body}");

      if ([200, 201, 202].contains(response.statusCode)) {
        // Store the token if returned
        await secureStorage.write(
            key: 'token', value: response.body.toString());
        await fb.refreshToken();

        Uri url =
            Uri(scheme: 'https', host: Config.host, path: '/users/get-id');
        var idResponse = await http.get(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${response.body.toString()}',
        });
        int userId = int.parse(idResponse.body);
        await secureStorage.write(key: 'userId', value: userId.toString());

        if (widget.jwt == null) {
          await secureStorage.write(key: 'verified', value: 'false');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VerifyEmail(userEmail: widget.email),
            ),
          );
        } else {
          Navigator.pushNamedAndRemoveUntil(
              context, '/authorizator', (Route<dynamic> route) => false);
        }
      } else if (response.statusCode == 409) {
        GoogleSignInService.signOut();
        logger.w('Sign up failed: ${response.statusCode} | ${response.body}');
        _showMessage(t('signup.overview.errors.user_exists'));
      } else {
        GoogleSignInService.signOut();
        _showMessage(t('signup.overview.errors.error_ocured'));
        logger.e("Sign up failed: ${response.statusCode} | ${response.body}");
      }
    } catch (error) {
      GoogleSignInService.signOut();
      logger.e("An error occurred: $error");
      _showMessage(t('signup.overview.errors.error_ocured'));
    } finally {}
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: TextStyle(
                fontSize: 16,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isLoading,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: Image.asset(
                  'assets/icons/backButton.png',
                  width: 30,
                  height: 30,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('signup.overview.title'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('signup.overview.check_details'),
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildInfoItem(
                        t('signup.overview.items.email'), widget.email),
                    _buildInfoItem(
                        t('signup.overview.items.name'), widget.name),
                    _buildInfoItem(
                        t('signup.overview.items.last_name'), widget.surname),
                    _buildInfoItem(t('signup.overview.items.nickname'),
                        widget.nickname.isNotEmpty ? widget.nickname : '-'),
                    _buildInfoItem(
                        t('signup.overview.items.post_code'), widget.postCode),
                    _buildInfoItem(
                        t('signup.overview.items.city'), widget.city),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Checkbox(
                          value: _marketingConsent,
                          onChanged: (bool? value) {
                            setState(() {
                              _marketingConsent = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            t('signup.overview.marketing_consent'),
                            style: TextStyle(
                              fontSize: 14,
                              color: _RegOverviewState.textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: !_isLoading
                            ? () {
                                _withLoader(() async {
                                  await register();
                                });
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          backgroundColor: yellow,
                          foregroundColor: textColor,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                        ),
                        child: Text(t('signup.overview.buttons.register')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 16, bottom: 48),
              child: Row(
                children: List.generate(5, (index) {
                  bool completed = index < 5;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: completed ? yellow : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
