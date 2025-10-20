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
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';

/// User preference for mobile data usage
enum DataUsageOption { wifiOnly, wifiAndMobile }

/// Server health status codes
enum ServerHealth { healthy, maintenance, offline }

enum LanguagePreference { systemDefault, en, cs, de }

Logger logger = Logger();

class Config {
  static Map<String, dynamic>? _config;
  static Map<String, dynamic>? _Fconfig;

  static const String _dataUsagePrefKey = 'data_usage_option';
  static DataUsageOption? _dataUsageOption;
  static const String _languagePrefKey = 'preferred_language';

  // Load config.json
  static Future<void> loadConfig() async {
    String jsonString = await rootBundle.loadString('assets/secrets.json');
    _config = json.decode(jsonString);
    await loadDataUsageOption();
  }

  static StringFromLanguagePreference(LanguagePreference lang) {
    switch (lang) {
      case LanguagePreference.en:
        return 'en';
      case LanguagePreference.cs:
        return 'cs';
      case LanguagePreference.de:
        return 'de';
      case LanguagePreference.systemDefault:
      default:
        return 'system';
    }
  }

  static LangFromString(String code) {
    switch (code) {
      case 'en':
        return LanguagePreference.en;
      case 'cs':
        return LanguagePreference.cs;
      case 'de':
        return LanguagePreference.de;
      default:
        return LanguagePreference.systemDefault;
    }
  }

  static Future<void> loadFirebaseConfig() async {
    String jsonString =
        await rootBundle.loadString('assets/firebase-secrets.json');
    _Fconfig = json.decode(jsonString);
  }

  /// Loads the user's mobile data preference from SharedPreferences
  static Future<void> loadDataUsageOption() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataUsagePrefKey);
    if (raw == null) {
      // First launch: default to Wi-Fi only and save
      _dataUsageOption = DataUsageOption.wifiOnly;
      await prefs.setString(_dataUsagePrefKey, _dataUsageOption.toString());
    } else {
      _dataUsageOption = DataUsageOption.values.firstWhere(
        (e) => e.toString() == raw,
        orElse: () => DataUsageOption.wifiOnly,
      );
    }
  }

  /// Gets the current mobile data preference
  static DataUsageOption get dataUsageOption {
    return _dataUsageOption ?? DataUsageOption.wifiOnly;
  }

  /// Sets the user's mobile data preference
  static Future<void> setDataUsageOption(DataUsageOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataUsagePrefKey, option.toString());
    _dataUsageOption = option;
  }

  static Future<void> setLanguagePreference(
      LanguagePreference languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefKey, languageCode.toString());
  }

  static Future<LanguagePreference> getLanguagePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_languagePrefKey);
    if (raw == null) {
      return LanguagePreference.systemDefault;
    } else {
      return LanguagePreference.values.firstWhere(
        (e) => e.toString() == raw,
        orElse: () => LanguagePreference.systemDefault,
      );
    }
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

  static String get firebaseProjectId {
    if (_Fconfig == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _Fconfig!["project_id"];
  }

  static Map<String, dynamic>? get firebaseServiceAccountJson {
    if (_Fconfig == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _Fconfig;
  }

  /// Checks the server health via a HEAD request to {host}/utils/health
  static Future<ServerHealth> checkServerHealth() async {
    final uri = Uri.parse('https://${host}/utils/health');
    try {
      final response = await http.head(uri).timeout(const Duration(seconds: 5));
      logger
          .i('Checking API health at $uri: status code ${response.statusCode}');
      if (response.statusCode == 200) {
        return ServerHealth.healthy;
      } else if (response.statusCode == 503) {
        return ServerHealth.maintenance;
      } else {
        return ServerHealth.offline;
      }
    } on SocketException catch (e) {
      logger.w('SocketException when checking API health: $e');
      return ServerHealth.offline;
    } on TimeoutException catch (e) {
      logger.w('Timeout when checking API health: $e');
      return ServerHealth.offline;
    } catch (e) {
      logger.e('Unexpected error checking API health: $e');
      return ServerHealth.offline;
    }
  }

  /// Checks whether the device has any network connectivity (basic)
  static Future<bool> get hasBasicInternet async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Checks whether the backend is reachable (via health endpoint)
  static Future<bool> get isBackendAvailable async {
    try {
      final health = await checkServerHealth();
      return health == ServerHealth.healthy;
    } catch (_) {
      return false;
    }
  }

  /// Determines if upload operations are allowed based on connectivity, backend, and user preference
  static Future<bool> get canUpload async {
    if (!await hasBasicInternet) return false;
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.mobile &&
        dataUsageOption == DataUsageOption.wifiOnly) {
      return false;
    }
    return await isBackendAvailable;
  }
}
