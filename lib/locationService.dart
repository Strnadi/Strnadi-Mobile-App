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
/*
 * location_service.dart
 * A singleton service that provides a broadcast stream for location updates.
 */
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/location/active_listener_stream.dart';
import 'package:strnadi/location/location_resolution.dart';

class LocationService {
  Future<void> checkLocationWorking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Permission denied forever', false,
          await Geolocator.isLocationServiceEnabled(), null);
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('Permission denied', false,
          await Geolocator.isLocationServiceEnabled(), null);
    }
  }

  Future<bool> isLocationEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal() {
    _positions = ActiveListenerStream<Position>(
      sourceFactory: () => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ),
      onValue: (Position position) {
        final LatLng candidate = LatLng(position.latitude, position.longitude);
        if (isValidLocation(candidate)) {
          _rememberLocation(candidate);
        }
      },
    );
  }

  LatLng? lastKnownPosition;
  DateTime? _lastKnownPositionObservedAt;
  late final ActiveListenerStream<Position> _positions;

  Stream<Position> get positionStream => _positions.stream;

  Future<LatLng> getCurrentLocation({
    Duration timeout = defaultCurrentLocationTimeout,
    bool allowLastKnownFallback = true,
  }) async {
    final LatLng location = await resolveBoundedCurrentLocation(
      request: () async {
        final Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
          ),
        );
        final LatLng current = LatLng(position.latitude, position.longitude);
        if (isValidLocation(current)) {
          _rememberLocation(current);
        }
        return current;
      },
      fallback: allowLastKnownFallback &&
              lastKnownPosition != null &&
              _lastKnownPositionObservedAt != null
          ? CachedLocation(
              location: lastKnownPosition!,
              observedAt: _lastKnownPositionObservedAt!,
            )
          : null,
      timeout: timeout,
    );
    return location;
  }

  void _rememberLocation(LatLng location) {
    lastKnownPosition = location;
    _lastKnownPositionObservedAt = DateTime.now();
  }
}
