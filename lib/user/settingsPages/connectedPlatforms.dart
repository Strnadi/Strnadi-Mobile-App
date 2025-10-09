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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/auth/appleAuth.dart';
import 'package:strnadi/localization/localization.dart';
import '../../HealthCheck/serverHealth.dart' show logger;
import '../../bottomBar.dart';
import 'package:strnadi/localization/localization.dart' show t;

class Connectedplatforms extends StatefulWidget {
  const Connectedplatforms({super.key});

  @override
  State<Connectedplatforms> createState() => _ConnectedPlatformsState();
}

class _ConnectedPlatformsState extends State<Connectedplatforms> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      appBarTitle: "Propojené služby",
      allawArrowBack: true,
      content: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
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
                    logger.w("Apple Sign-In is not supported on the web.");
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
        ],
      )),
    );
  }
}
