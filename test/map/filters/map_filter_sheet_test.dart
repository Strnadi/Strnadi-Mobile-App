import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/models/map_feature_filters.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/filters/map_filter_defaults.dart';
import 'package:strnadi/map/filters/map_filter_selection.dart';
import 'package:strnadi/map/filters/map_filter_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final config = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await config.readAsString())['packages'] as List;
    final flutter = packages.cast<Map>().firstWhere(
      (p) => p['name'] == 'flutter',
    );
    final root = config.uri.resolve(flutter['rootUri'] as String);
    final font = File.fromUri(
      Uri.directory(
        File.fromUri(root).path,
      ).resolve('../../bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
    );
    await (FontLoader(
      'MapFilterRoboto',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    final icons = File.fromUri(
      Uri.directory(File.fromUri(root).path).resolve(
        '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
    await (FontLoader(
      'MaterialIcons',
    )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
  });
  setUp(() => Localization.load('assets/lang/en.json'));

  test('one initial selection defines every filter default', () {
    expect(mapFilterDefaults.satelliteView, false);
    expect(mapFilterDefaults.authorFilter, 'all');
    expect(mapFilterDefaults.recordingAge, RecordingAgeFilter.newer);
    expect(mapFilterDefaults.dialectVisibility, DialectVisibilityMode.aiAdmin);
    expect(mapFilterDefaults.clustered, false);
    expect(mapFilterDefaults.featureFilters.mixDialects, true);
    expect(mapFilterDefaults.featureFilters.mixSources, true);
    expect(mapFilterDefaults.featureFilters.onlyMeaningfulDialects, false);
    expect(
      mapFilterDefaults.featureFilters.hideOthersWithoutMeaningfulDialect,
      true,
    );
  });

  testWidgets('selection applies immediately and dismissal retains it', (
    tester,
  ) async {
    var selection = mapFilterDefaults;
    var changes = 0;
    await _openSheet(
      tester,
      selection: selection,
      onChanged: (value) {
        selection = value;
        changes++;
      },
    );
    expect(find.byKey(const ValueKey('mixDialects')), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('map.filters.mapView.satellite')),
    );
    await tester.pumpAndSettle();
    expect(selection.satelliteView, true);
    expect(selection.clustered, false);
    expect(changes, 1);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(MapFilterSheet), findsNothing);
    expect(selection.satelliteView, true);
  });

  testWidgets('reset restores all shared defaults with clustering off', (
    tester,
  ) async {
    var selection = const MapFilterSelection(
      satelliteView: true,
      authorFilter: 'others',
      recordingAge: RecordingAgeFilter.older,
      dialectVisibility: DialectVisibilityMode.adminOnly,
      clustered: true,
      featureFilters: MapFeatureFilters(
        mixDialects: false,
        mixSources: false,
        onlyMeaningfulDialects: true,
        hideOthersWithoutMeaningfulDialect: false,
      ),
    );
    await _openSheet(
      tester,
      selection: selection,
      onChanged: (value) => selection = value,
    );
    final reset = find.byKey(const ValueKey('map-reset-filters'));
    await tester.scrollUntilVisible(
      reset,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(selection, mapFilterDefaults);
    expect(selection.clustered, false);
    expect(find.byKey(const ValueKey('mixDialects')), findsNothing);
  });

  testWidgets('guest sheet leaves relative owner filters disabled', (
    tester,
  ) async {
    await _openSheet(
      tester,
      selection: mapFilterDefaults,
      canFilterByUser: false,
      onChanged: (_) => fail('Disabled owner control changed selection'),
    );
    for (final owner in ['me', 'others']) {
      final finder = find.byKey(ValueKey('map-owner-$owner'));
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(tester.widget<OutlinedButton>(finder).onPressed, isNull);
    }
  });

  testWidgets('new selection from the parent updates visible controls', (
    tester,
  ) async {
    var selection = mapFilterDefaults;
    late StateSetter updateParent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              updateParent = setState;
              return MapFilterSheet(
                selection: selection,
                canFilterByUser: true,
                onChanged: (_) {},
              );
            },
          ),
        ),
      ),
    );
    updateParent(() => selection = selection.copyWith(satelliteView: true));
    await tester.pump();
    final satellite = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('map.filters.mapView.satellite')),
    );
    expect(satellite.style!.side!.resolve({})!.color, Colors.black);
  });

  testWidgets('extracted map settings retain their mobile layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _openSheet(tester, selection: mapFilterDefaults, onChanged: (_) {});
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('map-filter-sheet-golden')),
      matchesGoldenFile('../goldens/map_filter_sheet.png'),
    );
    await tester.drag(
      find.byIcon(Icons.unfold_more_rounded),
      const Offset(0, -380),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('map-filter-sheet-golden')),
      matchesGoldenFile('../goldens/map_filter_sheet_expanded.png'),
    );
  });
}

Future<void> _openSheet(
  WidgetTester tester, {
  required MapFilterSelection selection,
  required ValueChanged<MapFilterSelection> onChanged,
  bool canFilterByUser = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'MapFilterRoboto'),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => RepaintBoundary(
                key: const ValueKey('map-filter-sheet-golden'),
                child: MapFilterSheet(
                  selection: selection,
                  canFilterByUser: canFilterByUser,
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
