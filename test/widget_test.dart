/*
 * Copyright (C) 2024 Marian Pecqueur
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
/*
 * Copyright (C) 2024 [Your Name]
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
// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/passReset/newPassword.dart';

import 'package:strnadi/main.dart';

void main() {
  testWidgets('MyApp renders root MaterialApp without bootstrap side effects',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MyApp(
        homeOverride: SizedBox(key: Key('isolated-test-home')),
        enableLifecycleSideEffects: false,
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('isolated-test-home')), findsOneWidget);
  });

  testWidgets('password reset deep link reads token from query parameters',
      (WidgetTester tester) async {
    const String token =
        'eyJhbGciOiJub25lIn0.eyJzdWIiOiJiaXJkQGV4YW1wbGUudGVzdCJ9.signature';

    await tester.pumpWidget(
      const MyApp(
        homeOverride: SizedBox(key: Key('isolated-test-home')),
        enableLifecycleSideEffects: false,
      ),
    );
    await tester.pump();

    unawaited(
      navigatorKey.currentState!.pushNamed(
        '/ucet/obnova-hesla?token=$token',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ChangePassword page =
        tester.widget<ChangePassword>(find.byType(ChangePassword));
    expect(page.jwt, token);
  });
}
