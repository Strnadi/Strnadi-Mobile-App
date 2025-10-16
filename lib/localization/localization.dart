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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Localization {
  static Map<String, String> _localizedStrings = {};

  static Future<void> load(String? dict) async {
    FlutterSecureStorage storage = const FlutterSecureStorage();

    var language = await storage.read(key: 'language');
    dict ??= 'assets/lang/${language ?? 'cs'}.json';

    final jsonString = await rootBundle.loadString(dict);
    final Map<String, dynamic> jsonMap = json.decode(jsonString);
    _localizedStrings = _flatten(jsonMap);
  }

  static Map<String, String> _flatten(Map<String, dynamic> map,
      [String prefix = '']) {
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
