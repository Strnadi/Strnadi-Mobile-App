import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Localization {
  static Map<String, String> _localizedStrings = {};

  static Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/lang/cs.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = jsonMap.map((key, value) => MapEntry(key, value.toString()));
  }

  static String t(String key) {
    return _localizedStrings[key] ?? key;
  }
}

String t(String key) => Localization.t(key);
