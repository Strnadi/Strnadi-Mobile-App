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
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/bottomBar.dart';
import 'package:strnadi/main.dart';

import 'auth/login.dart';


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      appBarTitle: 'Welcome to Flutter',
      content: Center(
        child: ElevatedButton(
          onPressed: ()  =>{
            Logout(context)
          },
          child: const Text('Logout'),
        ),
      ),
    );
  }

  void Logout(BuildContext context) {
    final localStorage = const FlutterSecureStorage();
    localStorage.delete(key: 'token');
    Navigator.push(context, MaterialPageRoute(builder: (context) => MyApp()));
  }
}
