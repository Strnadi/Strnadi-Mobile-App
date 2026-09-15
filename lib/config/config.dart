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
import 'package:strnadi/logging/app_logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'host_environment.dart';
import 'package:strnadi/config/oauth_configuration.dart';
export 'host_environment.dart';

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

AppLogger logger = AppLogger(scope: 'config.config');
const HealthController _healthController = HealthController();

class Config {
  static Map<String, dynamic>? _config;

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
  static const bool _hasDefaultHost = bool.hasEnvironment('STRNADI_API_HOST');
  static const String _defaultDevHost = String.fromEnvironment(
    'STRNADI_DEV_API_HOST',
    defaultValue: '',
  );
  static const bool _hasDefaultDevHost = bool.hasEnvironment(
    'STRNADI_DEV_API_HOST',
  );
  static const String _defaultPreprodHost = String.fromEnvironment(
    'STRNADI_PREPROD_API_HOST',
    defaultValue: 'preprod-api.strnadi.cz',
  );
  static const bool _hasDefaultPreprodHost = bool.hasEnvironment(
    'STRNADI_PREPROD_API_HOST',
  );

  static const _administrationDefaults = <String, String>{
    'administrationurl': String.fromEnvironment(
      'STRNADI_ADMINISTRATION_URL',
      defaultValue: '',
    ),
    'projectid': String.fromEnvironment('STRNADI_PROJECT_ID', defaultValue: ''),
    'devadministrationurl': String.fromEnvironment(
      'STRNADI_DEV_ADMINISTRATION_URL',
      defaultValue: '',
    ),
    'devprojectid': String.fromEnvironment(
      'STRNADI_DEV_PROJECT_ID',
      defaultValue: '',
    ),
    'preprodadministrationurl': String.fromEnvironment(
      'STRNADI_PREPROD_ADMINISTRATION_URL',
      defaultValue: 'https://preprod-administration.strnadi.cz/',
    ),
    'preprodprojectid': String.fromEnvironment(
      'STRNADI_PREPROD_PROJECT_ID',
      defaultValue: '01a08608-44b7-7aba-8d0c-542148b30bf2',
    ),
  };
  static const _administrationOverrides = <String, bool>{
    'administrationurl': bool.hasEnvironment('STRNADI_ADMINISTRATION_URL'),
    'projectid': bool.hasEnvironment('STRNADI_PROJECT_ID'),
    'devadministrationurl': bool.hasEnvironment(
      'STRNADI_DEV_ADMINISTRATION_URL',
    ),
    'devprojectid': bool.hasEnvironment('STRNADI_DEV_PROJECT_ID'),
    'preprodadministrationurl': bool.hasEnvironment(
      'STRNADI_PREPROD_ADMINISTRATION_URL',
    ),
    'preprodprojectid': bool.hasEnvironment('STRNADI_PREPROD_PROJECT_ID'),
  };

  // Load public configuration; server credentials are owned by the backend.
  static Future<void> loadConfig() async {
    final assetConfig = await _loadJsonAsset('assets/config.json');
    _config = <String, dynamic>{
      ..._administrationDefaults,
      'host': _defaultHost,
      'preprodhost': _defaultPreprodHost,
      if (_defaultDevHost.isNotEmpty) 'devhost': _defaultDevHost,
      ...assetConfig,
    };
    _applyDartDefineOverrides(_config!);
    await loadDataUsageOption();
    await loadHostEnvironment();
  }

