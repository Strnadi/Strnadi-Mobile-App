import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class TrackingConsentManager {
  static const _storageKey = 'tracking_authorization_status';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static TrackingStatus? _cachedStatus;
  static bool _posthogInitialized = false;

  static TrackingStatus? get status => _cachedStatus;

  static Future<bool> ensureTrackingConsent({bool requestIfNeeded = true}) async {
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (!isIos) {
      _cachedStatus = TrackingStatus.authorized;
      await _persistStatus(_cachedStatus!);
      await _applyPosthogPreference(authorized: true);
      return true;
    }

    try {
      _cachedStatus = await AppTrackingTransparency.trackingAuthorizationStatus;

      if (_cachedStatus == TrackingStatus.notDetermined && requestIfNeeded) {
        _cachedStatus =
            await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (_) {
      _cachedStatus = TrackingStatus.notDetermined;
    }

    _cachedStatus ??= TrackingStatus.notDetermined;

    await _persistStatus(_cachedStatus!);
    final authorized = _cachedStatus == TrackingStatus.authorized;
    await _applyPosthogPreference(authorized: authorized);
    return authorized;
  }

  static Future<void> _persistStatus(TrackingStatus status) async {
    try {
      await _storage.write(key: _storageKey, value: status.name);
    } catch (_) {
      // Best-effort persistence; ignore storage failures.
    }
  }

  static Future<void> _applyPosthogPreference({required bool authorized}) async {
    if (kIsWeb) {
      return;
    }

    try {
      if (authorized) {
        if (!_posthogInitialized) {
          final config = PostHogConfig(
            'phc_z9EJPD4Mx7tvxn4ERnub3lSPkMg51hMgmthaiqM3QDj',
          )
            ..host = 'https://eu.i.posthog.com'
            ..captureApplicationLifecycleEvents = true
            ..optOut = false
            ..debug = kDebugMode;
          await Posthog().setup(config);
          _posthogInitialized = true;
        } else {
          await Posthog().enable();
        }
      } else {
        if (_posthogInitialized) {
          await Posthog().disable();
          await Posthog().reset();
        }
      }
    } catch (_) {
      // Ignore PostHog configuration errors – consent is enforced best-effort.
    }
  }

  static bool get isAuthorized => _cachedStatus == TrackingStatus.authorized;
}
