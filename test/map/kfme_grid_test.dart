import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/map/kfme_grid.dart';

void main() {
  final bounds = LatLngBounds(
    const LatLng(49.91, 14.01),
    const LatLng(50.09, 14.32),
  );

  test('grid visibility and quarter zoom threshold', () {
    expect(buildKfmeGrid(bounds: bounds, zoom: 6.99), isEmpty);
    for (final zoom in [7.0, 10.99]) {
      final lines = buildKfmeGrid(bounds: bounds, zoom: zoom);
      expect(lines, isNotEmpty);
      expect(lines.every((line) => line.color == Colors.red), isTrue);
    }
    final coarse = buildKfmeGrid(bounds: bounds, zoom: 10);
    final fine = buildKfmeGrid(bounds: bounds, zoom: 11);
    expect(fine.where((line) => line.color == Colors.orange), hasLength(4));
    expect(
      fine.where((line) => line.color == Colors.red).map((line) => line.points),
      coarse.map((line) => line.points),
    );
    final vertical = fine
        .where(
          (line) => line.points.first.longitude == line.points.last.longitude,
        )
        .toList();
    expect(
      vertical[1].points.first.longitude - vertical[0].points.first.longitude,
      closeTo(5 / 60, 1e-10),
    );
    final horizontal = fine
        .where(
          (line) => line.points.first.latitude == line.points.last.latitude,
        )
        .toList();
    expect(
      horizontal[0].points.first.latitude - horizontal[1].points.first.latitude,
      closeTo(3 / 60, 1e-10),
    );
  });

  test('all endpoints stay in the viewport on either side of the origin', () {
    for (final area in [
      bounds,
      LatLngBounds(const LatLng(55.91, 5.51), const LatLng(56.19, 5.82)),
    ]) {
      for (final line in buildKfmeGrid(bounds: area, zoom: 13)) {
        expect(line.points.every(area.contains), isTrue);
      }
    }
  });

  testWidgets('quarter grid renders and disappears when zooming out', (
    tester,
  ) async {
    final controller = MapController();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('grid'),
          child: FlutterMap(
            mapController: controller,
            options: const MapOptions(
              initialCenter: LatLng(50, 14.16),
              initialZoom: 11,
            ),
            children: [
              Builder(
                builder: (context) {
                  final camera = MapCamera.of(context);
                  return PolylineLayer(
                    polylines: buildKfmeGrid(
                      bounds: camera.visibleBounds,
                      zoom: camera.zoom,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('grid')),
      matchesGoldenFile('goldens/kfme_quarters.png'),
    );
    controller.move(const LatLng(50, 14.16), 10);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .every((line) => line.color == Colors.red),
      isTrue,
    );
    controller.move(const LatLng(50, 14.16), 6);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
