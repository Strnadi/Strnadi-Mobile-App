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
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

Logger logger = Logger();

class VerifyEmail extends StatefulWidget {
  final String userEmail;

  const VerifyEmail({
    Key? key,
    required this.userEmail,
  }) : super(key: key);

  @override
  State<VerifyEmail> createState() => _VerifyEmailState();
}

class _VerifyEmailState extends State<VerifyEmail> {
  // Reuse your existing color and styling constants
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

  void alreadyVerified(){
    Navigator.pop(context);
    Navigator.pushNamedAndRemoveUntil(context, 'authorizator', (Route<dynamic> route) => false);
  }

  Future<void> resendEmail() async {
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    final Uri url = Uri.https('api.strnadi.cz', '/auth/${widget.userEmail}/resend-verify-email');
    try {
      final response = await http.get(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
      );
      if(response.statusCode == 200){
        logger.i('Email sent');
      }
      else if(response.statusCode == 208){
        logger.i('Email already verified');
        showDialog(context: context, builder: (_) => AlertDialog(
          title: const Text('Email již ověřen'),
          content: const Text('Tento e-mail již byl ověřen.'),
          actions: [
            TextButton(
              onPressed: alreadyVerified,
              child: const Text('OK'),
            ),
          ],
        ));
      }
      else {
        logger.e(
            'Failed to send email ${response.statusCode} | ${response.body}');
      }
    } catch(e, stackTrace){
      logger.e(e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
    }
  }

  /// Resend email verification link. (Implement your actual logic here.)
  // void _resendEmail() {
  //   showDialog(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('Feature not implemented'),
  //       content: const Text('This feature has not been implemented yet.'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => alreadyVerified(context),
  //           child: const Text('OK'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  /// Open the user’s email app. (Implement or use a package like url_launcher.)
  void _openEmailApp() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: widget.userEmail,
    );
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the email app')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // White background
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(''),
        leading: IconButton(
          icon: Image.asset(
            'assets/icons/backButton.png',
            width: 30,
            height: 30,
          ),
          onPressed: () {
            Navigator.pushNamedAndRemoveUntil(context, 'authorizator', (Route<dynamic> route) => false);
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Ověřte svůj e-mail',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Na „${widget.userEmail}” jsme vám poslali odkaz na ověření '
                    'e-mailové adresy. Kliknutím na odkaz potvrdíte svoji '
                    'emailovou adresu.',
                style: const TextStyle(
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
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: Text(
                    _counter > 0
                        ? 'Poslat znovu ($_counter s)'
                        : 'Poslat znovu',
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
                    side: const BorderSide(
                      color: yellow,
                      width: 2,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: const Text('Otevřít e-mail'),
                ),
              ),
              const SizedBox(height: 16),

              // Pokračovat button that returns the user to the Authorizator page
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(context, 'authorizator', (Route<dynamic> route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: yellow,
                    foregroundColor: textColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: const Text('Pokračovat'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      // Bottom segmented progress bar
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 32,
        ),
        child: Row(
          children: List.generate(5, (index) {
            // Example: first segment is completed
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