import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Localization {
  static Map<String, String> _localizedStrings = {};

  static Future<void> load() async {
    final jsonString = await rootBundle.loadString('assets/lang/cs.json');
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = _flatten(jsonMap);
  }

  static Map<String, String> _flatten(Map<String, dynamic> map, [String prefix = '']) {
    final result = <String, String>{};
    map.forEach((key, value) {
      final newKey = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map) {
        result.addAll(_flatten(value.cast<String, dynamic>(), newKey));
      } else {
        result[newKey] = value.toString();
      }
    });
    return result;
  }

  static String t(String key) {
    return _localizedStrings[key] ?? key;
  }
}

String t(String key) => Localization.t(key);
