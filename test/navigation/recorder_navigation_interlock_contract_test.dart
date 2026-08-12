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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guest List and User login exits receive the recorder policy', () {
    final source =
        File('lib/navigation/scaffold_with_bottom_bar.dart').readAsStringSync();

    expect(
      RegExp(r'showGuestUserPopup\(\s*context,\s*'
              r'recorderExitPolicy: changeConfirmation,')
          .allMatches(source)
          .length,
      2,
    );
  });

  test('guest notification login exit receives the recorder policy', () {
    final source =
        File('lib/navigation/notification_bell_button.dart').readAsStringSync();

    expect(
      source,
      contains('recorderExitPolicy: widget.recorderExitPolicy'),
    );
    expect(
      source,
      contains('recorderExitPolicy: recorderExitPolicy'),
    );
    expect(
      source,
      contains(
        'if (!await permitsRecorderExit(recorderExitPolicy)) return;',
      ),
    );
  });

  test('recorder supplies guest state and one policy to every shortcut', () {
    final source = File('lib/recording/streamRec.dart').readAsStringSync();

    expect(
      RegExp(r'NotificationBellButton\(\s*'
              r'isGuestUser: _isGuestUser,\s*'
              r'recorderExitPolicy: changeConfirmation,')
          .hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(r'GuideShortcutButton\(\s*'
              r'recorderExitPolicy: changeConfirmation,')
          .hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(r'GuestUserRules\(\s*'
              r'recorderExitPolicy: changeConfirmation,')
          .hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(r'ReusableBottomAppBar\(\s*'
              r'currentPage: BottomBarItem\.recorder,\s*'
              r'changeConfirmation: changeConfirmation,')
          .hasMatch(source),
      isTrue,
    );
  });

  test('offline map rejection happens before destructive recorder cleanup', () {
    final source =
        File('lib/navigation/scaffold_with_bottom_bar.dart').readAsStringSync();
    final int bottomBar = source.indexOf('class ReusableBottomAppBar');
    final int mapButton = source.indexOf('BottomBarItem.map', bottomBar);
    final int listButton = source.indexOf('BottomBarItem.list', mapButton + 1);
    final String mapNavigation = source.substring(mapButton, listButton);

    final int internetCheck =
        mapNavigation.indexOf('if (!await Config.hasBasicInternet)');
    final int recorderExit = mapNavigation.indexOf(
      'if (!await permitsRecorderExit(changeConfirmation)) return;',
    );

    expect(internetCheck, greaterThanOrEqualTo(0));
    expect(recorderExit, greaterThan(internetCheck));
  });

  test('selected recorder tab is a no-op before destructive cleanup', () {
    final source =
        File('lib/navigation/scaffold_with_bottom_bar.dart').readAsStringSync();
    final int bottomBar = source.indexOf('class ReusableBottomAppBar');
    final int recorderButton =
        source.indexOf('BottomBarItem.recorder', bottomBar);
    final int blogButton =
        source.indexOf('BottomBarItem.blog', recorderButton + 1);
    final String recorderNavigation =
        source.substring(recorderButton, blogButton);

    final int selectedGuard =
        recorderNavigation.indexOf('currentPage == BottomBarItem.recorder');
    final int recorderExit = recorderNavigation.indexOf(
      'if (!await permitsRecorderExit(changeConfirmation)) return;',
    );

    expect(selectedGuard, greaterThanOrEqualTo(0));
    expect(recorderExit, greaterThan(selectedGuard));
  });
}
