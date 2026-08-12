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

import 'package:latlong2/latlong.dart';

const Duration defaultCurrentLocationTimeout = Duration(seconds: 8);
const Duration defaultMaxLocationFallbackAge = Duration(seconds: 30);

typedef LocationClock = DateTime Function();

class CachedLocation {
  final LatLng location;
  final DateTime observedAt;

  const CachedLocation({
    required this.location,
    required this.observedAt,
  });
}

bool isValidLocation(LatLng? location) {
  if (location == null) return false;
  return location.latitude.isFinite &&
      location.longitude.isFinite &&
      location.latitude >= -90 &&
      location.latitude <= 90 &&
      location.longitude >= -180 &&
      location.longitude <= 180;
}

Future<LatLng> resolveBoundedCurrentLocation({
  required Future<LatLng> Function() request,
  CachedLocation? fallback,
  Duration timeout = defaultCurrentLocationTimeout,
  Duration maxFallbackAge = defaultMaxLocationFallbackAge,
  LocationClock clock = DateTime.now,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be greater than zero.');
  }
  if (maxFallbackAge <= Duration.zero) {
    throw ArgumentError.value(
      maxFallbackAge,
      'maxFallbackAge',
      'Must be greater than zero.',
    );
  }

  try {
    final LatLng candidate = await request().timeout(timeout);
    if (!isValidLocation(candidate)) {
      throw FormatException(
        'Location provider returned invalid coordinates: '
        '${candidate.latitude}, ${candidate.longitude}.',
      );
    }
    return candidate;
  } catch (error, stackTrace) {
    final LatLng? freshFallback = freshCachedLocation(
      fallback,
      now: clock(),
      maxAge: maxFallbackAge,
    );
    if (freshFallback != null) {
      return freshFallback;
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

LatLng? freshCachedLocation(
  CachedLocation? cached, {
  required DateTime now,
  Duration maxAge = defaultMaxLocationFallbackAge,
}) {
  if (cached == null || !isValidLocation(cached.location)) {
    return null;
  }
  if (maxAge <= Duration.zero) {
    throw ArgumentError.value(maxAge, 'maxAge', 'Must be greater than zero.');
  }

  final Duration age = now.difference(cached.observedAt);
  if (age.isNegative || age > maxAge) {
    return null;
  }
  return cached.location;
}
