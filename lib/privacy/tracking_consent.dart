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
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

class TrackingConsentManager {
  static const _storageKey = 'tracking_authorization_status';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static TrackingStatus? _cachedStatus;
  static bool _posthogInitialized = false;
  static PosthogObserver? _posthogObserver;

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
          _posthogInitialized = false;
        }
      }
    } catch (_) {
      // Ignore PostHog configuration errors – consent is enforced best-effort.
    }
  }

  static bool get isAuthorized => _cachedStatus == TrackingStatus.authorized;

  static bool get isTrackingEnabled =>
      !kIsWeb && _posthogInitialized && isAuthorized;

  static List<NavigatorObserver> get navigatorObservers {
    final observer = ensureObserver();
    return observer == null ? const <NavigatorObserver>[] : <NavigatorObserver>[observer];
  }

  static NavigatorObserver? ensureObserver() {
    if (!isTrackingEnabled) {
      return null;
    }
    return _posthogObserver ??= PosthogObserver();
  }

  static Future<void> identifyUser(String userId,
      {Map<String, Object>? userProperties}) async {
    if (!isTrackingEnabled) return;
    try {
      await Posthog().identify(
        userId: userId,
        userProperties: userProperties,
      );
    } catch (_) {}
  }

  static Future<void> captureEvent(String eventName,
      {Map<String, Object>? properties}) async {
    if (!isTrackingEnabled) return;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
    } catch (_) {}
  }

  static Future<void> resetIdentity() async {
    if (!isTrackingEnabled) return;
    try {
      await Posthog().reset();
    } catch (_) {}
  }
}
