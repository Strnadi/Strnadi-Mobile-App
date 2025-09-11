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

import 'package:flutter/material.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:version/version.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> checkForUpdate(BuildContext context) async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final bundleId = packageInfo.packageName;
    Version latestVersion;

    if (Platform.isIOS) {
      // Use Apple App Store via iTunes Lookup API
      final url = 'https://itunes.apple.com/lookup?bundleId=$bundleId';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['resultCount'] > 0) {
          final latestVersionString = data['results'][0]['version'];
          latestVersion = Version.parse(latestVersionString);
        } else {
          print('No results found from iTunes lookup.');
          return;
        }
      } else {
        print('Failed to fetch version info from Apple App Store.');
        return;
      }
    } else if (Platform.isAndroid) {
      // Use Google Play Store by scraping the app page
      final url = 'https://play.google.com/store/apps/details?id=$bundleId&hl=en';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = response.body;
        // Extract the current version using RegExp. Note: The regex may need adjustment if Google Play's HTML structure changes.
        RegExp regExp = RegExp(r'Current Version[\s\S]*?<span[^>]*>([\d\.]+)</span>');
        final match = regExp.firstMatch(document);
        if (match != null) {
          final latestVersionString = match.group(1)!;
          latestVersion = Version.parse(latestVersionString);
        } else {
          print('Could not extract version info from Google Play.');
          return;
        }
      } else {
        print('Failed to fetch version info from Google Play Store.');
        return;
      }
    } else {
      // Fallback for unsupported platforms.
      print('Update check not supported on this platform.');
      return;
    }

    // Get current app version
    final currentVersion = Version.parse(packageInfo.version);

    // Compare versions
    if (latestVersion > currentVersion) {
      // Show update dialog
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t('Update Available')),
          content: Text(
            t('A new version ({version}) is available. Please update your app.')
                .replaceFirst('{version}', latestVersion.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                String redirectUrl;
                if (Platform.isIOS) {
                  // Replace 'YOUR_APP_ID' with your actual App Store ID
                  redirectUrl = 'https://play.google.com/store/apps/details?id=com.delta.strnadi';
                } else if (Platform.isAndroid) {
                  redirectUrl = 'https://play.google.com/store/apps/details?id=$bundleId';
                } else {
                  redirectUrl = 'https://strnadi.cz';
                }

                final Uri uri = Uri.parse(redirectUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  print('Could not launch $redirectUrl');
                }
                Navigator.of(context).pop();
              },
              child: Text(t('Update')),
            ),
          ],
        ),
      );
    }
  } catch (e) {
    print('Error checking for update: $e');
  }
}