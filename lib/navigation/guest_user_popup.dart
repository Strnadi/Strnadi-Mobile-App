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
import 'package:strnadi/navigation/recorder_exit_policy.dart';

Widget _buildAuthorizator(BuildContext context) => Authorizator();

Future<void> showGuestUserPopup(
  BuildContext context, {
  RecorderExitPolicy? recorderExitPolicy,
  WidgetBuilder loginPageBuilder = _buildAuthorizator,
}) {
  return showCupertinoDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return CupertinoAlertDialog(
        title: Text(t('bottomBar.errors.guest_user')),
        content: Text(t('bottomBar.errors.guest_user_desc')),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: Text(t('bottomBar.errors.close')),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final SharedPreferences prefs =
                  await SharedPreferences.getInstance();
              if (!dialogContext.mounted) return;
              if (!await permitsRecorderExit(recorderExitPolicy)) return;
              if (!dialogContext.mounted) return;

              try {
                await prefs.setBool('popupShown', false);
              } catch (_) {
                // This preference only controls whether the guest hint repeats;
                // it must not strand the user after recorder cleanup succeeded.
              }
              if (!dialogContext.mounted) return;

              final NavigatorState navigator = Navigator.of(dialogContext);
              navigator.pop();
              navigator.pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      loginPageBuilder(context),
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
