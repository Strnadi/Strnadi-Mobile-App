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
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// Server health status codes
enum ServerHealth { healthy, maintenance }

Logger logger = Logger();

class Config {
  static Map<String, dynamic>? _config;
  static Map<String, dynamic>? _Fconfig;

  // Load config.json
  static Future<void> loadConfig() async {
    String jsonString = await rootBundle.loadString('assets/secrets.json');
    _config = json.decode(jsonString);
  }

  static Future<void> loadFirebaseConfig() async {
    String jsonString = await rootBundle.loadString('assets/firebase-secrets.json');
    _Fconfig = json.decode(jsonString);
  }

  // Get API Key
  static String get mapsApiKey {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _config!["mapy.cz-key"];
  }

  static String get host {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    if (kDebugMode && _config!.containsKey("devhost")) {
      return _config!["devhost"];
    }
    return _config!["host"];
  }

  static String get firebaseProjectId{
    if (_Fconfig == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _Fconfig!["project_id"];
  }

  static Map<String, dynamic>? get firebaseServiceAccountJson{
    if (_Fconfig == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _Fconfig;
  }

  /// Checks the server health via a HEAD request to {host}/utils/health
  static Future<ServerHealth> checkServerHealth() async {
    final uri = Uri.parse('https://${host}/utils/health');
    final response = await http.head(uri);
    logger.i('Checking API health + https://${host}/utils/health with response ${response.statusCode}');
    if (response.statusCode == 200) {
      return ServerHealth.healthy;
    } else if (response.statusCode == 503) {
      return ServerHealth.maintenance;
    } else {
      throw Exception('Unexpected status code: ${response.statusCode}');
    }
  }
}