import 'package:latlong2/latlong.dart';

class MapSearchResult {
  const MapSearchResult({required this.name, required this.latLng});

  final String name;
  final LatLng latLng;

  static MapSearchResult? fromJson(dynamic item) {
    if (item is! Map) return null;
    final name = item['display_name']?.toString();
    final latitude = double.tryParse(item['lat']?.toString() ?? '');
    final longitude = double.tryParse(item['lon']?.toString() ?? '');
    if (name == null ||
        name.isEmpty ||
        latitude == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude == null ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return MapSearchResult(name: name, latLng: LatLng(latitude, longitude));
  }
}
