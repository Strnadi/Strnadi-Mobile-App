import 'dart:convert';
import 'package:flutter/services.dart';

class Translations {
  static Map<String, dynamic> _strings = {};

  static Future<void> load(String languageCode) async {
    final data = await rootBundle.loadString('assets/i18n/' + languageCode + '.json');
    _strings = json.decode(data) as Map<String, dynamic>;
  }

  static String text(String key) {
    return _strings[key] ?? key;
  }
}
