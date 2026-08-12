/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/guest_user_popup.dart';
import 'package:strnadi/widgets/GuestUserWarning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Localization.load('assets/lang/en.json');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'popupShown': true,
    });
  });

  Future<void> showPopup(
    WidgetTester tester, {
    required Future<bool> Function() recorderExitPolicy,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-popup'),
              onPressed: () {
                showGuestUserPopup(
                  context,
                  recorderExitPolicy: recorderExitPolicy,
                  loginPageBuilder: (_) => const Scaffold(
                    body: SizedBox(key: Key('login-destination')),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-popup')));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
  }

  Future<void> showGuestRules(
    WidgetTester tester, {
    required Future<bool> Function() recorderExitPolicy,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-rules'),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => GuestUserRules(
                    recorderExitPolicy: recorderExitPolicy,
                    loginPageBuilder: (_) => const Scaffold(
                      body: SizedBox(key: Key('login-destination')),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-rules')));
    await tester.pumpAndSettle();
    expect(find.byType(GuestUserRules), findsOneWidget);
  }

  testWidgets('cancelled recorder cleanup keeps guest and recorder routes',
      (tester) async {
    var policyInvocations = 0;
    await showPopup(
      tester,
      recorderExitPolicy: () async {
        policyInvocations++;
        return false;
      },
    );

    await tester.tap(
      find.text(t('bottomBar.errors.navigate_to_login')),
    );
    await tester.pumpAndSettle();

    expect(policyInvocations, 1);
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.byKey(const Key('login-destination')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('popupShown'), isTrue);
  });

  testWidgets('approved recorder cleanup allows login route replacement',
      (tester) async {
    var policyInvocations = 0;
    await showPopup(
      tester,
      recorderExitPolicy: () async {
        policyInvocations++;
        return true;
      },
    );

    await tester.tap(
      find.text(t('bottomBar.errors.navigate_to_login')),
    );
    await tester.pumpAndSettle();

    expect(policyInvocations, 1);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byKey(const Key('login-destination')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('popupShown'), isFalse);
  });

  testWidgets('guest rules login cannot bypass cancelled recorder cleanup',
      (tester) async {
    var policyInvocations = 0;
    await showGuestRules(
      tester,
      recorderExitPolicy: () async {
        policyInvocations++;
        return false;
      },
    );

    await tester.tap(find.text(t('widgets.guest_user_rules.login')));
    await tester.pumpAndSettle();

    expect(policyInvocations, 1);
    expect(find.byType(GuestUserRules), findsOneWidget);
    expect(find.byKey(const Key('login-destination')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('popupShown'), isTrue);
  });

  testWidgets('guest rules login proceeds after recorder cleanup',
      (tester) async {
    var policyInvocations = 0;
    await showGuestRules(
      tester,
      recorderExitPolicy: () async {
        policyInvocations++;
        return true;
      },
    );

    await tester.tap(find.text(t('widgets.guest_user_rules.login')));
    await tester.pumpAndSettle();

    expect(policyInvocations, 1);
    expect(find.byType(GuestUserRules), findsNothing);
    expect(find.byKey(const Key('login-destination')), findsOneWidget);
  });
}
