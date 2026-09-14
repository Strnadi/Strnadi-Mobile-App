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
import 'package:strnadi/components/liquid_glass.dart';
import 'package:strnadi/components/native_ios_controls.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/articles/blog_explorer_content.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localRecordings/recList.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/mapv2.dart';
import 'package:strnadi/navigation/guest_user_popup.dart';
import 'package:strnadi/navigation/notification_bell_button.dart';
import 'package:strnadi/navigation/recorder_exit_policy.dart';
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
    final bool shouldRedirectAndroidBackToSessionLanding =
        !allowArrowBack &&
        (selectedPage == BottomBarItem.map ||
            selectedPage == BottomBarItem.blog ||
            selectedPage == BottomBarItem.user);
    final Widget pageContent = content;

    final scaffold = Scaffold(
      extendBody: selectedPage == BottomBarItem.map,
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
                  GlassIconButton(
                    nativeSymbol: 'rectangle.portrait.and.arrow.right',
                    tooltip: t('logout.logout'),
                    icon: icon != null ? Icon(icon) : const Icon(Icons.logout),
                    onPressed: logout,
                  ),
              ],
              leading: allowArrowBack
                  ? GlassIconButton(
                      nativeSymbol: 'chevron.left',
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 22,
                      ),
                      onPressed: () => Navigator.maybePop(context),
                    )
                  : null,
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
                    child: NotificationBellButton(
                      isGuestUser: guestUser,
                      isSelected: selectedPage == BottomBarItem.notification,
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
  final RecorderExitPolicy changeConfirmation;

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
    final destinations = <_BottomBarDestination>[
      _BottomBarDestination(
        label: t('bottomBar.tabs.map'),
        selected: currentPage == BottomBarItem.map,
        icon: Image.asset(
          _iconAsset(
            on: 'assets/icons/mapOn.png',
            off: 'assets/icons/mapOff.png',
            isSelected: currentPage == BottomBarItem.map,
          ),
          width: 40,
          height: 40,
        ),
        onTap: () async {
          if (!await Config.hasBasicInternet) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t('bottomBar.errors.noInternetMap')),
                duration: const Duration(seconds: 3),
              ),
            );
            return;
          }
          // Do not destroy an active recording unless the destination is
          // actually available. Offline map navigation is rejected above.
          if (!await permitsRecorderExit(changeConfirmation)) return;
          if (!context.mounted) return;

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
      _BottomBarDestination(
        label: t('bottomBar.tabs.list'),
        selected: currentPage == BottomBarItem.list,
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
        onTap: () async {
          const FlutterSecureStorage storage = FlutterSecureStorage();
          final String? userId = await storage.read(key: 'userId');
          if (!context.mounted) return;
          if (userId == null || userId.isEmpty) {
            await showGuestUserPopup(
              context,
              recorderExitPolicy: changeConfirmation,
            );
            return;
          }
          if (!await permitsRecorderExit(changeConfirmation)) return;
          if (!context.mounted) return;

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
      _BottomBarDestination(
        label: t('bottomBar.tabs.recorder'),
        selected: currentPage == BottomBarItem.recorder,
        icon: Image.asset(
          _iconAsset(
            on: 'assets/icons/micOn.png',
            off: 'assets/icons/micOff.png',
            isSelected: currentPage == BottomBarItem.recorder,
          ),
          width: 40,
          height: 40,
        ),
        onTap: () async {
          // Tapping the selected recorder tab is a no-op. Asking the
          // recorder exit policy here would discard audio without
          // navigating anywhere.
          if (currentPage == BottomBarItem.recorder ||
              ModalRoute.of(context)?.settings.name == '/Recorder') {
            return;
          }
          if (!await permitsRecorderExit(changeConfirmation)) return;
          if (!context.mounted) return;

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
        },
      ),
      _BottomBarDestination(
        selected: currentPage == BottomBarItem.blog,
        label: t('blogExplorer.title'),
        icon: Icon(
          currentPage == BottomBarItem.blog
              ? Icons.menu_book_rounded
              : Icons.menu_book_outlined,
          size: 28,
          color: currentPage == BottomBarItem.blog
              ? const Color(0xFF2D2B18)
              : const Color(0xFFADADAD),
        ),
        onTap: () async {
          if (!await permitsRecorderExit(changeConfirmation)) return;
          if (!context.mounted) return;

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
      _BottomBarDestination(
        label: t('bottomBar.tabs.user'),
        selected: currentPage == BottomBarItem.user,
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
        onTap: () async {
          const FlutterSecureStorage storage = FlutterSecureStorage();
          final String? userId = await storage.read(key: 'userId');
          if (!context.mounted) return;
          if (userId == null || userId.isEmpty) {
            await showGuestUserPopup(
              context,
              recorderExitPolicy: changeConfirmation,
            );
            return;
          }
          if (!await permitsRecorderExit(changeConfirmation)) return;
          if (!context.mounted) return;

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
    ];
    if (usesNativeIOSControls) {
      return NativeIOSTabBar(
        labels: destinations.map((item) => item.label).toList(),
        selectedIndex: destinations.indexWhere((item) => item.selected),
        onTap: (index) async {
          if (index < 0 || index >= destinations.length) return;
          if (destinations[index].selected) return;
          await destinations[index].onTap();
        },
      );
    }
    return GlassNavigationBar(
      children: [
        for (final item in destinations)
          IconButton(
            tooltip: item.label,
            isSelected: item.selected,
            icon: item.icon,
            onPressed: item.onTap,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: item.selected
                  ? const Color(0xFFE4EBDB)
                  : Colors.transparent,
              shape: const StadiumBorder(),
            ),
          ),
      ],
    );
  }
}

class _BottomBarDestination {
  const _BottomBarDestination({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Widget icon;
  final Future<void> Function() onTap;
}
