import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/map/map_clusters.dart';
import 'package:strnadi/map/map_cluster_picker.dart';
import 'package:strnadi/map/map_feature_marker.dart';
import 'map_feature_fixtures.dart';

void main() {
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
      'PickerRoboto',
    )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
  });
  setUp(() => Localization.load('assets/lang/en.json'));
  testWidgets(
    'picker loads remaining items, retries failures and selects the sixth',
    (tester) async {
      var attempts = 0;
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapClusterPicker(
              cluster: MapCluster.fromJson(clusterJson()),
              isCurrent: () => true,
              onExpired: () => fail('Unexpected expiry'),
              onSelect: (id) => selected = id,
              loadPage: (cursor) async {
                expect(cursor, 'cursor+/?=');
                if (++attempts == 1) throw Exception('offline');
                return MapClusterItemsPage.fromResponseData(pageJson());
              },
            ),
          ),
        ),
      );
      expect(find.text('Recordings (6)'), findsOneWidget);
      expect(find.text('Recording 6'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load more recordings.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Load more'), findsNothing);
      await tester.scrollUntilVisible(find.text('Recording 6'), 100);
      await tester.tap(find.text('Recording 6'));
      expect(selected, 6);
      expect(attempts, 2);
    },
  );
  testWidgets('expired snapshots request refresh', (tester) async {
    var expired = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapClusterPicker(
            cluster: MapCluster.fromJson(clusterJson()),
            isCurrent: () => true,
            onExpired: () => expired++,
            onSelect: (_) {},
            loadPage: (_) async => throw ClusterSnapshotExpired(),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(expired, 1);
    expect(find.text('Recording 6'), findsNothing);
  });
  testWidgets('late responses from an old scope never append recordings', (
    tester,
  ) async {
    var current = true, expired = false;
    final completer = Completer<MapClusterItemsPage>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapClusterPicker(
            cluster: MapCluster.fromJson(clusterJson()),
            isCurrent: () => current,
            onExpired: () => expired = true,
            onSelect: (_) => fail('Old scope selected'),
            loadPage: (_) => completer.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load more'));
    await tester.pump();
    current = false;
    completer.complete(MapClusterItemsPage.fromResponseData(pageJson()));
    await tester.pumpAndSettle();
    expect(expired, true);
    expect(find.text('Recording 6'), findsNothing);
  });
  testWidgets('malformed continuation keeps preview and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapClusterPicker(
            cluster: MapCluster.fromJson(clusterJson()),
            isCurrent: () => true,
            onExpired: () {},
            onSelect: (_) {},
            loadPage: (_) async => MapClusterItemsPage.fromResponseData(
              pageJson()..['clusterId'] = 'other',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Recording 1'), findsOneWidget);
    expect(find.text('Recording 6'), findsNothing);
  });
  testWidgets(
    'individual recordings are compact tappable tiles without a badge',
    (tester) async {
      final feature = MapCluster.fromJson(recordingJson());
      var taps = 0;
      expect(MapFeatureMarker.extent(feature), 30);
      expect(MapFeatureMarker.extent(MapCluster.fromJson(clusterJson())), 48);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: MapFeatureMarker.extent(feature),
              child: MapFeatureMarker(feature: feature, onTap: () => taps++),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.text('1'), findsNothing);
      expect(
        tester.getSize(
          find.descendant(
            of: find.byType(MapFeatureMarker),
            matching: find.byType(CustomPaint),
          ),
        ),
        const Size(20, 20),
      );
      await tester.tap(find.byType(MapFeatureMarker));
      expect(taps, 1);
    },
  );

  testWidgets('mobile picker metadata golden and dismiss preserves map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'PickerRoboto'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => RepaintBoundary(
                    key: const Key('picker-golden'),
                    child: Material(
                      child: MapClusterPicker(
                        cluster: MapCluster.fromJson(clusterJson()),
                        isCurrent: () => true,
                        onExpired: () {},
                        onSelect: (_) {},
                        loadPage: (_) async =>
                            MapClusterItemsPage.fromResponseData(pageJson()),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Filtered map'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Filtered map'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sep 8, 2026'), findsWidgets);
    await expectLater(
      find.byKey(const Key('picker-golden')),
      matchesGoldenFile('goldens/cluster_picker_mobile.png'),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(MapClusterPicker), findsNothing);
    expect(find.text('Filtered map'), findsOneWidget);
  });

  testWidgets('server percentage markers golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const Key('markers'),
              child: SizedBox(
                width: 160,
                height: 80,
                child: ColoredBox(
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: MapFeatureMarker(
                          feature: MapCluster.fromJson(recordingJson()),
                          onTap: () {},
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: MapFeatureMarker(
                          feature: MapCluster.fromJson(clusterJson()),
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const Key('markers')),
      matchesGoldenFile('goldens/server_feature_markers.png'),
    );
  });
}
