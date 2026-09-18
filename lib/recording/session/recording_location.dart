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
part of 'recording_controller.dart';

extension _RecordingLocation on RecordingController {
  Future<void> _finishPartLocation(
    RecordingPartUnready part, {
    required String action,
  }) async {
    try {
      final loc = await _locService.getCurrentLocation();
      part.gpsLatitudeEnd = loc.latitude;
      part.gpsLongitudeEnd = loc.longitude;
    } catch (e, stackTrace) {
      logger.e(
        'Error fetching location on $action: $e',
        error: e,
        stackTrace: stackTrace,
      );
      part.gpsLatitudeEnd ??= part.gpsLatitudeStart;
      part.gpsLongitudeEnd ??= part.gpsLongitudeStart;
    }
  }

  Future<LatLng?> _resolveSegmentStartLocation({
    required String action,
    bool allowLastKnownFallback = true,
  }) async {
    try {
      final LatLng current = await _locService.getCurrentLocation(
        allowLastKnownFallback: allowLastKnownFallback,
      );
      if (isValidLocation(current)) {
        return current;
      }
      logger.w('Ignoring invalid location while $action.');
    } catch (e, stackTrace) {
      logger.e(
        'Error fetching location while $action: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }

    return null;
  }

  void _rememberSegmentStartLocation(LatLng location) {
    currentPosition = location;
    final bool isNewPoint =
        _liveRoute.isEmpty ||
        _liveRoute.last.latitude != location.latitude ||
        _liveRoute.last.longitude != location.longitude;
    if (isNewPoint) {
      _liveRoute.add(location);
    }
    _lastRouteUpdateTime = DateTime.now();
  }
}
