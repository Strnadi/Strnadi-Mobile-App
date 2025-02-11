/*
 * Copyright (C) 2024 [Your Name]
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
import 'package:strnadi/home.dart';
import 'package:strnadi/map/map.dart';
import 'package:strnadi/recording/recorderWithSpectogram.dart';

class ScaffoldWithBottomBar extends StatelessWidget {
  final String appBarTitle;
  final Widget content;

  const ScaffoldWithBottomBar({
    Key? key,
    required this.appBarTitle,
    required this.content,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
      ),
      body: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - kToolbarHeight - kBottomNavigationBarHeight,
        ),
        child: content,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (appBarTitle == 'Recording Screen') {
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RecorderWithSpectogram()),
          );
        },
        child: const Icon(
          Icons.mic,
          size: 30,
        ),
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
            icon: const Icon(Icons.home),
            iconSize: 30.0,
            onPressed: () {
              if (ModalRoute.of(context)?.settings.name != '/home') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HomePage(),
                    settings: const RouteSettings(name: '/home'),
                  ),
                );
              }
            },
          ),
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
        ],
      ),
    );
  }
}