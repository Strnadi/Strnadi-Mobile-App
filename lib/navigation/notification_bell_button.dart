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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/guest_user_popup.dart';
import 'package:strnadi/notificationPage/notifList.dart';

Future<void> _openNotificationScreen(
  BuildContext context, {
  required bool isGuestUser,
}) async {
  const FlutterSecureStorage storage = FlutterSecureStorage();
  final String? userId = await storage.read(key: 'userId');
  if (isGuestUser || userId == null || userId.isEmpty) {
    await showGuestUserPopup(context);
    return;
  }

  if (ModalRoute.of(context)?.settings.name != '/notification') {
    await Navigator.push(
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
}

class NotificationBellButton extends StatefulWidget {
  final bool isGuestUser;
  final bool isSelected;

  const NotificationBellButton({
    super.key,
    this.isGuestUser = false,
    this.isSelected = false,
  });

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  @override
  void initState() {
    super.initState();
    _refreshUnreadCount();
  }

  @override
  void didUpdateWidget(covariant NotificationBellButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isGuestUser != widget.isGuestUser) {
      _refreshUnreadCount();
    }
  }

  void _refreshUnreadCount() {
    if (widget.isGuestUser) {
      DatabaseNew.unreadNotificationCount.value = 0;
      return;
    }
    unawaited(DatabaseNew.refreshUnreadNotificationCount());
  }

  Future<void> _handlePressed() async {
    await _openNotificationScreen(context, isGuestUser: widget.isGuestUser);
    _refreshUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        widget.isSelected ? const Color(0xFF116A7B) : Colors.black87;
    return ValueListenableBuilder<int>(
      valueListenable: DatabaseNew.unreadNotificationCount,
      builder: (context, unreadCount, _) {
        final bool hasUnread = !widget.isGuestUser && unreadCount > 0;
        return IconButton(
          tooltip: t('notifications.title'),
          onPressed: _handlePressed,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                widget.isSelected
                    ? Icons.notifications
                    : Icons.notifications_outlined,
                color: iconColor,
              ),
              if (hasUnread)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
