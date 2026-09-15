import 'package:flutter_map/flutter_map.dart';

/// Uses Flutter Map's cancellation and cache support for public API tiles.
/// TileLayer disposes the provider and its internally owned HTTP client.
NetworkTileProvider createMapTileProvider() => NetworkTileProvider();
