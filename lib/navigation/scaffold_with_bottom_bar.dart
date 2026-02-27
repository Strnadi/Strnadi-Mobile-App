/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/articles/blog_explorer_content.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/mapv2.dart';
import 'package:strnadi/navigation/guest_user_popup.dart';
import 'package:strnadi/navigation/notification_bell_button.dart';
import 'package:strnadi/navigation/session_navigation.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/user/userPage.dart';

enum BottomBarItem { map, list, recorder, notification, blog, user }

class ScaffoldWithBottomBar extends StatelessWidget {
  final String? appBarTitle;
  final Widget content;
  final VoidCallback? logout;
  final bool allowArrowBack;
  final IconData? icon;
  final bool? isGuestUser;
  final bool showNotificationBell;
  final BottomBarItem selectedPage;

  const ScaffoldWithBottomBar({
    super.key,
    this.appBarTitle,
    required this.content,
    required this.selectedPage,
    this.logout,
    this.allowArrowBack = false,
    this.icon,
    this.isGuestUser,
    this.showNotificationBell = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool guestUser = isGuestUser ?? false;
    final bool shouldRedirectAndroidBackToSessionLanding = !allowArrowBack &&
        (selectedPage == BottomBarItem.map ||
            selectedPage == BottomBarItem.blog ||
            selectedPage == BottomBarItem.user);
    final Widget pageContent = SizedBox(
      height: MediaQuery.of(context).size.height -
          kToolbarHeight -
          kBottomNavigationBarHeight,
      child: content,
    );

    final scaffold = Scaffold(
      appBar: appBarTitle != null
          ? AppBar(
              title: appBarTitle!.isNotEmpty
                  ? Text(appBarTitle!)
                  : const SizedBox.shrink(),
              centerTitle: true,
              backgroundColor: Colors.white,
              actions: [
                if (showNotificationBell)
                  NotificationBellButton(
                    isGuestUser: guestUser,
                    isSelected: selectedPage == BottomBarItem.notification,
                  ),
                if (logout != null)
                  IconButton(
                    icon: icon != null ? Icon(icon) : const Icon(Icons.logout),
                    onPressed: logout,
                  ),
              ],
              automaticallyImplyLeading: allowArrowBack,
            )
          : null,
      backgroundColor: Colors.white,
      body: appBarTitle != null
          ? pageContent
          : showNotificationBell
              ? Stack(
                  children: [
                    pageContent,
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SafeArea(
                        child: Material(
                          elevation: 2,
                          shape: const CircleBorder(),
                          color: Colors.white,
                          child: NotificationBellButton(
                            isGuestUser: guestUser,
                            isSelected:
                                selectedPage == BottomBarItem.notification,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : pageContent,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: ReusableBottomAppBar(
        currentPage: selectedPage,
        changeConfirmation: () => Future.value(true),
        isGuestUser: guestUser,
      ),
    );

    if (!shouldRedirectAndroidBackToSessionLanding) {
      return scaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await navigateToSessionLanding(context);
      },
      child: scaffold,
    );
  }
}

class ReusableBottomAppBar extends StatelessWidget {
  final BottomBarItem currentPage;
  final bool isGuestUser;
  final Future<bool> Function() changeConfirmation;

  const ReusableBottomAppBar({
    super.key,
    required this.currentPage,
    required this.changeConfirmation,
    this.isGuestUser = false,
  });

  String _iconAsset({
    required String on,
    required String off,
    String? disabled,
    required bool isSelected,
  }) {
    if (isGuestUser && disabled != null) return disabled;
    return isSelected ? on : off;
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
                    duration: const Duration(seconds: 3),
                  ),
                );
                return;
              }

              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const MapScreenV2(),
                    settings: const RouteSettings(name: '/map'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
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
              const FlutterSecureStorage storage = FlutterSecureStorage();
              final String? userId = await storage.read(key: 'userId');
              if (userId == null || userId.isEmpty) {
                await showGuestUserPopup(context);
                return;
              }
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/list') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const RecordingScreen(),
                    settings: const RouteSettings(name: '/list'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
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
                        const LiveRec(),
                    settings: const RouteSettings(name: '/Recorder'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
          IconButton(
            tooltip: t('blogExplorer.title'),
            icon: Icon(
              currentPage == BottomBarItem.blog
                  ? Icons.menu_book_rounded
                  : Icons.menu_book_outlined,
              size: 28,
              color: currentPage == BottomBarItem.blog
                  ? const Color(0xFF2D2B18)
                  : const Color(0xFFADADAD),
            ),
            onPressed: () async {
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/blog') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        ScaffoldWithBottomBar(
                      selectedPage: BottomBarItem.blog,
                      appBarTitle: t('blogExplorer.title'),
                      content: const BlogExplorerContent(),
                    ),
                    settings: const RouteSettings(name: '/blog'),
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                  ),
                );
              }
            },
          ),
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
              const FlutterSecureStorage storage = FlutterSecureStorage();
              final String? userId = await storage.read(key: 'userId');
              if (userId == null || userId.isEmpty) {
                await showGuestUserPopup(context);
                return;
              }
              if (!await changeConfirmation()) return;

              if (ModalRoute.of(context)?.settings.name != '/user') {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const UserPage(),
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
