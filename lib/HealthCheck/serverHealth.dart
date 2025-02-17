/*
 * Copyright (C) 2024 Marian Pecqueur && Jan Drobílek
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
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

final logger = Logger();

class ServerHealth extends StatefulWidget {
  const ServerHealth({Key? key}) : super(key: key);

  @override
  _ServerHealthState createState() => _ServerHealthState();
}

class _ServerHealthState extends State<ServerHealth> {
  bool _isServerHealthy = false;

  void checkServerHealth() async {
    final url = Uri.parse('https://strnadiapi.slavetraders.tech/utils/health');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        setState(() {
          _isServerHealthy = true;
        });
      }
    } catch (e) {
      logger.e(e);
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    checkServerHealth();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Center(
        child: _isServerHealthy
            ? const Text('Server is healthy', style: TextStyle(color: Colors.green),)
            : const Text('Server is down', style: TextStyle(color: Colors.red),),
      ),
    );
  }
}