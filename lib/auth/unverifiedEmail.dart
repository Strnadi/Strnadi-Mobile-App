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
import 'dart:async';

import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/config/config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

Logger logger = Logger();

class EmailNotVerified extends StatefulWidget {
  final int userId;
  final String userEmail;
  const EmailNotVerified({
    Key? key,
    required this.userId,
    required this.userEmail
  }) : super(key: key);

  @override
  State<EmailNotVerified> createState() => _EmailNotVerifiedState();
}

class _EmailNotVerifiedState extends State<EmailNotVerified> {
  static const Color textColor = Color(0xFF2D2B18);
  static const Color yellow = Color(0xFFFFD641);

  int _counter = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Starts a 30-second countdown timer for the 'Poslat znovu' button.
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_counter > 0) {
          _counter--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  /// Navigates back to the login/authorization page when email is verified.
  void alreadyVerified() {
    Navigator.pop(context);
    Navigator.pushNamedAndRemoveUntil(context, '/authorizator', (Route<dynamic> route) => false);
  }

  /// Resend verification email.
  Future<void> resendEmail() async {
    FlutterSecureStorage secureStorage = FlutterSecureStorage();
    final String? jwt = await secureStorage.read(key: 'token');
    final Uri url = Uri.https(Config.host, '/auth/${await secureStorage.read(key: 'userId')}/resend-verify-email');
    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
      );
      if (response.statusCode == 200) {
        logger.i('Verification email sent');
        _startTimer();
      } else if (response.statusCode == 208) {
        logger.i('Email already verified');
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(t('Email již ověřen')),
            content: Text(t('Tento e-mail již byl ověřen.')),
            actions: [
              TextButton(
                onPressed: alreadyVerified,
                child: Text(t('auth.buttons.ok')),
              ),
            ],
          ),
        );
      } else {
        logger.e('Failed to send email ${response.statusCode} | ${response.body}');
      }
    } catch (e, stackTrace) {
      logger.e(e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Opens the email app using url_launcher with externalApplication mode.
  void _openEmailApp() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: widget.userEmail,
    );
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('Could not open the email app'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(t('')),
        leading: IconButton(
          icon: Image.asset(
            'assets/icons/backButton.png',
            width: 30,
            height: 30,
          ),
          onPressed: () {
            FlutterSecureStorage().delete(key: 'token');
            Navigator.pushNamedAndRemoveUntil(context, '/authorizator', (Route<dynamic> route) => false);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(t('Email není ověřen'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('Pro pokračování se přihlášením ověřte prosím svůj e-mail ({email}).\nNa tuto adresu byl zaslán ověřovací odkaz. Klikněte na odkaz pro potvrzení.')
                    .replaceFirst('{email}', widget.userEmail),
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 32),
              const Spacer(),
              // Resend button (disabled while countdown is running)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _counter > 0 ? null : resendEmail,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: yellow,
                    foregroundColor: textColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: Text(
                    _counter > 0 ? 'Poslat znovu ($_counter s)' : 'Poslat znovu',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Open email app button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _openEmailApp,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    foregroundColor: textColor,
                    side: const BorderSide(color: yellow, width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: Text(t('Otevřít e-mail')),
                ),
              ),
              const SizedBox(height: 16),
              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(context, '/authorizator', (Route<dynamic> route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: yellow,
                    foregroundColor: textColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: Text(t('signup.mail.buttons.continue')),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      // Bottom segmented progress bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 32),
        child: Row(
          children: List.generate(5, (index) {
            // All segments shown as complete
            bool completed = index < 5;
            return Expanded(
              child: Container(
                height: 5,
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
    );
  }
}