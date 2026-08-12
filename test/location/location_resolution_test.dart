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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/location/location_resolution.dart';

final DateTime _now = DateTime.utc(2026, 7, 18, 12);

void main() {
  test('returns a valid current location', () async {
    final LatLng result = await resolveBoundedCurrentLocation(
      request: () async => const LatLng(50.08, 14.43),
      fallback: _fresh(const LatLng(1, 2)),
      clock: () => _now,
    );

    expect(result, const LatLng(50.08, 14.43));
  });

  test('timeout is bounded and uses a validated fallback', () async {
    final Completer<LatLng> hangingRequest = Completer<LatLng>();

    final LatLng result = await resolveBoundedCurrentLocation(
      request: () => hangingRequest.future,
      fallback: _fresh(const LatLng(49.2, 16.6)),
      timeout: const Duration(milliseconds: 10),
      clock: () => _now,
    );

    expect(result, const LatLng(49.2, 16.6));
  });

  test('provider failure uses a valid fallback', () async {
    final LatLng result = await resolveBoundedCurrentLocation(
      request: () async => throw StateError('provider unavailable'),
      fallback: _fresh(const LatLng(-33.8, 151.2)),
      clock: () => _now,
    );

    expect(result, const LatLng(-33.8, 151.2));
  });

  test('invalid provider output uses a valid fallback', () async {
    final LatLng result = await resolveBoundedCurrentLocation(
      request: () async => const LatLng(double.nan, 14),
      fallback: _fresh(const LatLng(50, 14)),
      clock: () => _now,
    );

    expect(result, const LatLng(50, 14));
  });

  test('invalid fallback never masks a timeout', () async {
    await expectLater(
      resolveBoundedCurrentLocation(
        request: () => Completer<LatLng>().future,
        fallback: _fresh(const LatLng(100, 14)),
        timeout: const Duration(milliseconds: 10),
        clock: () => _now,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('invalid provider and fallback coordinates fail closed', () async {
    await expectLater(
      resolveBoundedCurrentLocation(
        request: () async => const LatLng(50, 181),
        fallback: _fresh(const LatLng(-91, 14)),
        clock: () => _now,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a non-positive timeout before starting the provider', () async {
    var invoked = false;

    await expectLater(
      resolveBoundedCurrentLocation(
        request: () async {
          invoked = true;
          return const LatLng(50, 14);
        },
        timeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(invoked, isFalse);
  });

  test('stale fallback never masks a current-location timeout', () async {
    await expectLater(
      resolveBoundedCurrentLocation(
        request: () => Completer<LatLng>().future,
        fallback: CachedLocation(
          location: const LatLng(50, 14),
          observedAt:
              _now.subtract(defaultMaxLocationFallbackAge + Duration.zero),
        ),
        timeout: const Duration(milliseconds: 10),
        maxFallbackAge: const Duration(seconds: 29),
        clock: () => _now,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('future-dated fallback fails closed after a clock change', () async {
    await expectLater(
      resolveBoundedCurrentLocation(
        request: () async => throw StateError('provider unavailable'),
        fallback: CachedLocation(
          location: const LatLng(50, 14),
          observedAt: _now.add(const Duration(seconds: 1)),
        ),
        clock: () => _now,
      ),
      throwsStateError,
    );
  });

  test('fallback at the maximum age boundary remains usable', () async {
    final LatLng result = await resolveBoundedCurrentLocation(
      request: () async => throw StateError('provider unavailable'),
      fallback: CachedLocation(
        location: const LatLng(50, 14),
        observedAt: _now.subtract(defaultMaxLocationFallbackAge),
      ),
      clock: () => _now,
    );

    expect(result, const LatLng(50, 14));
  });

  test('rejects a non-positive fallback age bound', () async {
    await expectLater(
      resolveBoundedCurrentLocation(
        request: () async => const LatLng(50, 14),
        maxFallbackAge: Duration.zero,
      ),
      throwsArgumentError,
    );
  });

  test('coordinate validation covers finite geographic bounds', () {
    expect(isValidLocation(const LatLng(-90, -180)), isTrue);
    expect(isValidLocation(const LatLng(90, 180)), isTrue);
    expect(isValidLocation(const LatLng(90.1, 0)), isFalse);
    expect(isValidLocation(const LatLng(0, -180.1)), isFalse);
    expect(isValidLocation(const LatLng(double.infinity, 0)), isFalse);
    expect(isValidLocation(null), isFalse);
  });
}

CachedLocation _fresh(LatLng location) {
  return CachedLocation(location: location, observedAt: _now);
}
