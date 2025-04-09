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
import 'package:strnadi/recording/streamRec.dart'; // Added missing import for LiveRecrnadi/user/userPage.dart;

import 'main.dart';
import 'notificationPage/notifList.dart';
import 'user/userPage.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;


class ScaffoldWithBottomBar extends StatelessWidget {
  final String? appBarTitle;
  final Widget content;
  final VoidCallback? logout;
  final allawArrowBack;
  final IconData? icon;

  const ScaffoldWithBottomBar({
    Key? key,

    this.appBarTitle,
    required this.content,
    this.logout,
    this.allawArrowBack = false,
    this.icon,
  }) : super(key: key);

  void Logout(BuildContext context) async {
    final localStorage = const FlutterSecureStorage();

    localStorage.delete(key: 'user');
    localStorage.delete(key: 'lastname');
    await fb.deleteToken();
    localStorage.delete(key: 'token');
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => MyApp(),
        settings: const RouteSettings(name: '/'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false, // Remove all previous routes
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBarTitle != null
          ? AppBar(
        title: Center(child: Text(appBarTitle!)),
        backgroundColor: Colors.white,
        actions: [
          if (logout != null)
            IconButton(
              icon: icon != null ? Icon(icon) : const Icon(Icons.logout),
              onPressed: () {
                logout!();
              },
            ),
        ],
        automaticallyImplyLeading: allawArrowBack,
      )
          : null,
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => MapScreenV2(),
                    settings: const RouteSettings(name: '/map'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => RecordingScreen(),
                    settings: const RouteSettings(name: '/list'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
                    settings: const RouteSettings(name: '/Recorder'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => NotificationScreen(),
                    settings: const RouteSettings(name: '/notification'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
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
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => UserPage(),
                    settings: const RouteSettings(name: '/user'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
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
