import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/map/layers/map_marker_layout.dart';
import 'package:strnadi/map/layers/map_feature_marker.dart';
import 'map_feature_fixtures.dart';

void main() {
  MapCluster cluster(String id, {Map<String, double>? bounds}) =>
      MapCluster.fromJson(
        clusterJson()
          ..['id'] = id
          ..['bounds'] =
              bounds ??
              {'north': 50.1, 'south': 50.0, 'east': 14.1, 'west': 14.0},
      );
  testWidgets('markers stay at their coordinates without connector lines', (
    tester,
  ) async {
    final controller = MapController();
    final features = [cluster('a'), cluster('b')];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: FlutterMap(
          mapController: controller,
          options: const MapOptions(
            initialCenter: LatLng(50, 14),
            initialZoom: 12,
          ),
          children: [
            MapFeatureLayer(features: features, onTap: (f) => selected = f.id),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final markers = find.byType(MapFeatureMarker);
    expect(tester.getCenter(markers.at(0)), tester.getCenter(markers.at(1)));
    expect(find.byType(PolylineLayer), findsNothing);
    await tester.tap(markers.last);
    expect(selected, 'b');
    controller.move(const LatLng(50.001, 14.001), 13);
    await tester.pumpAndSettle();
    expect(tester.getCenter(markers.at(0)), tester.getCenter(markers.at(1)));
  });

  test(
    'wide clusters always zoom in and repeated taps are not blocked by id',
    () {
      final feature = cluster(
        'wide',
        bounds: {'north': 60, 'south': 40, 'east': 30, 'west': 0},
      );
      final target = clusterZoomTarget(feature, 12, const Size(390, 700))!;
      expect(target.zoom, 13);
      expect(
        clusterZoomTarget(feature, target.zoom, const Size(390, 700))!.zoom,
        14,
      );
    },
  );
  test('coincident and maximum zoom clusters open picker', () {
    expect(
      clusterZoomTarget(
        MapCluster.fromJson(clusterJson()),
        12,
        const Size(390, 700),
      ),
      isNull,
    );
    expect(clusterZoomTarget(cluster('a'), 19, const Size(390, 700)), isNull);
    expect(
      clusterZoomTarget(
        MapCluster.fromJson(recordingJson()),
        12,
        const Size(390, 700),
      ),
      isNull,
    );
  });
  test('dateline bounds zoom to the dateline and stay within zoom limits', () {
    final target = clusterZoomTarget(
      cluster(
        'date',
        bounds: {'north': 1, 'south': -1, 'east': -179, 'west': 179},
      ),
      18.5,
      const Size(390, 700),
    )!;
    expect(target.longitude.abs(), 180);
    expect(target.latitude, closeTo(0, 1e-8));
    expect(target.zoom, 19);
  });
}
