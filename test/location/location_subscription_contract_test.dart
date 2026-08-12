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
  test('LocationService has no process-lifetime cache subscription', () {
    final String source = File('lib/locationService.dart').readAsStringSync();

    expect(source, isNot(contains('_cacheSubscription')));
    expect(source, isNot(contains('void init()')));
    expect(source, isNot(contains('.asBroadcastStream()')));
    expect(source, contains('ActiveListenerStream<Position>'));
    expect(source, contains('_lastKnownPositionObservedAt = DateTime.now()'));
    expect(source, contains('CachedLocation('));
  });

  test('RecordingForm does not subscribe to device location', () {
    final String source =
        File('lib/PostRecordingForm/RecordingForm.dart').readAsStringSync();

    expect(source, isNot(contains('LocationService')));
    expect(source, isNot(contains('locationService.positionStream')));
    expect(source, isNot(contains('_positionSubscription')));
    expect(source, isNot(contains('_onNewPosition')));
  });

  test('recorder listener remains the owner of route location updates', () {
    final String source =
        File('lib/recording/streamRec.dart').readAsStringSync();

    expect(
      source,
      contains('_locationSub = _locService.positionStream.listen'),
    );
    expect(source, contains('await _locationSub?.cancel()'));
    expect(source, isNot(contains('_locService.init()')));
  });
}
