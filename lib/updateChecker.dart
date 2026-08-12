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

import 'dart:io';

import 'package:strnadi/api/http_adapter.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/update_checker_logic.dart';
import 'package:url_launcher/url_launcher.dart';

const MethodChannel _androidUpdateChannel =
    MethodChannel('com.delta.strnadi/app_update');

typedef StoreUriLauncher = Future<void> Function(Uri storeUri);

Future<void> checkForUpdate(BuildContext context) async {
  try {
    await runPlatformUpdateCheck(
      platform: Platform.isIOS
          ? UpdateTargetPlatform.ios
          : Platform.isAndroid
              ? UpdateTargetPlatform.android
              : UpdateTargetPlatform.unsupported,
      isMounted: () => context.mounted,
      loadInstalledApp: () async {
        final PackageInfo packageInfo = await PackageInfo.fromPlatform();
        return InstalledAppVersion(
          bundleId: packageInfo.packageName,
          version: packageInfo.version,
          buildNumber: packageInfo.buildNumber,
        );
      },
      lookupAppleRelease: _lookupAppleRelease,
      lookupAndroidUpdate: () =>
          _androidUpdateChannel.invokeMethod<Object?>('checkForUpdate'),
      presentUpdate: (UpdatePrompt prompt) async {
        if (!context.mounted) return;
        await showUpdateDialog(context, prompt);
      },
    );
  } catch (e) {
    debugPrint('Error checking for update: $e');
  }
}

Future<UpdateRelease?> _lookupAppleRelease(String bundleId) async {
  final Uri lookupUri = Uri.https(
    'itunes.apple.com',
    '/lookup',
    <String, String>{'bundleId': bundleId},
  );
  final response = await http.get(lookupUri);
  if (response.statusCode != 200) {
    debugPrint('Failed to fetch version info from Apple App Store.');
    return null;
  }

  final UpdateRelease? release = parseITunesLookupRelease(response.body);
  if (release == null) {
    debugPrint('No valid release found from iTunes lookup.');
  }
  return release;
}

Future<void> showUpdateDialog(
  BuildContext context,
  UpdatePrompt prompt, {
  StoreUriLauncher? launchStore,
}) async {
  final String message = prompt.versionLabel == null
      ? t('updates.available.messageWithoutVersion')
      : t('updates.available.message')
          .replaceFirst('{version}', prompt.versionLabel!);

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(t('updates.available.title')),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await (launchStore ?? _launchStoreUri)(prompt.storeUri);
            } catch (error) {
              debugPrint('Could not launch ${prompt.storeUri}: $error');
            }

            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
          },
          child: Text(t('updates.available.action')),
        ),
      ],
    ),
  );
}

Future<void> _launchStoreUri(Uri storeUri) async {
  if (await canLaunchUrl(storeUri)) {
    await launchUrl(storeUri, mode: LaunchMode.externalApplication);
  } else {
    debugPrint('Could not launch $storeUri');
  }
}
