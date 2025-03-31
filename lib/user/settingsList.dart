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
import 'package:strnadi/user/settingsPages/appSettings.dart';
import 'package:strnadi/user/settingsPages/userInfo.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:strnadi/md_renderer.dart';
import 'package:package_info_plus/package_info_plus.dart';

class MenuScreen extends StatelessWidget {
  final List<String> menuItems = [
    'Osobní údaje',
    'Nastavení',
    'Vaše úspěchy',
    'Příručka',
    'O projektu',
    'O aplikaci',
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

  void Executor(int index, BuildContext context) {
    if (index == 0) {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => ProfileEditPage()));
    } else if (index == 1) {
      _showMessage("Nastavení ještě není dostupné", context);
      //Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsPage()));
    } else if (index == 3) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  MDRender(mdPath: 'assets/docs/how-to-record.md')));
    } else if (index == 4) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  MDRender(mdPath: 'assets/docs/about-project.md')));
    } else if (index == 5) {
      _showAboutDialog(context);
    } else {
      _showMessage("tato funkce neni jeste dostupna", context);
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
          child: Text('Creators: Marian Pecqueur && Jan Drobílek'),
        ),
      ],
    );
  }
}