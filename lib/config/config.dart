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
}