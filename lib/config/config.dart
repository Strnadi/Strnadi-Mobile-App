import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Config {
  static Map<String, dynamic>? _config;

  // Load config.json
  static Future<void> loadConfig() async {
    String jsonString = await rootBundle.loadString('assets/config.json');
    _config = json.decode(jsonString);
  }

  // Get API Key
  static String get mapsApiKey {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _config!["mapy.cz-key"];
  }
}