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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/navigation/guide_shortcut_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Localization.load('assets/lang/en.json');
  });

  testWidgets('cancelled recorder exit keeps the guide closed', (tester) async {
    var policyCalls = 0;
    await tester.pumpWidget(
      _GuideHost(
        policy: () async {
          policyCalls += 1;
          return false;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(policyCalls, 1);
    expect(find.byKey(const Key('fake-guide')), findsNothing);
  });

  testWidgets('approved recorder exit opens the injected guide',
      (tester) async {
    var policyCalls = 0;
    await tester.pumpWidget(
      _GuideHost(
        policy: () async {
          policyCalls += 1;
          return true;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();

    expect(policyCalls, 1);
    expect(find.byKey(const Key('fake-guide')), findsOneWidget);
  });
}

class _GuideHost extends StatelessWidget {
  final Future<bool> Function() policy;

  const _GuideHost({required this.policy});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          leading: GuideShortcutButton(
            recorderExitPolicy: policy,
            guidePageBuilder: (_) => const Scaffold(
              body: SizedBox(key: Key('fake-guide')),
            ),
          ),
        ),
      ),
    );
  }
}
