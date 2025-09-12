/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:strnadi/auth/unverifiedEmail.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/firebase/firebase.dart' as firebase;
import 'package:strnadi/database/databaseNew.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strnadi/auth/login.dart';
import 'package:flutter/gestures.dart'; // Needed for TapGestureRecognizer
import 'package:strnadi/md_renderer.dart';
// Removed: import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/config.dart';
import 'launch_warning.dart';

Logger logger = Logger();

enum AuthType { login, register }

class Authorizator extends StatefulWidget {

  const Authorizator({
    Key? key,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}


enum AuthStatus { loggedIn, loggedOut, notVerified }

Future<AuthStatus> _onlineIsLoggedIn() async{
  final secureStorage = FlutterSecureStorage();
  final token = await secureStorage.read(key: 'token');
  if (token != null) {
    final Uri url = Uri(scheme: 'https', host: Config.host, path: '/auth/verify-jwt', queryParameters: {'jwt': token});

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      logger.i('Response: ${response.statusCode} | ${response.body}');

      if (response.statusCode == 200) {
        await secureStorage.write(key: 'verified', value: 'true');
        DateTime expirationDate = JwtDecoder.getExpirationDate(token)!;
        if (expirationDate.isAfter(DateTime.now().add(const Duration(days: 7)))) {
          return AuthStatus.loggedIn;
        }
        // If the token is valid but about to expire, refresh it
        try{
          final refreshResponse = await http.get(
            Uri(scheme: 'https', host: Config.host, path: '/auth/renew-jwt'), headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },);
          if (refreshResponse.statusCode == 200) {
            String newToken = refreshResponse.body;
            await secureStorage.write(key: 'token', value: newToken);
          }
        }
        catch(e, stackTrace){
          Sentry.captureException(e, stackTrace: stackTrace);
          logger.e('Error refreshing token: $e', error: e, stackTrace: stackTrace);
        }
        return AuthStatus.loggedIn;
      } else if (response.statusCode == 403) {
        await secureStorage.write(key: 'verified', value: 'false');
        return AuthStatus.notVerified;
      }
      else {
        return AuthStatus.loggedOut;
      }
    } catch (error) {
      Sentry.captureException(error);
      return AuthStatus.loggedOut;
    }
  }
  return AuthStatus.loggedOut;
}

Future<AuthStatus> _offlineIsLoggedIn() async{
  FlutterSecureStorage secureStorage = FlutterSecureStorage();
  String? token = await secureStorage.read(key: 'token');
  if (token != null) {
    DateTime expirationDate = JwtDecoder.getExpirationDate(token)!;
    if (expirationDate.isAfter(DateTime.now())) {
      String? verified = await secureStorage.read(key: 'verified');
      if (verified == 'true') {
        return AuthStatus.loggedIn;
      } else {
        return AuthStatus.notVerified;
      }
    } else {
      return AuthStatus.loggedOut;
    }
  }
  else{
    return AuthStatus.loggedOut;
  }
}

Future<AuthStatus> isLoggedIn() async {
  // Treat either no connectivity or backend unreachable as offline
  if (!await Config.hasBasicInternet) {
    return await _offlineIsLoggedIn();
  }
  if (!await Config.isBackendAvailable) {
    return await _offlineIsLoggedIn();
  }
  return await _onlineIsLoggedIn();
}

