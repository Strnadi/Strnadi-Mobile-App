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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:strnadi/api/controllers/health_controller.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

/// User preference for mobile data usage
enum DataUsageOption { wifiOnly, wifiAndMobile }

/// Server health status codes
enum ServerHealth { healthy, maintenance, offline }

enum LanguagePreference {
  en,
  cs,
  de;

  String GetVal() => "Hello";

  @override
  String toString() => this.name;
}

enum HostEnvironment { prod, dev }

Logger logger = Logger();
const HealthController _healthController = HealthController();

class Config {
  static Map<String, dynamic>? _config;
  static Map<String, dynamic>? _Fconfig;

  static const String _dataUsagePrefKey = 'data_usage_option';
  static const String _legacyCellularPrefKey = 'CellularData';
  static DataUsageOption? _dataUsageOption;
  static const String _languagePrefKey = 'preferred_language';
  static const Set<String> _supportedLanguageCodes = {'cs', 'en', 'de'};
  static const String _hostEnvPrefKey = 'host_environment';
  static HostEnvironment? _hostEnv;
  static VoidCallback? onHostEnvironmentChanged;

  static const String _defaultHost = String.fromEnvironment(
    'STRNADI_API_HOST',
    defaultValue: 'api.strnadi.cz',
  );
  static const String _defaultDevHost = String.fromEnvironment(
    'STRNADI_DEV_API_HOST',
    defaultValue: '',
  );
  static const String _defaultMapyCzKey = String.fromEnvironment(
    'STRNADI_MAPY_CZ_KEY',
    defaultValue: '',
  );
  static const String _firebaseServiceAccountJson = String.fromEnvironment(
    'FIREBASE_SERVICE_ACCOUNT_JSON',
    defaultValue: '',
  );
  static const String _firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  // Load public config defaults. Sensitive values must come from dart-define.
  static Future<void> loadConfig() async {
    final assetConfig = await _loadJsonAsset('assets/config.json');
    _config = <String, dynamic>{
      'host': _defaultHost,
      if (_defaultDevHost.isNotEmpty) 'devhost': _defaultDevHost,
      'mapy.cz-key': _defaultMapyCzKey,
      ...assetConfig,
    };
    await loadDataUsageOption();
    await loadHostEnvironment();
  }

  static StringFromLanguagePreference(LanguagePreference lang) {
    switch (lang) {
      case LanguagePreference.en:
        return 'en';
      case LanguagePreference.cs:
        return 'cs';
      case LanguagePreference.de:
        return 'de';
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
    }
  }

  static Future<void> loadFirebaseConfig() async {
    if (_firebaseServiceAccountJson.isNotEmpty) {
      if (kReleaseMode) {
        logger.w(
          'Ignoring FIREBASE_SERVICE_ACCOUNT_JSON in release builds. Send push notifications from a backend service instead.',
        );
        _Fconfig = <String, dynamic>{
          if (_firebaseProjectId.isNotEmpty) 'project_id': _firebaseProjectId,
        };
        return;
      }
      final decoded = json.decode(_firebaseServiceAccountJson);
      _Fconfig =
          decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      return;
    }

    _Fconfig = <String, dynamic>{
      if (_firebaseProjectId.isNotEmpty) 'project_id': _firebaseProjectId,
    };
  }

