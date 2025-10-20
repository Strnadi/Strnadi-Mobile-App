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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/user/settingsPages/appSettings.dart';
import 'package:strnadi/user/settingsPages/connectedPlatforms.dart';
import 'package:strnadi/user/settingsPages/userInfo.dart' hide logger;
import 'package:url_launcher/url_launcher.dart';
import 'package:strnadi/md_renderer.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/config.dart';

class MenuScreen extends StatelessWidget {
  final List<String> menuItems = [
    t('user.menu.items.personalInfo'),
    t('user.menu.items.settings'),
    t('user.menu.items.connectedAccounts'),
    //'Vaše úspěchy',
    t('user.menu.items.guide'),
    t('user.menu.items.aboutProject'),
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

  _launchURL(String ur) async {
    final Uri url = Uri.parse(ur);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<String> getMarkdown(int index) async {
    var i = -1;
    // hardcoded values from the backend with the article id
    switch (index) {
      case 3:
        i = 6;
      case 4:
        i = 3;
    }

    final url = Uri.parse('https://${Config.host}/articles/$i/Text.md');
    final response = await http.get(url, headers: {
      'accept': 'application/json',
    });

    if (response.statusCode == 200) {
      final text = utf8.decode(response.bodyBytes);
      return text;
    }

    return 'Error loading article';
  }

  void Executor(int index, BuildContext context) async {
    if (index == 0) {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => ProfileEditPage()));
    } else if (index == 1) {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => SettingsPage()));
    } else if (index == 2) {
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => Connectedplatforms()));
    } else if (index == 3) {
      var text = await getMarkdown(index);
      logger.i('Markdown content loaded');
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => MDRender(
                    mdContent: text,
                    title: 'Jak nahrávat',
                  )));
    } else if (index == 4) {
      var text = await getMarkdown(index);
      logger.i('Markdown content loaded');
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => MDRender(
                    mdContent: text,
                    title: 'O projektu',
                  )));
    } else if (index == 5) {
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
