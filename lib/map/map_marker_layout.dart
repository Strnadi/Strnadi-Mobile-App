import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'map_clusters.dart';
import 'map_feature_marker.dart';

/// Render server features at their geographic coordinates.
class MapFeatureLayer extends StatelessWidget {
  const MapFeatureLayer({
    super.key,
    required this.features,
    required this.onTap,
  });
  final List<MapCluster> features;
  final ValueChanged<MapCluster> onTap;

  @override
  Widget build(BuildContext context) => MarkerLayer(
    markers: [
      for (final feature in features)
        Marker(
          key: ValueKey(feature.id),
          point: feature.center,
          width: MapFeatureMarker.extent(feature),
          height: MapFeatureMarker.extent(feature),
          child: MapFeatureMarker(
            feature: feature,
            onTap: () => onTap(feature),
          ),
        ),
    ],
  );
}

/// Null means the cluster is already detailed enough to show its recordings.
({double zoom, double latitude, double longitude})? clusterZoomTarget(
  MapCluster feature,
  double currentZoom,
  Size size,
) {
  final bounds = feature.bounds;
  if (feature.isRecording ||
      bounds == null ||
      bounds.coincident ||
      currentZoom >= 19) {
    return null;
  }
  double mercatorY(double lat) {
    final sin = math.sin(lat.clamp(-85.05112878, 85.05112878) * math.pi / 180);
    return .5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi);
  }

  final fit = math.min(
    math.log(
          math.max(size.width - 96, 1) /
              (256 * math.max(bounds.longitudeSpan / 360, 1e-10)),
        ) /
        math.ln2,
    math.log(
          math.max(size.height - 96, 1) /
              (256 *
                  math.max(
                    (mercatorY(bounds.north) - mercatorY(bounds.south)).abs(),
                    1e-10,
                  )),
        ) /
        math.ln2,
  );
  // A wide cluster still needs a zoom step, even if fitting its bounds would
  // keep the current zoom (or zoom out).
  final zoom = math.max(currentZoom + 1, fit).clamp(1.0, 19.0).toDouble();
  final y = (mercatorY(bounds.north) + mercatorY(bounds.south)) / 2;
  final n = math.pi * (1 - 2 * y);
  return (
    zoom: zoom,
    latitude: math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi,
    longitude: ((bounds.west + bounds.longitudeSpan / 2 + 180) % 360) - 180,
  );
}
