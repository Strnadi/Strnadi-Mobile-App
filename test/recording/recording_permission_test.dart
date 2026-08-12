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
import 'package:geolocator/geolocator.dart';
import 'package:strnadi/recording/recording_permission.dart';

void main() {
  test('recording accepts only usable foreground location permissions', () {
    expect(
      isUsableRecordingLocationPermission(LocationPermission.whileInUse),
      isTrue,
    );
    expect(
      isUsableRecordingLocationPermission(LocationPermission.always),
      isTrue,
    );

    for (final LocationPermission denied in <LocationPermission>[
      LocationPermission.denied,
      LocationPermission.deniedForever,
      LocationPermission.unableToDetermine,
    ]) {
      expect(
        isUsableRecordingLocationPermission(denied),
        isFalse,
        reason: '$denied must not start a recording',
      );
    }
  });

  test('permission request fails once instead of looping on denied forever',
      () {
    final String source =
        File('lib/recording/streamRec.dart').readAsStringSync();
    final int start = source.indexOf('Future<bool> getLocationPermission');
    final int stateClass = source.indexOf('class _LiveRecState', start);
    final String permissionFlow = source.substring(start, stateClass);

    expect(start, greaterThanOrEqualTo(0));
    expect(stateClass, greaterThan(start));
    expect(permissionFlow, isNot(contains('while (')));
    expect(
      permissionFlow,
      contains('return false;'),
    );
  });
}
