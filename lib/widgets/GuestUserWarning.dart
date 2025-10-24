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

class GuestUserRules extends StatelessWidget {
  const GuestUserRules({Key? key}) : super(key: key);

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
        ),
      ],
    );
  }
}