  static void _applyDartDefineOverrides(Map<String, dynamic> config) {
    for (final entry in _administrationOverrides.entries) {
      if (entry.value) config[entry.key] = _administrationDefaults[entry.key];
    }
    if (_hasDefaultHost) {
      config['host'] = _defaultHost;
    }
    if (_hasDefaultDevHost) {
      if (_defaultDevHost.isEmpty) {
        config.remove('devhost');
      } else {
        config['devhost'] = _defaultDevHost;
      }
    }
    if (_hasDefaultPreprodHost) {
      // Keep an explicitly empty override: resolving preprod must fail closed.
      config['preprodhost'] = _defaultPreprodHost;
    }
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

  /// Loads the selected host environment from SharedPreferences.
  static Future<void> loadHostEnvironment() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostEnvPrefKey);
    if (raw == null) {
      _hostEnv = HostEnvironment.prod; // default
      await prefs.setString(_hostEnvPrefKey, _hostEnv.toString());
    } else {
      _hostEnv = HostEnvironment.fromPreference(raw);
    }
  }

  /// Gets the current mobile data preference
  static DataUsageOption get dataUsageOption {
    return _dataUsageOption ?? DataUsageOption.wifiOnly;
  }

  /// Gets the current host environment (prod/dev/preprod).
  static HostEnvironment get hostEnvironment {
    return _hostEnv ?? HostEnvironment.prod;
  }

  /// Whether the persisted host choice has been loaded in this isolate.
  ///
  /// Background isolates must not silently attribute account-owned cache data
  /// to production merely because their preferences have not loaded yet.
  static bool get isHostEnvironmentLoaded => _hostEnv != null;

  /// Sets the host environment and persists it
  static Future<void> setHostEnvironment(HostEnvironment env) async {
    hostForEnvironment(env); // Validate before changing persisted state.
    if (env == HostEnvironment.preprod) {
      administrationForEnvironment(env);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_hostEnvPrefKey, env.toString())) {
      throw StateError('Could not persist the server environment.');
    }
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
    LanguagePreference languageCode,
  ) async {
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
    final deviceCode = ui.PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    if (_supportedLanguageCodes.contains(deviceCode)) {
      return deviceCode;
    }
    return 'en';
  }

  static String get host => hostForEnvironment(hostEnvironment);

  static bool get usesAdministration =>
      hostEnvironment == HostEnvironment.preprod;

  static OAuthConfiguration? get administration =>
      administrationForEnvironment(hostEnvironment);

  static OAuthConfiguration? administrationForEnvironment(
    HostEnvironment environment,
  ) {
    if (_config == null) {
      throw StateError('Config not loaded. Call loadConfig() first.');
    }
    final prefix = environment == HostEnvironment.prod ? '' : environment.name;
    final issuer = _config!['${prefix}administrationurl'];
    final project = _config!['${prefix}projectid'];
    if (issuer == '' && project == '') {
      if (environment == HostEnvironment.preprod) {
        throw StateError('Preprod Administration configuration is required.');
      }
      return null;
    }
    if (issuer is! String || project is! String) {
      throw StateError('Invalid Administration configuration.');
    }
    return OAuthConfiguration(
      environment: environment.name,
      issuer: Uri.parse(issuer),
      tenantOrigin: Uri.https(hostForEnvironment(environment)),
      projectId: project,
    );
  }

  /// OAuth data remains separate from legacy integer-owned preprod data.
  static String get dataEnvironment {
    if (!usesAdministration) return hostEnvironment.name;
    final configuration = administration!;
    return 'preprod|${configuration.issuer.origin}|${configuration.tenantOrigin.origin}|${configuration.projectId}';
  }

  static Uri get administrationOrigin =>
      usesAdministration ? administration!.issuer : Uri.https(host);

  static String get administrationHost => administrationOrigin.host;

  static String hostForEnvironment(HostEnvironment environment) {
    if (_config == null) {
      throw Exception("Config not loaded. Call loadConfig() first.");
    }
    return resolveApiHost(environment, _config!);
  }

  /// Checks the server health via a HEAD request to {host}/utils/health
  static Future<ServerHealth> checkServerHealth() async {
    final uri = Uri.parse('https://${host}/utils/health');
    try {
      final response = await _healthController
          .checkBackendHealth(host: host)
          .timeout(const Duration(seconds: 5));
      logger.i(
        'Checking API health at $uri: status code ${response.statusCode}',
        context: {'statusCode': response.statusCode},
      );
      if (response.statusCode == 200) {
        return ServerHealth.healthy;
      } else if (response.statusCode == 503) {
        return ServerHealth.maintenance;
      } else {
        return ServerHealth.offline;
      }
    } on SocketException catch (e, stackTrace) {
      logger.w(
        'SocketException when checking API health: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return ServerHealth.offline;
    } on TimeoutException catch (e, stackTrace) {
      logger.w(
        'Timeout when checking API health: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return ServerHealth.offline;
    } catch (e, stackTrace) {
      logger.e(
        'Unexpected error checking API health: $e',
        error: e,
        stackTrace: stackTrace,
      );
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
    } on FlutterError catch (e, stackTrace) {
      logger.w(
        'Optional config asset $path is not available: ${e.message}',
        error: e,
        stackTrace: stackTrace,
      );
      return <String, dynamic>{};
    } on FormatException catch (e, stackTrace) {
      logger.e(
        'Invalid JSON in config asset $path',
        error: e,
        stackTrace: stackTrace,
      );
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
