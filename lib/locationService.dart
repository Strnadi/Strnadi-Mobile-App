/*
 * location_service.dart
 * A singleton service that provides a broadcast stream for location updates.
 */
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() => _instance;

  LocationService._internal();

  Stream<Position>? _positionStream;

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
}
