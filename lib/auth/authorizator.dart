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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/home.dart';

enum AuthType { login, register }

class Authorizator extends StatefulWidget {
  final Widget login;
  final Widget register;

  const Authorizator({
    Key? key,
    required this.login,
    required this.register,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}

class _AuthState extends State<Authorizator> {
  AuthType authType = AuthType.login;

  void isLoggedIn() {
    // Check if user is logged in
    final secureStorage = FlutterSecureStorage();
    final token = secureStorage.read(key: 'jwt');
    if (token != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 20,
      children: [
        SegmentedButton<AuthType>(
          segments: const <ButtonSegment<AuthType>>[
            ButtonSegment<AuthType>(
                value: AuthType.login,
                label: Text('Login'),
                icon: Icon(Icons.key)),
            ButtonSegment<AuthType>(
                value: AuthType.register,
                label: Text('Register'),
                icon: Icon(Icons.account_circle_rounded)),
          ],
          selected: <AuthType>{authType},
          onSelectionChanged: (Set<AuthType> newSelection) {
            setState(() {
              authType = newSelection.first;
            });
          },
        ),
        Center(
          child: authType == AuthType.login ? widget.login : widget.register,
        )
      ],
    );
  }
}