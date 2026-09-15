import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads the existing grant without prompting or starting analytics services.
class TelemetryConsent {
  TelemetryConsent({
    Future<String?> Function()? readStoredStatus,
    Future<TrackingStatus> Function()? readTrackingStatus,
    bool? isIos,
    this.timeout = const Duration(seconds: 2),
  }) : _readStoredStatus = readStoredStatus ?? _readStored,
       _readTrackingStatus = readTrackingStatus ?? _readTracking,
       _isIos =
           isIos ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  static final TelemetryConsent instance = TelemetryConsent();
  static const storageKey = 'tracking_authorization_status';
  static const _storage = FlutterSecureStorage();

  final Future<String?> Function() _readStoredStatus;
  final Future<TrackingStatus> Function() _readTrackingStatus;
  final bool _isIos;
  final Duration timeout;

  static Future<String?> _readStored() => _storage.read(key: storageKey);
  static Future<TrackingStatus> _readTracking() =>
      AppTrackingTransparency.trackingAuthorizationStatus;

  Future<bool> isAuthorized() async {
    try {
      if (await _readStoredStatus().timeout(timeout) != 'authorized') {
        return false;
      }
      return !_isIos ||
          await _readTrackingStatus().timeout(timeout) ==
              TrackingStatus.authorized;
    } catch (_) {
      // A locked keychain or unavailable plugin must fail closed.
      return false;
    }
  }
}
