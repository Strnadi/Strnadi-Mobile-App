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

import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/user/settingsPages/achievementsPage.dart';
import 'package:strnadi/user/settingsPages/appSettings.dart';
import 'package:strnadi/user/settingsPages/connectedPlatforms.dart';
import 'package:strnadi/user/settingsPages/userInfo.dart' hide logger;
import 'package:package_info_plus/package_info_plus.dart';

class MenuScreen extends StatelessWidget {
  Function() refreshUserCallback;
  Function(BuildContext, {bool popUp}) logout;

  MenuScreen(
      {Key? key, required this.refreshUserCallback, required this.logout})
      : super(key: key);

  final List<String> menuItems = [
    t('user.menu.items.personalInfo'),
    t('user.menu.items.settings'),
    t('user.menu.items.connectedAccounts'),
    t('user.menu.items.achievements'),
    t('user.menu.items.aboutApp'),
  ];

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.5;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: ListView.separated(
            itemCount: menuItems.length,
            separatorBuilder: (context, index) => Divider(),
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(menuItems[index]),
                trailing: Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Executor(index, context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void Executor(int index, BuildContext context) async {
    if (index == 0) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => ProfileEditPage(
                    refreshUserCallback: refreshUserCallback,
                  )));
    } else if (index == 1) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => SettingsPage(logout: logout)));
    } else if (index == 2) {
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => Connectedplatforms()));
    } else if (index == 3) {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => AchievementsPage()));
    } else if (index == 4) {
      _showAboutDialog(context);
    } else {
      // TODO: implement other menu items
      _showMessage(t('menu.error.notImplemented'), context);
    }
  }

  void _showMessage(String s, BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(title: Text(s)),
    );
  }

  void _showAboutDialog(BuildContext context) async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    showAboutDialog(
      context: context,
      applicationName: 'Strnadi Mobile App',
      applicationVersion: packageInfo.version,
      applicationIcon: Icon(Icons.info_outline),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 15),
          child: Text(t('user.menu.dialogs.aboutApp.creators')),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(t('user.menu.dialogs.aboutApp.contact')),
        ),
      ],
    );
  }
}