class _AuthState extends State<Authorizator> {
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showWIPwarning();
    });
    Config.hasBasicInternet.then((online) {
      setState(() {
        _isOnline = online;
      });
    });
    checkLoggedIn(); // token check if needed
  }

  void _showWIPwarning() {
    showDialog(
      context: context,
      builder: (context) => WIP_warning(),
    );
  }
  @override
  Widget build(BuildContext context) {
    // Example color definitions
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  // Spacing from the top
                  //const SizedBox(height: 0),

                  // Bird image
                  Image.asset(
                    'assets/images/ncs_logo_tall_large.png', // Update path if needed
                    width: 200,
                    height: 200,
                  ),

                  const SizedBox(height: 32),

                  // Main title
                  Text(t('auth.title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(t('auth.subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // "Založit účet" button (yellow background, no elevation)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _navigateIfAllowed(const RegMail()),
                      style: ElevatedButton.styleFrom(
                        elevation: 0, // No elevation
                        shadowColor: Colors.transparent, // Remove shadow
                        backgroundColor: yellow,
                        foregroundColor: textColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(t('auth.buttons.register'), style: TextStyle(color: textColor),),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // "Přihlásit se" button (outlined)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _navigateIfAllowed(const Login()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: textColor,
                        side: BorderSide(color: Colors.grey[200]!, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(t('auth.buttons.login'), style: TextStyle(color: textColor)),
                    ),
                  ),

                  // Add the terms here
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      Text(t('auth.disclaimer.consent_prefix'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _launchURL(),
                        child: Text(t('auth.disclaimer.privacy_policy'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Add disclaimer and space at the bottom
                  const SizedBox(height: 60),
                  Text(t('auth.disclaimer.dev_notice'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> checkLoggedIn() async {
    bool online = await Config.hasBasicInternet;
    if (!online) {
      final secureStorage = FlutterSecureStorage();
      String? token = await secureStorage.read(key: 'token');
      if (token == null) {
        _showAlert("Offline", "Nemáte připojení k internetu a žádný token není uložen.");
        return;
      } else {
        DateTime expirationDate = JwtDecoder.getExpirationDate(token)!;
        if (expirationDate.isBefore(DateTime.now())) {
          _showAlert("Offline", "Váš JWT vypršel. Prosím připojte se k internetu pro obnovení.");
          return;
        }
        String? verified = await secureStorage.read(key: 'verified');
        if (verified != 'true') {
          _showAlert("Offline", "Váš účet není ověřen. Prosím ověřte svůj email pro další přístup.");
          return;
        }
      }
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
          settings: const RouteSettings(name: '/Recorder'),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      return;
    }
    final secureStorage = FlutterSecureStorage();
    final AuthStatus status = await isLoggedIn();


    if (status == AuthStatus.loggedIn) {
      String? token = await secureStorage.read(key: 'token');
      if (token == null) return;
      String? userIdS = await secureStorage.read(key: 'userId');
      int? userId;

      if(userIdS==null){
        Uri url = Uri(
            scheme: 'https',
            host: Config.host,
            path: '/users/get-id'
        );
        var idResponse = await http.get(url, headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        });
        userId = int.parse(idResponse.body);
        await secureStorage.write(key: 'userId', value: userId.toString());
      }
      else{
        userId = int.parse(userIdS);
      }
      final Uri url = Uri.parse('https://${Config.host}/users/$userId').replace(queryParameters: {'jwt': token});

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );


      final Map<String, dynamic> data = jsonDecode(response.body);
      secureStorage.write(key: 'user', value: data['firstName']);
      secureStorage.write(key: 'lastname', value: data['lastName']);

      logger.i('Syncing recordings on login');
      DatabaseNew.syncRecordings();
      logger.i('Syncing recordings on login done');
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
          settings: const RouteSettings(name: '/Recorder'),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } else if(status == AuthStatus.notVerified) {
      String? token = await secureStorage.read(key: 'token');
      if (token == null) return;
      Uri url = Uri(
          scheme: 'https',
          host: Config.host,
          path: '/users/get-id'
      );
      var idResponse = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });
      int userId = int.parse(idResponse.body);
      await secureStorage.write(key: 'userId', value: userId.toString());
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EmailNotVerified(userEmail: JwtDecoder.decode(token!)['sub'], userId: userId,)),
      );
    } else {
      // If there is a token but user is not logged in (invalid token),
      // remove it and show message.
      if (await secureStorage.read(key: 'token') != null) {
        _showMessage("Byli jste odhlášeni");
        await secureStorage.delete(key: 'token');
        await secureStorage.delete(key: 'user');
        await secureStorage.delete(key: 'lastname');
        await firebase.deleteToken();
      }
    }
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Login')),
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

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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

  /// Navigate respecting internet connectivity
  Future<void> _navigateIfAllowed(Widget page) async {
    if (!await Config.hasBasicInternet) {
      _showAlert("Offline", "Tato akce není dostupná offline.");
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _launchURL() async {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MDRender(mdPath: 'assets/docs/terms-of-services.md', title: 'Podmínky používání',)),
    );
  }
}
