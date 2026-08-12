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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/update_checker_logic.dart';
import 'package:version/version.dart';

void main() {
  group('iTunes lookup parsing', () {
    test('uses the response trackViewUrl for the iOS update action', () {
      const String trackViewUrl =
          'https://apps.apple.com/cz/app/strnadi/id123456789?mt=8';
      final String response = jsonEncode(<String, Object>{
        'resultCount': 1,
        'results': <Object>[
          <String, Object>{
            'version': '2.4.1',
            'trackViewUrl': trackViewUrl,
          },
        ],
      });

      final UpdateRelease? release = parseITunesLookupRelease(response);

      expect(release, isNotNull);
      expect(release!.version.toString(), '2.4.1');
      expect(release.storeUri, Uri.parse(trackViewUrl));
      expect(release.storeUri.host, 'apps.apple.com');
      expect(release.storeUri.host, isNot('play.google.com'));
    });

    test('accepts the legacy HTTPS iTunes trackViewUrl host', () {
      const String trackViewUrl =
          'https://itunes.apple.com/cz/app/strnadi/id123456789';
      final String response = jsonEncode(<String, Object>{
        'resultCount': 1,
        'results': <Object>[
          <String, Object>{
            'version': '1.8.0',
            'trackViewUrl': trackViewUrl,
          },
        ],
      });

      final UpdateRelease? release = parseITunesLookupRelease(response);

      expect(release?.storeUri, Uri.parse(trackViewUrl));
    });

    test('skips malformed entries and uses a later valid result', () {
      final String response = jsonEncode(<String, Object>{
        'resultCount': 2,
        'results': <Object>[
          <String, Object>{'version': '2.0.0'},
          <String, Object>{
            'version': '2.1.0',
            'trackViewUrl': 'https://apps.apple.com/app/id123456789',
          },
        ],
      });

      final UpdateRelease? release = parseITunesLookupRelease(response);

      expect(release?.version.toString(), '2.1.0');
      expect(release?.storeUri.host, 'apps.apple.com');
    });

    test('skips an invalid version and uses a later valid result', () {
      final String response = jsonEncode(<String, Object>{
        'resultCount': 2,
        'results': <Object>[
          <String, Object>{
            'version': 'not-a-version',
            'trackViewUrl': 'https://apps.apple.com/app/id111111111',
          },
          <String, Object>{
            'version': '2.2.0',
            'trackViewUrl': 'https://apps.apple.com/app/id123456789',
          },
        ],
      });

      final UpdateRelease? release = parseITunesLookupRelease(response);

      expect(release?.version.toString(), '2.2.0');
      expect(release?.storeUri.path, '/app/id123456789');
    });

    for (final ({String name, String response}) scenario
        in <({String name, String response})>[
      (name: 'invalid JSON', response: '{'),
      (
        name: 'non-object JSON',
        response: jsonEncode(<Object>[]),
      ),
      (
        name: 'zero results',
        response: jsonEncode(<String, Object>{
          'resultCount': 0,
          'results': <Object>[],
        }),
      ),
      (
        name: 'missing results',
        response: jsonEncode(<String, Object>{'resultCount': 1}),
      ),
      (
        name: 'missing trackViewUrl',
        response: jsonEncode(<String, Object>{
          'resultCount': 1,
          'results': <Object>[
            <String, Object>{'version': '2.0.0'},
          ],
        }),
      ),
      (
        name: 'invalid version',
        response: jsonEncode(<String, Object>{
          'resultCount': 1,
          'results': <Object>[
            <String, Object>{
              'version': 'not-a-version',
              'trackViewUrl': 'https://apps.apple.com/app/id123456789',
            },
          ],
        }),
      ),
      (
        name: 'non-HTTPS URL',
        response: jsonEncode(<String, Object>{
          'resultCount': 1,
          'results': <Object>[
            <String, Object>{
              'version': '2.0.0',
              'trackViewUrl': 'http://apps.apple.com/app/id123456789',
            },
          ],
        }),
      ),
      (
        name: 'non-Apple URL',
        response: jsonEncode(<String, Object>{
          'resultCount': 1,
          'results': <Object>[
            <String, Object>{
              'version': '2.0.0',
              'trackViewUrl':
                  'https://play.google.com/store/apps/details?id=strnadi',
            },
          ],
        }),
      ),
      (
        name: 'lookalike Apple hostname',
        response: jsonEncode(<String, Object>{
          'resultCount': 1,
          'results': <Object>[
            <String, Object>{
              'version': '2.0.0',
              'trackViewUrl': 'https://apps.apple.com.example.test/app/1',
            },
          ],
        }),
      ),
    ]) {
      test('rejects ${scenario.name}', () {
        expect(parseITunesLookupRelease(scenario.response), isNull);
      });
    }
  });

  group('Google Play Core update result', () {
    test('resolves an eligible higher version code to the app Play URL', () {
      final UpdatePrompt? prompt = resolveAndroidUpdatePrompt(
        platformResult: <String, Object>{
          'availability': googlePlayUpdateAvailable,
          'availableVersionCode': 171,
        },
        bundleId: 'com.delta.strnadi',
        installedBuildNumber: '170',
      );

      expect(prompt, isNotNull);
      expect(prompt!.versionLabel, isNull);
      expect(prompt.storeUri.scheme, 'https');
      expect(prompt.storeUri.host, 'play.google.com');
      expect(prompt.storeUri.path, '/store/apps/details');
      expect(prompt.storeUri.queryParameters['id'], 'com.delta.strnadi');
    });

    test('ignores the arbitrary version code when Play reports no update', () {
      expect(
        resolveAndroidUpdatePrompt(
          platformResult: <String, Object>{
            'availability': 1,
            'availableVersionCode': 999999,
          },
          bundleId: 'com.delta.strnadi',
          installedBuildNumber: '170',
        ),
        isNull,
      );
    });

    test('does not treat an in-progress status as a fresh update prompt', () {
      expect(
        resolveAndroidUpdatePrompt(
          platformResult: <String, Object>{
            'availability': 3,
            'availableVersionCode': 171,
          },
          bundleId: 'com.delta.strnadi',
          installedBuildNumber: '170',
        ),
        isNull,
      );
    });

    test('requires the available version code to exceed the installed code',
        () {
      for (final int candidate in <int>[169, 170]) {
        expect(
          resolveAndroidUpdatePrompt(
            platformResult: <String, Object>{
              'availability': googlePlayUpdateAvailable,
              'availableVersionCode': candidate,
            },
            bundleId: 'com.delta.strnadi',
            installedBuildNumber: '170',
          ),
          isNull,
        );
      }
    });

    test('fails closed for malformed or missing version codes', () {
      for (final Object? candidate in <Object?>[
        null,
        0,
        -1,
        '171',
        171.5,
      ]) {
        expect(
          resolveAndroidUpdatePrompt(
            platformResult: <String, Object?>{
              'availability': googlePlayUpdateAvailable,
              'availableVersionCode': candidate,
            },
            bundleId: 'com.delta.strnadi',
            installedBuildNumber: '170',
          ),
          isNull,
          reason: 'candidate $candidate must not produce a prompt',
        );
      }
    });

    test('fails closed for an invalid installed Android build number', () {
      for (final String installed in <String>['', '1.7.0', '0', '-1']) {
        expect(
          resolveAndroidUpdatePrompt(
            platformResult: <String, Object>{
              'availability': googlePlayUpdateAvailable,
              'availableVersionCode': 171,
            },
            bundleId: 'com.delta.strnadi',
            installedBuildNumber: installed,
          ),
          isNull,
        );
      }
    });

    test('fails closed when the platform result has an unknown shape', () {
      for (final Object? result in <Object?>[
        null,
        true,
        <Object?>[],
        <String, Object>{},
        <String, Object>{'availability': 99},
        <String, Object>{'availability': '2', 'availableVersionCode': 171},
      ]) {
        expect(parseAndroidUpdateInfo(result), isNull);
      }
    });

    test('accepts an integral platform number but rejects a fraction', () {
      expect(
        parseAndroidUpdateInfo(
          <String, Object>{
            'availability': 2.0,
            'availableVersionCode': 171.0,
          },
        )?.availableVersionCode,
        171,
      );
      expect(
        parseAndroidUpdateInfo(
          <String, Object>{
            'availability': 2,
            'availableVersionCode': 171.1,
          },
        ),
        isNull,
      );
    });

    test('modern Play HTML is not parsed or trusted as version metadata', () {
      const String currentPlayMarkup = '''
        <html><script nonce="abc">
        AF_initDataCallback({key: 'ds:5', data: [null, null]});
        </script><body>Strnadi</body></html>
      ''';

      expect(parseAndroidUpdateInfo(currentPlayMarkup), isNull);
      expect(
        resolveAndroidUpdatePrompt(
          platformResult: currentPlayMarkup,
          bundleId: 'com.delta.strnadi',
          installedBuildNumber: '170',
        ),
        isNull,
      );
    });

    test('also rejects the obsolete Current Version HTML fixture', () {
      const String obsoleteMarkup =
          '<div>Current Version</div><span>3.2.1</span>';

      expect(parseAndroidUpdateInfo(obsoleteMarkup), isNull);
    });

    test('does not construct a store URL for an empty bundle id', () {
      expect(
        resolveAndroidUpdatePrompt(
          platformResult: <String, Object>{
            'availability': googlePlayUpdateAvailable,
            'availableVersionCode': 171,
          },
          bundleId: '  ',
          installedBuildNumber: '170',
        ),
        isNull,
      );
    });
  });

  group('platform update orchestration', () {
    const InstalledAppVersion installed = InstalledAppVersion(
      bundleId: 'com.delta.strnadi',
      version: '1.7.0',
      buildNumber: '170',
    );

    test('does no work for an unsupported platform', () async {
      final List<String> calls = <String>[];

      await runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.unsupported,
        isMounted: () => true,
        loadInstalledApp: () async {
          calls.add('package');
          return installed;
        },
        lookupAppleRelease: (_) async {
          calls.add('apple');
          return null;
        },
        lookupAndroidUpdate: () async {
          calls.add('play');
          return null;
        },
        presentUpdate: (_) async => calls.add('prompt'),
      );

      expect(calls, isEmpty);
    });

    test('Android uses only the mocked Play Core source', () async {
      final List<String> calls = <String>[];

      await runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.android,
        isMounted: () => true,
        loadInstalledApp: () async {
          calls.add('package');
          return installed;
        },
        lookupAppleRelease: (_) async {
          calls.add('apple-network');
          return null;
        },
        lookupAndroidUpdate: () async {
          calls.add('play-core');
          return <String, Object>{
            'availability': googlePlayUpdateAvailable,
            'availableVersionCode': 171,
          };
        },
        presentUpdate: (UpdatePrompt prompt) async {
          calls.add('prompt:${prompt.storeUri.host}');
        },
      );

      expect(
        calls,
        <String>['package', 'play-core', 'prompt:play.google.com'],
      );
    });

    test('does not prompt when the mocked Play source reports no update',
        () async {
      int prompts = 0;

      await runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.android,
        isMounted: () => true,
        loadInstalledApp: () async => installed,
        lookupAppleRelease: (_) async => null,
        lookupAndroidUpdate: () async => <String, Object>{
          'availability': 1,
          'availableVersionCode': 171,
        },
        presentUpdate: (_) async {
          prompts++;
        },
      );

      expect(prompts, 0);
    });

    test('awaits the update prompt until it is dismissed', () async {
      final Completer<void> promptDismissed = Completer<void>();
      bool checkCompleted = false;

      final Future<void> check = runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.android,
        isMounted: () => true,
        loadInstalledApp: () async => installed,
        lookupAppleRelease: (_) async => null,
        lookupAndroidUpdate: () async => <String, Object>{
          'availability': googlePlayUpdateAvailable,
          'availableVersionCode': 171,
        },
        presentUpdate: (_) => promptDismissed.future,
      ).then((_) => checkCompleted = true);

      await Future<void>.delayed(Duration.zero);
      expect(checkCompleted, isFalse);

      promptDismissed.complete();
      await check;
      expect(checkCompleted, isTrue);
    });

    test('stops if the widget unmounts while Play Core is pending', () async {
      final Completer<Object?> playResult = Completer<Object?>();
      bool mounted = true;
      int prompts = 0;

      final Future<void> check = runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.android,
        isMounted: () => mounted,
        loadInstalledApp: () async => installed,
        lookupAppleRelease: (_) async => null,
        lookupAndroidUpdate: () => playResult.future,
        presentUpdate: (_) async {
          prompts++;
        },
      );
      await Future<void>.delayed(Duration.zero);

      mounted = false;
      playResult.complete(<String, Object>{
        'availability': googlePlayUpdateAvailable,
        'availableVersionCode': 171,
      });
      await check;

      expect(prompts, 0);
    });

    test('iOS uses only the mocked Apple source and semantic version',
        () async {
      final List<String> calls = <String>[];

      await runPlatformUpdateCheck(
        platform: UpdateTargetPlatform.ios,
        isMounted: () => true,
        loadInstalledApp: () async => installed,
        lookupAppleRelease: (String bundleId) async {
          calls.add('apple:$bundleId');
          return UpdateRelease(
            version: Version.parse('1.10.0'),
            storeUri: Uri.parse('https://apps.apple.com/app/id123'),
          );
        },
        lookupAndroidUpdate: () async {
          calls.add('play-core');
          return null;
        },
        presentUpdate: (UpdatePrompt prompt) async {
          calls.add('prompt:${prompt.versionLabel}');
        },
      );

      expect(
        calls,
        <String>['apple:com.delta.strnadi', 'prompt:1.10.0'],
      );
    });

    test('propagates a mocked source failure to the production error boundary',
        () async {
      final StateError failure = StateError('Play API unavailable');

      await expectLater(
        runPlatformUpdateCheck(
          platform: UpdateTargetPlatform.android,
          isMounted: () => true,
          loadInstalledApp: () async => installed,
          lookupAppleRelease: (_) async => null,
          lookupAndroidUpdate: () async => throw failure,
          presentUpdate: (_) async {},
        ),
        throwsA(same(failure)),
      );
    });
  });

  group('mounted update-check sequencing', () {
    test('does not start either check when already unmounted', () async {
      final List<String> calls = <String>[];

      await runUpdateChecksWhileMounted(
        isMounted: () => false,
        checkForUpdate: () async => calls.add('update'),
        checkPlatformServices: () async => calls.add('services'),
      );

      expect(calls, isEmpty);
    });

    test('runs both checks in order while mounted', () async {
      final List<String> calls = <String>[];

      await runUpdateChecksWhileMounted(
        isMounted: () => true,
        checkForUpdate: () async => calls.add('update'),
        checkPlatformServices: () async => calls.add('services'),
      );

      expect(calls, <String>['update', 'services']);
    });

    test('does not call platform services after unmounting during update check',
        () async {
      final Completer<void> updateFinished = Completer<void>();
      final List<String> calls = <String>[];
      bool mounted = true;

      final Future<void> checks = runUpdateChecksWhileMounted(
        isMounted: () => mounted,
        checkForUpdate: () {
          calls.add('update');
          return updateFinished.future;
        },
        checkPlatformServices: () async => calls.add('services'),
      );
      await Future<void>.delayed(Duration.zero);

      mounted = false;
      updateFinished.complete();
      await checks;

      expect(calls, <String>['update']);
    });

    test('waits for update check before starting platform services', () async {
      final Completer<void> updateFinished = Completer<void>();
      final List<String> calls = <String>[];

      final Future<void> checks = runUpdateChecksWhileMounted(
        isMounted: () => true,
        checkForUpdate: () {
          calls.add('update-start');
          return updateFinished.future.then((_) => calls.add('update-end'));
        },
        checkPlatformServices: () async => calls.add('services'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['update-start']);

      updateFinished.complete();
      await checks;

      expect(calls, <String>['update-start', 'update-end', 'services']);
    });

    test('does not swallow an update-check failure or run the next check',
        () async {
      final List<String> calls = <String>[];
      final StateError failure = StateError('update failed');

      await expectLater(
        runUpdateChecksWhileMounted(
          isMounted: () => true,
          checkForUpdate: () async {
            calls.add('update');
            throw failure;
          },
          checkPlatformServices: () async => calls.add('services'),
        ),
        throwsA(same(failure)),
      );

      expect(calls, <String>['update']);
    });
  });

  test('production MyApp schedules update checks from its mounted root', () {
    final String source = File('lib/main.dart').readAsStringSync();
    final int appState = source.indexOf('class _MyAppState');
    final int homeScreen = source.indexOf('class HomeScreen', appState);
    final String rootState = source.substring(appState, homeScreen);

    expect(appState, greaterThanOrEqualTo(0));
    expect(homeScreen, greaterThan(appState));
    expect(
      rootState,
      contains('WidgetsBinding.instance.addPostFrameCallback'),
    );
    expect(rootState, contains('runUpdateChecksWhileMounted('));
    expect(rootState, contains('navigatorKey.currentContext'));
    expect(
      rootState,
      contains(
        'checkForUpdate: () => checkForUpdate(navigatorContext)',
      ),
    );
    expect(
      rootState,
      contains(
        '_checkGooglePlayServices(navigatorContext)',
      ),
    );
    expect(
      rootState,
      contains('isMounted: () => mounted && navigatorContext.mounted'),
    );
    expect(
      rootState.indexOf('if (!widget.enableLifecycleSideEffects) return;'),
      lessThan(rootState.indexOf('runUpdateChecksWhileMounted(')),
    );
  });

  test('Android production update lookup uses Play Core, never store HTML', () {
    final String dartSource = File('lib/updateChecker.dart').readAsStringSync();
    final String nativeSource = File(
      'android/app/src/main/java/com/example/strnadi/MainActivity.java',
    ).readAsStringSync();
    final String gradle = File('android/app/build.gradle').readAsStringSync();

    expect(dartSource, contains('com.delta.strnadi/app_update'));
    expect(dartSource, contains("invokeMethod<Object?>('checkForUpdate')"));
    expect(dartSource, isNot(contains("'play.google.com',\n        '/store")));
    expect(dartSource, isNot(contains('parseGooglePlayRelease')));
    expect(dartSource, isNot(contains('Current Version')));

    expect(nativeSource, contains('AppUpdateManagerFactory.create'));
    expect(nativeSource, contains('updateInfo.updateAvailability()'));
    expect(nativeSource, contains('updateInfo.availableVersionCode()'));
    expect(nativeSource, contains('"PLAY_UPDATE_CHECK_FAILED"'));
    expect(
      gradle,
      contains(
        "implementation 'com.google.android.play:app-update:2.1.0'",
      ),
    );
  });

  test('production update presentation awaits the actual dialog', () {
    final String source = File('lib/updateChecker.dart').readAsStringSync();

    expect(source, contains('await showUpdateDialog(context, prompt);'));
    expect(source, contains('await showDialog<void>('));
    expect(source, isNot(contains('\n      showDialog<void>(')));
  });
}
