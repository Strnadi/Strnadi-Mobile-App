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

import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/auth/authorizator.dart';
import 'package:strnadi/localization/localization.dart';

Future<void> showGuestUserPopup(BuildContext context) {
  return showCupertinoDialog(
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
              Navigator.of(context).pop();
              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              await prefs.setBool('popupShown', false);
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
