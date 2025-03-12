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
import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/exceptions.dart';



class LocationService {

  Future<void> checkLocationWorking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Permission denied forever', false, await Geolocator.isLocationServiceEnabled(), null);
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('Permission denied', false, await Geolocator.isLocationServiceEnabled(), null);
    }
  }

  Future<bool> isLocationEnabled(){
    return Geolocator.isLocationServiceEnabled();
  }

  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  Stream<Position>? _positionStream;

  LatLng? lastKnownPosition;

  Stream<Position> get positionStream {
    // Create a broadcast stream so multiple listeners can attach.
    if (_positionStream == null) {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).asBroadcastStream();
    }
    return _positionStream!;
  }

  Future<LatLng> getCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    lastKnownPosition = LatLng(position.latitude, position.longitude);
    return lastKnownPosition!;
  }

  void init() {
    positionStream.listen((Position position) {
      lastKnownPosition = LatLng(position.latitude, position.longitude);
    });
  }
}
