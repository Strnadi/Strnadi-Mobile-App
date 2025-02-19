/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'package:strnadi/map/map.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/user/userPage.dart';

class ScaffoldWithBottomBar extends StatelessWidget {
  final String appBarTitle;
  final Widget content;
  final bool? logout;

  const ScaffoldWithBottomBar({
    Key? key,
    required this.appBarTitle,
    required this.content,
    this.logout,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(child: Text(appBarTitle)),
        actions: [
          if (logout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                logout!;
              },
            ),
        ],
        automaticallyImplyLeading: false,
      ),
      body: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - kToolbarHeight - kBottomNavigationBarHeight,
        ),
        child: content,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: const ReusableBottomAppBar(),
    );
  }
}

class ReusableBottomAppBar extends StatelessWidget {
  const ReusableBottomAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.map),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OSMmap(),
                    settings: const RouteSettings(name: '/map'),
                  ),
                );
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.menu),
            iconSize: 30.0,
            onPressed: () {
              // todo add the correct route
              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveRec(),
                    settings: const RouteSettings(name: '/map'),
                  ),
                );
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.mic),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/Recorder') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecorderWithSpectogram(),
                    settings: const RouteSettings(name: '/Recorder'),
                  ),
                );
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            iconSize: 30.0,
            onPressed: () {
              // todo add the correct route
              if (ModalRoute.of(context)?.settings.name != '/map') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OSMmap(),
                    settings: const RouteSettings(name: '/map'),
                  ),
                );
              }
            },
          ),

          IconButton(
            icon: const Icon(Icons.account_circle),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/user') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserPage(),
                    settings: const RouteSettings(name: '/user'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}