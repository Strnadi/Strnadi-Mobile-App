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

import 'package:flutter/cupertino.dart' as Dialogs;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/archived/map.dart';
import 'package:strnadi/map/mapv2.dart';
import 'package:strnadi/archived/recorderWithSpectogram.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'main.dart';
import 'notificationPage/notifList.dart';
import 'user/userPage.dart';
import 'package:strnadi/firebase/firebase.dart' as fb;
import 'config/config.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';

// 1. Add enum for bottom bar items
enum BottomBarItem { map, list, recorder, notification, user }


class ScaffoldWithBottomBar extends StatelessWidget {
  final String? appBarTitle;
  final Widget content;
  final VoidCallback? logout;
  final allowArrowBack;
  final IconData? icon;
  final bool? isGuestUser;

  // New field for selected page
  final BottomBarItem selectedPage;

  const ScaffoldWithBottomBar({
    Key? key,
    this.appBarTitle,
    required this.content,
    required this.selectedPage, // Make selectedPage required
    this.logout,
    this.allowArrowBack = false,
    this.icon,
    this.isGuestUser,
  }) : super(key: key);

  Future<void> Logout(BuildContext context) async {
    final localStorage = const FlutterSecureStorage();

    localStorage.delete(key: 'user');
    localStorage.delete(key: 'lastname');
    await fb.deleteToken();
    await GoogleSignInService.signOut();
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
                title: appBarTitle!.isNotEmpty
                    ? Center(child: Text(appBarTitle!))
                    : const SizedBox.shrink(),
                backgroundColor: Colors.white,
                //toolbarHeight: 40.0,
                actions: [
                  if (logout != null)
                    IconButton(
                      icon:
                          icon != null ? Icon(icon) : const Icon(Icons.logout),
                      onPressed: () {
                        logout!();
                      },
                    ),
                ],
                automaticallyImplyLeading: allowArrowBack,
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
        // Pass the selectedPage to the bottom bar widget:
        bottomNavigationBar: ReusableBottomAppBar(
            currentPage: selectedPage,
            changeConfirmation: () => Future.value(true),
            isGuestUser: isGuestUser ?? false));
  }
}

class ReusableBottomAppBar extends StatelessWidget {
  // New field to capture the current page
  final BottomBarItem currentPage;
  final bool isGuestUser;
  Future<bool> Function() changeConfirmation;

  ReusableBottomAppBar(
      {super.key,
      required this.currentPage,
      required this.changeConfirmation,
      this.isGuestUser = false});

  String _iconAsset({
    required String on,
    required String off,
    String? disabled,
    required bool isSelected,
  }) {
    if (isGuestUser && disabled != null) return disabled;
    return isSelected ? on : off;
  }

  Future showGuestUserPopup(context) {
    return Dialogs.showCupertinoDialog(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: Text(t('bottomBar.errors.guest_user')),
          content: Text(t('bottomBar.errors.guest_user_desc')),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(t('bottomBar.errors.close')),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () async {
                //navigate to login
                Navigator.of(context).pop();
                SharedPreferences prefs = await SharedPreferences.getInstance();
                prefs.setBool('popupShown', false);
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        Authorizator(),
                    settings: const RouteSettings(name: '/'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              },
              child: Text(t('bottomBar.errors.navigate_to_login')),
            ),
          ],
        );
      },
    );
  }

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
          // Map Button
          IconButton(
            icon: Image.asset(
              _iconAsset(
                on: 'assets/icons/mapOn.png',
                off: 'assets/icons/mapOff.png',
                isSelected: currentPage == BottomBarItem.map,
              ),
              width: 40,
              height: 40,
            ),
            iconSize: 30.0,
            onPressed: () async {
              if (!await changeConfirmation()) return;

              if (!await Config.hasBasicInternet) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t('bottomBar.errors.noInternetMap')),
                    duration: Duration(seconds: 3),
                  ),
                );
                return;
              }

              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        MapScreenV2(),
                    settings: const RouteSettings(name: '/map'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          // List Button
          IconButton(
            icon: Image.asset(
              _iconAsset(
                on: 'assets/icons/listOn.png',
                off: 'assets/icons/listOff.png',
                disabled: 'assets/icons/listDisabled.png',
                isSelected: currentPage == BottomBarItem.list,
              ),
              width: 40,
              height: 40,
            ),
            iconSize: 30.0,
            onPressed: () async {
              var storage = const FlutterSecureStorage();
              var token = await storage.read(key: 'userId');
              if (token == null || token.isEmpty) {
                showGuestUserPopup(context);
                return;
              }
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/list') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        RecordingScreen(),
                    settings: const RouteSettings(name: '/list'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          // Recorder Button
          IconButton(
            icon: Image.asset(
              _iconAsset(
                on: 'assets/icons/micOn.png',
                off: 'assets/icons/micOff.png',
                isSelected: currentPage == BottomBarItem.recorder,
              ),
              width: 40,
              height: 40,
            ),
            iconSize: 30.0,
            onPressed: () async {
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/Recorder') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        LiveRec(),
                    settings: const RouteSettings(name: '/Recorder'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          // Notification Button
          IconButton(
            icon: Image.asset(
              _iconAsset(
                on: 'assets/icons/shelfOn.png',
                off: 'assets/icons/shelfOff.png',
                disabled: 'assets/icons/shelfDisabled.png',
                isSelected: currentPage == BottomBarItem.notification,
              ),
              width: 40,
              height: 40,
            ),
            iconSize: 30.0,
            onPressed: () async {
              var storage = const FlutterSecureStorage();
              var token = await storage.read(key: 'userId');
              if (token == null || token.isEmpty) {
                showGuestUserPopup(context);
                return;
              }
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/notification') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        NotificationScreen(),
                    settings: const RouteSettings(name: '/notification'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          // User Button
          IconButton(
            icon: Image.asset(
              _iconAsset(
                on: 'assets/icons/userOn.png',
                off: 'assets/icons/userOff.png',
                disabled: 'assets/icons/userDisabled.png',
                isSelected: currentPage == BottomBarItem.user,
              ),
              width: 40,
              height: 40,
            ),
            iconSize: 30.0,
            onPressed: () async {
              var storage = const FlutterSecureStorage();
              var token = await storage.read(key: 'userId');
              if (token == null || token.isEmpty) {
                showGuestUserPopup(context);
                return;
              }
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/user') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        UserPage(),
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
