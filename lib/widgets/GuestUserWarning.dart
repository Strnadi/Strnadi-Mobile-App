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
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/authorizator.dart';
import '../localization/localization.dart';
import '../navigation/recorder_exit_policy.dart';

Widget _buildAuthorizator(BuildContext context) => Authorizator();

class GuestUserRules extends StatelessWidget {
  final RecorderExitPolicy? recorderExitPolicy;
  final WidgetBuilder loginPageBuilder;

  const GuestUserRules({
    super.key,
    this.recorderExitPolicy,
    this.loginPageBuilder = _buildAuthorizator,
  });

  @override
  Widget build(BuildContext context) {
    // tell the user that in guest mode he can view map and record but cannot send them unless he creates an account with cupertino
    return CupertinoAlertDialog(
      title: Text(t('widgets.guest_user_rules.title')),
      content: Text(t('widgets.guest_user_rules.content')),
      actions: [
        CupertinoDialogAction(
          child: Text(t('widgets.guest_user_rules.ok')),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        CupertinoDialogAction(
          child: Text(t('widgets.guest_user_rules.login')),
          onPressed: () async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            if (!context.mounted) return;
            if (!await permitsRecorderExit(recorderExitPolicy)) return;
            if (!context.mounted) return;

            try {
              await prefs.setBool('popupShown', false);
            } catch (_) {
              // This preference only controls whether the guest hint repeats;
              // it must not strand the user after recorder cleanup succeeded.
            }
            if (!context.mounted) return;

            final NavigatorState navigator = Navigator.of(context);
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
        ),
      ],
    );
  }
}
