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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/auth/appleAuth.dart';
import 'package:strnadi/auth/google_sign_in_service.dart' hide logger;
import 'package:strnadi/localization/localization.dart';
import '../../HealthCheck/serverHealth.dart' show logger;
import '../../bottomBar.dart';
import 'package:strnadi/localization/localization.dart' show t;

import '../../config/config.dart' hide logger;

class Connectedplatforms extends StatefulWidget {
  const Connectedplatforms({super.key});

  @override
  State<Connectedplatforms> createState() => _ConnectedPlatformsState();
}

class _ConnectedPlatformsState extends State<Connectedplatforms> {
  late bool? shouldShowAppleSignIn = null;
  late bool? ShouldShowGoogleSignIn = null;

  @override
  void initState() {
    super.initState();
    shouldShowGoogle().then((show) {
      setState(() {
        ShouldShowGoogleSignIn = show;
      });
    });
    shouldShowApple().then((show) {
      setState(() {
        shouldShowAppleSignIn = show;
      });
    });
  }

  Future<bool> shouldShowGoogle() async {
    var storage = FlutterSecureStorage();
    var jwt = await storage.read(key: 'token');
    final url = Uri.parse(
        'https://${Config.host}/auth/has-google-id?userId=${await storage.read(key: 'userId') ?? ''}');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
    );
    logger.i(response.statusCode);
    logger.i(url);
    if (response.statusCode == 200) {
      return false;
    }
    return true;
  }

  Future<bool> shouldShowApple() async {
    var storage = FlutterSecureStorage();
    var jwt = await storage.read(key: 'token');
    final url = Uri.parse(
        'https://${Config.host}/auth/has-apple-id?userId=${await storage.read(key: 'userId') ?? ''}');
    final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
    );
    logger.i(response.statusCode);
    logger.i(url);
    if (response.statusCode == 200) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (shouldShowAppleSignIn == null) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.user,
        appBarTitle: "Propojené služby",
        allawArrowBack: true,
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    if (shouldShowAppleSignIn == false && ShouldShowGoogleSignIn == false) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.user,
        appBarTitle: "Propojené služby",
        allawArrowBack: true,
        content: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'Váš účet je již propojen s Apple i Google.',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ],
        )),
      );
    }

    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      appBarTitle: "Propojené služby",
      allawArrowBack: true,
      content: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (shouldShowAppleSignIn == true)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        var storage = FlutterSecureStorage();
                        var jwt = await storage.read(key: 'token');
                        if (kIsWeb) {
                          logger
                              .w("Apple Sign-In is not supported on the web.");
                          return;
                        }
                        try {
                          var resp = await AppleAuth.signInAndGetJwt(jwt);
                          if (resp?['status'] != 200) {
                            logger.w("Apple Sign-In was cancelled or failed.");
                            return;
                          }
                          logger.i('Apple Sign-In successful.');
                        } catch (e) {
                          logger.e("Error during Apple Sign-In: $e");
                        }
                      },
                      icon: Image.asset(
                        'assets/images/apple.png',
                        height: 24,
                        width: 24,
                      ),
                      label: const Text(
                        'Pokračovat přes Apple',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        logger.i('Negger Schwartz');
                      },
                      icon: Image.asset(
                        'assets/images/google.webp',
                        height: 24,
                        width: 24,
                      ),
                      label: const Text(
                        'Už propojeno s Google',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (ShouldShowGoogleSignIn == true)
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        var storage = FlutterSecureStorage();
                        var jwt = await storage.read(key: 'token');
                        if (kIsWeb) {
                          logger
                              .w("Google Sign-In is not supported on the web.");
                          return;
                        }
                        try {
                          var resp =
                              await GoogleSignInService.signInWithGoogle();
                          if (resp == null) {
                            logger.w("Google Sign-In was cancelled or failed.");
                            return;
                          }
                          logger.i('Google Sign-In successful.');
                        } catch (e) {
                          logger.e("Error during Google Sign-In: $e");
                        }
                      },
                      icon: Image.asset(
                        'assets/images/google.webp',
                        height: 24,
                        width: 24,
                      ),
                      label: const Text(
                        'Pokračovat přes Google',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        logger.i('Schwartz Negger');
                      },
                      icon: Image.asset(
                        'assets/images/apple.png',
                        height: 24,
                        width: 24,
                      ),
                      label: const Text(
                        'Již propojeno s Apple',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            )
        ],
      )),
    );
  }
}
