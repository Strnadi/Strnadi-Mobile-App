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
import 'package:url_launcher/url_launcher.dart';

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
    if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsPage()));
    }
    if (index == 3) {
      _launchURL('https://new.strnadi.cz/how-to-record');
    }
    if (index == 4) {
      _launchURL("https://new.strnadi.cz/about-project");
    }
  }
}