  /// Loads the user's mobile data preference from SharedPreferences
  static Future<void> loadDataUsageOption() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dataUsagePrefKey);
    final bool? legacyCellular = prefs.getBool(_legacyCellularPrefKey);
    if (raw == null) {
      _dataUsageOption = legacyCellular == true
          ? DataUsageOption.wifiAndMobile
          : DataUsageOption.wifiOnly;
      await prefs.setString(_dataUsagePrefKey, _dataUsageOption.toString());
    } else {
      _dataUsageOption = DataUsageOption.values.firstWhere(
        (e) => e.toString() == raw,
        orElse: () => DataUsageOption.wifiOnly,
      );
      if (legacyCellular != null) {
        final DataUsageOption legacyOption = legacyCellular
            ? DataUsageOption.wifiAndMobile
            : DataUsageOption.wifiOnly;
        if (legacyOption != _dataUsageOption) {
          _dataUsageOption = legacyOption;
          await prefs.setString(_dataUsagePrefKey, _dataUsageOption.toString());
        }
      }
    }
  }

  /// Loads the selected host environment (prod/dev) from SharedPreferences
  static Future<void> loadHostEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostEnvPrefKey);
    if (raw == null) {
      _hostEnv = HostEnvironment.prod; // default
      await prefs.setString(_hostEnvPrefKey, _hostEnv.toString());
    } else {
      _hostEnv = HostEnvironment.values.firstWhere(
        (e) => e.toString() == raw,
        orElse: () => HostEnvironment.prod,
      );
    }
  }

  /// Gets the current mobile data preference
  static DataUsageOption get dataUsageOption {
    return _dataUsageOption ?? DataUsageOption.wifiOnly;
  }

  /// Gets the current host environment (prod/dev)
  static HostEnvironment get hostEnvironment {
    return _hostEnv ?? HostEnvironment.prod;
  }

  /// Sets the host environment and persists it
  static Future<void> setHostEnvironment(HostEnvironment env) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostEnvPrefKey, env.toString());
    _hostEnv = env;
    onHostEnvironmentChanged?.call();
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
    String? raw = prefs.getString(_languagePrefKey);
    if (raw == null || !_supportedLanguageCodes.contains(raw)) {
      raw = _resolveInitialLanguageCode();
      await prefs.setString(_languagePrefKey, raw);
    }
    return LanguagePreference.values.firstWhere(
      (e) => e.toString() == raw,
      orElse: () => LanguagePreference.en,
    );
  }

  static String _resolveInitialLanguageCode() {
    final deviceCode =
        ui.PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    if (_supportedLanguageCodes.contains(deviceCode)) {
      return deviceCode;
    }
    return 'en';
  }

  // Get API Key
  static String get mapsApiKey {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _config!["mapy.cz-key"] as String? ?? '';
  }

  static String get host {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    final useDev = (hostEnvironment == HostEnvironment.dev);
    final devHost = _config!["devhost"] as String?;
    if (useDev && devHost != null && devHost.isNotEmpty) {
      return devHost;
    }
    return _config!["host"] as String;
  }

  static String get firebaseProjectId {
    if (_Fconfig == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return _Fconfig!["project_id"] as String? ?? '';
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
      final response = await _healthController
          .checkBackendHealth(host: host)
          .timeout(const Duration(seconds: 5));
      logger
          .i('Checking API health at $uri: status code ${response.statusCode}');
      if (response.statusCode == 200) {
        return ServerHealth.healthy;
      } else if (response.statusCode == 503) {
        return ServerHealth.maintenance;
      } else {
        return ServerHealth.offline;
      }
    } on SocketException catch (e, stackTrace) {
      logger.w('SocketException when checking API health: $e',
          error: e, stackTrace: stackTrace);
      return ServerHealth.offline;
    } on TimeoutException catch (e, stackTrace) {
      logger.w('Timeout when checking API health: $e',
          error: e, stackTrace: stackTrace);
      return ServerHealth.offline;
    } catch (e, stackTrace) {
      logger.e('Unexpected error checking API health: $e',
          error: e, stackTrace: stackTrace);
      return ServerHealth.offline;
    }
  }

  /// Checks whether the device has any network connectivity (basic)
  static Future<bool> get hasBasicInternet async {
    final results = await Connectivity().checkConnectivity();
    return _hasNetworkTransport(results);
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
    final connections = await Connectivity().checkConnectivity();
    if (_usesMobileData(connections) &&
        dataUsageOption == DataUsageOption.wifiOnly) {
      return false;
    }
    return await isBackendAvailable;
  }

  static Future<Map<String, dynamic>> _loadJsonAsset(String path) async {
    try {
      final jsonString = await rootBundle.loadString(path);
      final decoded = json.decode(jsonString);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FlutterError catch (e) {
      logger.w('Optional config asset $path is not available: ${e.message}');
      return <String, dynamic>{};
    } on FormatException catch (e, stackTrace) {
      logger.e('Invalid JSON in config asset $path',
          error: e, stackTrace: stackTrace);
      return <String, dynamic>{};
    }
  }

  static bool _hasNetworkTransport(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  static bool _usesMobileData(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.mobile);
  }
}
