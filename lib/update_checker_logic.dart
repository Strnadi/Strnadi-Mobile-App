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

import 'package:version/version.dart';

enum UpdateTargetPlatform {
  android,
  ios,
  unsupported,
}

class InstalledAppVersion {
  const InstalledAppVersion({
    required this.bundleId,
    required this.version,
    required this.buildNumber,
  });

  final String bundleId;
  final String version;
  final String buildNumber;
}

class UpdateRelease {
  const UpdateRelease({
    required this.version,
    required this.storeUri,
  });

  final Version version;
  final Uri storeUri;

  bool isNewerThan(String currentVersion) {
    return version > Version.parse(currentVersion);
  }
}

class UpdatePrompt {
  const UpdatePrompt({
    required this.storeUri,
    this.versionLabel,
  });

  final Uri storeUri;
  final String? versionLabel;
}

class AndroidUpdateInfo {
  const AndroidUpdateInfo({
    required this.availability,
    required this.availableVersionCode,
  });

  /// Values are defined by Google Play Core's UpdateAvailability API.
  ///
  /// 0 = unknown, 1 = not available, 2 = available, and
  /// 3 = developer-triggered update in progress.
  final int availability;
  final int? availableVersionCode;
}

const int googlePlayUpdateAvailable = 2;

UpdateRelease? parseITunesLookupRelease(String responseBody) {
  try {
    final Object? decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>) return null;

    final Object? resultCount = decoded['resultCount'];
    if (resultCount is! num || resultCount <= 0) return null;

    final Object? results = decoded['results'];
    if (results is! List<Object?>) return null;

    for (final Object? candidate in results) {
      if (candidate is! Map<String, dynamic>) continue;

      final Object? versionValue = candidate['version'];
      final Object? trackViewUrlValue = candidate['trackViewUrl'];
      if (versionValue is! String || trackViewUrlValue is! String) continue;

      final Uri? storeUri = Uri.tryParse(trackViewUrlValue.trim());
      if (storeUri == null || !_isAppleStoreUri(storeUri)) continue;

      late final Version version;
      try {
        version = Version.parse(versionValue.trim());
      } on FormatException {
        continue;
      }

      return UpdateRelease(
        version: version,
        storeUri: storeUri,
      );
    }
  } on FormatException {
    return null;
  }

  return null;
}

AndroidUpdateInfo? parseAndroidUpdateInfo(Object? platformResult) {
  if (platformResult is! Map) return null;

  final int? availability = _strictInteger(platformResult['availability']);
  if (availability == null || availability < 0 || availability > 3) {
    return null;
  }

  final Object? rawVersionCode = platformResult['availableVersionCode'];
  final int? availableVersionCode =
      rawVersionCode == null ? null : _strictInteger(rawVersionCode);
  if (rawVersionCode != null && availableVersionCode == null) return null;

  return AndroidUpdateInfo(
    availability: availability,
    availableVersionCode: availableVersionCode,
  );
}

UpdatePrompt? resolveAndroidUpdatePrompt({
  required Object? platformResult,
  required String bundleId,
  required String installedBuildNumber,
}) {
  final AndroidUpdateInfo? updateInfo = parseAndroidUpdateInfo(platformResult);
  if (updateInfo == null ||
      updateInfo.availability != googlePlayUpdateAvailable) {
    return null;
  }

  final int? availableVersionCode = updateInfo.availableVersionCode;
  final int? installedVersionCode = int.tryParse(installedBuildNumber.trim());
  if (availableVersionCode == null ||
      availableVersionCode <= 0 ||
      installedVersionCode == null ||
      installedVersionCode <= 0 ||
      availableVersionCode <= installedVersionCode) {
    return null;
  }

  final String normalizedBundleId = bundleId.trim();
  if (normalizedBundleId.isEmpty) return null;

  return UpdatePrompt(
    storeUri: Uri.https(
      'play.google.com',
      '/store/apps/details',
      <String, String>{'id': normalizedBundleId},
    ),
  );
}

Future<void> runPlatformUpdateCheck({
  required UpdateTargetPlatform platform,
  required bool Function() isMounted,
  required Future<InstalledAppVersion> Function() loadInstalledApp,
  required Future<UpdateRelease?> Function(String bundleId) lookupAppleRelease,
  required Future<Object?> Function() lookupAndroidUpdate,
  required Future<void> Function(UpdatePrompt prompt) presentUpdate,
}) async {
  if (platform == UpdateTargetPlatform.unsupported || !isMounted()) return;

  final InstalledAppVersion installed = await loadInstalledApp();
  if (!isMounted()) return;

  late final UpdatePrompt? prompt;
  switch (platform) {
    case UpdateTargetPlatform.ios:
      final UpdateRelease? release =
          await lookupAppleRelease(installed.bundleId);
      if (!isMounted() || release == null) return;
      if (!release.isNewerThan(installed.version)) return;

      prompt = UpdatePrompt(
        storeUri: release.storeUri,
        versionLabel: release.version.toString(),
      );
      break;
    case UpdateTargetPlatform.android:
      final Object? platformResult = await lookupAndroidUpdate();
      if (!isMounted()) return;

      prompt = resolveAndroidUpdatePrompt(
        platformResult: platformResult,
        bundleId: installed.bundleId,
        installedBuildNumber: installed.buildNumber,
      );
      break;
    case UpdateTargetPlatform.unsupported:
      return;
  }

  if (prompt == null || !isMounted()) return;
  await presentUpdate(prompt);
}

Future<void> runUpdateChecksWhileMounted({
  required bool Function() isMounted,
  required Future<void> Function() checkForUpdate,
  required Future<void> Function() checkPlatformServices,
}) async {
  if (!isMounted()) return;

  await checkForUpdate();
  if (!isMounted()) return;

  await checkPlatformServices();
}

bool _isAppleStoreUri(Uri uri) {
  if (uri.scheme != 'https' || !uri.hasAuthority) return false;

  final String host = uri.host.toLowerCase();
  return host == 'apps.apple.com' ||
      host.endsWith('.apps.apple.com') ||
      host == 'itunes.apple.com' ||
      host.endsWith('.itunes.apple.com');
}

int? _strictInteger(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}
