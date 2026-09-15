import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/api/controllers/map_search_controller.dart';
import 'package:strnadi/api/models/map_search_result.dart';
import 'package:strnadi/map/search/map_search_bar.dart';

void main() {
  testWidgets('coordinate input selects a location without an API call', (
    tester,
  ) async {
    final controller = _SearchController();
    LatLng? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchBarWidget(
            searchController: controller,
            onLocationSelected: (location) => selected = location,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '49.2, 16.6');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pump();
    expect(controller.requests, isEmpty);
    await tester.tap(find.text('49.2, 16.6').last);
    expect(selected, const LatLng(49.2, 16.6));
  });

  testWidgets(
    'late search responses cannot replace the current query results',
    (tester) async {
      final controller = _SearchController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchBarWidget(
              searchController: controller,
              onLocationSelected: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'old');
      await tester.pump(const Duration(milliseconds: 301));
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump(const Duration(milliseconds: 301));
      controller.requests['new']!.complete([
        const MapSearchResult(name: 'Current place', latLng: LatLng(50, 15)),
      ]);
      await tester.pump();
      controller.requests['old']!.complete([
        const MapSearchResult(name: 'Obsolete place', latLng: LatLng(49, 16)),
      ]);
      await tester.pump();
      expect(find.text('Current place'), findsOneWidget);
      expect(find.text('Obsolete place'), findsNothing);
    },
  );
}

class _SearchController extends MapSearchController {
  final requests = <String, Completer<List<MapSearchResult>>>{};

  @override
  Future<List<MapSearchResult>> search(String query) {
    final completer = Completer<List<MapSearchResult>>();
    requests[query] = completer;
    return completer.future;
  }
}
