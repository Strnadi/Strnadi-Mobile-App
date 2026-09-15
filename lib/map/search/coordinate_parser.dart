import 'package:latlong2/latlong.dart';

/// Determines if a prompt contains coordinates and extracts them
/// Returns a LatLng object if valid coordinates are found, null otherwise
LatLng? parseCoordinatesFromPrompt(String prompt) {
  if (prompt.isEmpty) return null;

  final normalized = prompt.trim();

  final directionalLatLon = RegExp(
    r'^([NS])?\s*(-?\d+(?:[.,]\d+)?)\s*([NS])?\s*[,;\s]+\s*([EW])?\s*(-?\d+(?:[.,]\d+)?)\s*([EW])?$',
    caseSensitive: false,
  );
  final directionalLonLat = RegExp(
    r'^([EW])?\s*(-?\d+(?:[.,]\d+)?)\s*([EW])?\s*[,;\s]+\s*([NS])?\s*(-?\d+(?:[.,]\d+)?)\s*([NS])?$',
    caseSensitive: false,
  );

  final latLonMatch = directionalLatLon.firstMatch(normalized);
  if (latLonMatch != null) {
    final lat = _parseCoordinateWithDirection(
      number: latLonMatch.group(2),
      prefixDirection: latLonMatch.group(1),
      suffixDirection: latLonMatch.group(3),
      positiveDirection: 'N',
      negativeDirection: 'S',
    );
    final lng = _parseCoordinateWithDirection(
      number: latLonMatch.group(5),
      prefixDirection: latLonMatch.group(4),
      suffixDirection: latLonMatch.group(6),
      positiveDirection: 'E',
      negativeDirection: 'W',
    );

    if (lat != null &&
        lng != null &&
        _isValidLatitude(lat) &&
        _isValidLongitude(lng)) {
      return LatLng(lat, lng);
    }
  }

  final lonLatMatch = directionalLonLat.firstMatch(normalized);
  if (lonLatMatch != null) {
    final lng = _parseCoordinateWithDirection(
      number: lonLatMatch.group(2),
      prefixDirection: lonLatMatch.group(1),
      suffixDirection: lonLatMatch.group(3),
      positiveDirection: 'E',
      negativeDirection: 'W',
    );
    final lat = _parseCoordinateWithDirection(
      number: lonLatMatch.group(5),
      prefixDirection: lonLatMatch.group(4),
      suffixDirection: lonLatMatch.group(6),
      positiveDirection: 'N',
      negativeDirection: 'S',
    );

    if (lat != null &&
        lng != null &&
        _isValidLatitude(lat) &&
        _isValidLongitude(lng)) {
      return LatLng(lat, lng);
    }
  }

  final decimalWithSeparator = RegExp(
    r'^(-?\d+(?:[.,]\d+)?)\s*[,;]\s*(-?\d+(?:[.,]\d+)?)$',
  );
  final decimalSeparatedBySpace = RegExp(
    r'^(-?\d+(?:[.,]\d+)?)\s+(-?\d+(?:[.,]\d+)?)$',
  );

  final decimalMatch =
      decimalWithSeparator.firstMatch(normalized) ??
      decimalSeparatedBySpace.firstMatch(normalized);
  if (decimalMatch != null) {
    final lat = _parseDecimalCoordinate(decimalMatch.group(1));
    final lng = _parseDecimalCoordinate(decimalMatch.group(2));
    if (lat != null &&
        lng != null &&
        _isValidLatitude(lat) &&
        _isValidLongitude(lng)) {
      return LatLng(lat, lng);
    }
  }

  return null;
}

double? _parseDecimalCoordinate(String? value) {
  if (value == null) return null;
  return double.tryParse(value.replaceAll(',', '.'));
}

double? _parseCoordinateWithDirection({
  required String? number,
  required String? prefixDirection,
  required String? suffixDirection,
  required String positiveDirection,
  required String negativeDirection,
}) {
  final base = _parseDecimalCoordinate(number);
  if (base == null) return null;

  final prefix = prefixDirection?.toUpperCase();
  final suffix = suffixDirection?.toUpperCase();
  if (prefix != null &&
      suffix != null &&
      prefix.isNotEmpty &&
      suffix.isNotEmpty &&
      prefix != suffix) {
    return null;
  }

  final direction = (prefix != null && prefix.isNotEmpty)
      ? prefix
      : ((suffix != null && suffix.isNotEmpty) ? suffix : null);
  if (direction == null) return base;
  if (direction == positiveDirection) return base.abs();
  if (direction == negativeDirection) return -base.abs();
  return null;
}

/// Helper: Validate latitude range (-90 to 90)
bool _isValidLatitude(double lat) => lat >= -90 && lat <= 90;

/// Helper: Validate longitude range (-180 to 180)
bool _isValidLongitude(double lng) => lng >= -180 && lng <= 180;

/// Simple check if a prompt looks like it might contain coordinates
bool looksLikeCoordinates(String prompt) {
  return parseCoordinatesFromPrompt(prompt) != null;
}
