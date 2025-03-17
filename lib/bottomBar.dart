// lib/bottomBar.dart
/*
 * Copyright (C) 2024 Marian Pecqueur
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/archived/map.dart';
import 'package:strnadi/map/mapv2.dart';
import 'package:strnadi/archived/recorderWithSpectogram.dart';
import 'package:strnadi/recording/streamRec.dart'; // Added missing import for LiveRecrnadi/user/userPage.dart';

import 'main.dart';
import 'notificationPage/notifList.dart';
import 'user/userPage.dart';


class ScaffoldWithBottomBar extends StatelessWidget {
  final String appBarTitle;
  final Widget content;
  final VoidCallback? logout;
  final allawArrowBack;

  const ScaffoldWithBottomBar({
    Key? key,

    required this.appBarTitle,
    required this.content,
    this.logout,
    this.allawArrowBack = false,
  }) : super(key: key);

  void Logout(BuildContext context) {
    final localStorage = const FlutterSecureStorage();
    localStorage.delete(key: 'token');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => MyApp()),
      (route) => false, // Remove all previous routes
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: Text(appBarTitle)),
        backgroundColor: Colors.white,
        actions: [
          if (logout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                Logout(context);
              },
            ),
        ],
        automaticallyImplyLeading: allawArrowBack,
      ),
      backgroundColor: Colors.white,
      body: SizedBox(
        height: MediaQuery.of(context).size.height -
            kToolbarHeight -
            kBottomNavigationBarHeight,
        child: content,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: const ReusableBottomAppBar(),
    );
  }
}

class ReusableBottomAppBar extends StatelessWidget {
  const ReusableBottomAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.map),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreenV2(),
                    settings: const RouteSettings(name: '/map'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/list') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordingScreen(),
                    settings: const RouteSettings(name: '/list'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.mic),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/Recorder') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveRec(),
                    settings: const RouteSettings(name: '/Recorder'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/notification') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationScreen(),
                    settings: const RouteSettings(name: '/notification'),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/user') {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserPage(),
                    settings: const RouteSettings(name: '/user'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
