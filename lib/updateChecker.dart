import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:version/version.dart';

String transformReleaseTag(String tag) {
  if (tag.contains('-')) {
    List<String> splitByDash = tag.split('-'); // e.g., [ 'alpha', '1.0.1+7' ]
    String preRelease = splitByDash[0];
    String versionPart = splitByDash[1];
    if (versionPart.contains('+')) {
      List<String> splitByPlus = versionPart.split('+'); // e.g., [ '1.0.1', '7' ]
      String version = splitByPlus[0];
      String build = splitByPlus[1];
      return "$version-$preRelease+$build";
    } else {
      return "$versionPart-$preRelease";
    }
  }
  return tag;
}

Future<void> checkForUpdate(BuildContext context) async {
  try {
    // Replace with your GitHub repository details
    final url = 'https://api.github.com/repos/Strnadi/Strnadi-Mobile-App/releases/latest';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // For example, the tag might be "alpha-1.0.1+7"
      final rawTag = data['tag_name'] as String;
      // Transform it into a semver compatible format: "1.0.1-alpha+7"
      final semverTag = transformReleaseTag(rawTag);

      // Parse the latest version
      final latestVersion = Version.parse(semverTag);

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      // Make sure your app version follows semver; e.g., "1.0.0"
      final currentVersion = Version.parse(packageInfo.version);

      // Compare versions
      if (latestVersion > currentVersion) {
        // Show update dialog
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Update Available'),
            content: Text('A new version (${latestVersion.toString()}) is available. Please update your app.'),
            actions: [
              TextButton(
                onPressed: () {
                  // Add logic to redirect to your app store or release page
                  Navigator.of(context).pop();
                },
                child: Text('Update'),
              ),
            ],
          ),
        );
      }
    } else {
      // Optionally log the error with Sentry
      print('Failed to fetch latest version info');
    }
  } catch (e) {
    // Optionally log the exception with Sentry
    print('Error checking for update: $e');
  }
}