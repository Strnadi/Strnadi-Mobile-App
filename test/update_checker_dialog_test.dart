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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/updateChecker.dart';
import 'package:strnadi/update_checker_logic.dart';

void main() {
  setUpAll(() async {
    await Localization.load('assets/lang/en.json');
  });

  testWidgets('Android prompt uses generic copy and a mocked store launcher',
      (WidgetTester tester) async {
    final BuildContext context = await _pumpDialogHost(tester);
    final List<Uri> launched = <Uri>[];
    bool completed = false;
    final Uri storeUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.delta.strnadi',
    );

    final Future<void> dialog = showUpdateDialog(
      context,
      UpdatePrompt(storeUri: storeUri),
      launchStore: (Uri uri) async => launched.add(uri),
    ).then((_) => completed = true);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(
      find.text('A new version is available. Please update your app.'),
      findsOneWidget,
    );
    expect(completed, isFalse);
    expect(launched, isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Update'));
    await tester.pumpAndSettle();
    await dialog;

    expect(launched, <Uri>[storeUri]);
    expect(completed, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('iOS prompt includes the mocked semantic version label',
      (WidgetTester tester) async {
    final BuildContext context = await _pumpDialogHost(tester);

    final Future<void> dialog = showUpdateDialog(
      context,
      UpdatePrompt(
        storeUri: Uri.parse('https://apps.apple.com/app/id123'),
        versionLabel: '2.4.1',
      ),
      launchStore: (_) async {},
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A new version (2.4.1) is available. Please update your app.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Update'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets('a mocked launcher failure still closes the update dialog',
      (WidgetTester tester) async {
    final BuildContext context = await _pumpDialogHost(tester);

    final Future<void> dialog = showUpdateDialog(
      context,
      UpdatePrompt(
        storeUri: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.delta.strnadi',
        ),
      ),
      launchStore: (_) async => throw StateError('launcher unavailable'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Update'));
    await tester.pumpAndSettle();
    await dialog;

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('platform-services check cannot overlap an open update dialog',
      (WidgetTester tester) async {
    final BuildContext context = await _pumpDialogHost(tester);
    final Completer<void> launcherFinished = Completer<void>();
    final List<String> events = <String>[];

    final Future<void> checks = runUpdateChecksWhileMounted(
      isMounted: () => context.mounted,
      checkForUpdate: () {
        events.add('update-start');
        return showUpdateDialog(
          context,
          UpdatePrompt(
            storeUri: Uri.parse(
              'https://play.google.com/store/apps/details'
              '?id=com.delta.strnadi',
            ),
          ),
          launchStore: (_) {
            events.add('launch-start');
            return launcherFinished.future;
          },
        ).then((_) => events.add('dialog-dismissed'));
      },
      checkPlatformServices: () async => events.add('services'),
    );

    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(events, <String>['update-start']);

    await tester.tap(find.widgetWithText(TextButton, 'Update'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(events, <String>['update-start', 'launch-start']);

    launcherFinished.complete();
    await tester.pumpAndSettle();
    await checks;

    expect(
      events,
      <String>[
        'update-start',
        'launch-start',
        'dialog-dismissed',
        'services',
      ],
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dismissing the update prompt with Back completes its future',
      (WidgetTester tester) async {
    final BuildContext context = await _pumpDialogHost(tester);
    int launches = 0;

    final Future<void> dialog = showUpdateDialog(
      context,
      UpdatePrompt(
        storeUri: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.delta.strnadi',
        ),
      ),
      launchStore: (_) async {
        launches++;
      },
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await dialog;

    expect(launches, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
}

Future<BuildContext> _pumpDialogHost(WidgetTester tester) async {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('host')),
    ),
  );
  await tester.pump();
  return navigatorKey.currentContext!;
}
