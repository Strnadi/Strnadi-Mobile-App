import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/api/models/map_clusters.dart';
import 'package:strnadi/api/models/map_feature_filters.dart';
import 'package:strnadi/map/filters/map_feature_filter_controls.dart';
import 'package:strnadi/map/filters/map_filter_defaults.dart';
import 'package:strnadi/map/filters/recording_author_filter.dart';

MapClustersRequest request(
  MapFeatureFilters filters, {
  Object? userId,
  String owner = 'All',
}) => MapClustersRequest(
  center: const LatLng(50, 14),
  zoom: 12,
  viewportWidthPx: 390,
  viewportHeightPx: 844,
  devicePixelRatio: 2,
  dialectMode: 'AiAdmin',
  ownerScope: owner,
  userId: userId,
  featureFilters: filters,
  clustered: mapFilterDefaults.clustered,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final packageFile = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(await packageFile.readAsString())['packages'] as List;
    final flutter = packages.cast<Map>().firstWhere(
      (entry) => entry['name'] == 'flutter',
    );
    final root = packageFile.uri.resolve(flutter['rootUri'] as String);
    final font = File.fromUri(
      Uri.directory(
        File.fromUri(root).path,
      ).resolve('../../bin/cache/artifacts/material_fonts/Roboto-Regular.ttf'),
    );
    final loader = FontLoader('Roboto')
      ..addFont(font.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });
  setUp(() => Localization.load('assets/lang/en.json'));

  test(
    'map defaults hide others without dialect and guests retain filtering',
    () {
      final defaults = mapFilterDefaults.featureFilters;
      expect(defaults.hideOthersWithoutMeaningfulDialect, isTrue);
      expect(defaults.forUser(signedIn: true), defaults);
      final guest = defaults.forUser(signedIn: false);
      expect(guest.onlyMeaningfulDialects, isTrue);
      expect(guest.hideOthersWithoutMeaningfulDialect, isFalse);
      expect(request(guest).toQueryParameters()['clustered'], isFalse);
    },
  );

  test('default and changed options serialize to the server contract', () {
    final defaults = request(const MapFeatureFilters()).toQueryParameters();
    expect(defaults['mixDialects'], true);
    expect(defaults['mixSources'], true);
    expect(defaults['onlyMeaningfulDialects'], false);
    expect(defaults['hideOthersWithoutMeaningfulDialect'], false);
    final changed = request(
      const MapFeatureFilters(
        mixDialects: false,
        mixSources: false,
        onlyMeaningfulDialects: true,
        hideOthersWithoutMeaningfulDialect: true,
      ),
      userId: 42,
      owner: 'Others',
    ).toQueryParameters();
    expect(changed['mixDialects'], false);
    expect(changed['mixSources'], false);
    expect(changed['onlyMeaningfulDialects'], true);
    expect(changed['hideOthersWithoutMeaningfulDialect'], true);
    expect(changed['ownerScope'], 'Others');
    expect(changed['userId'], 42);
  });

  test('all-plus-hide-others and Others fail closed without identity', () {
    expect(
      () => request(
        const MapFeatureFilters(),
        owner: 'Others',
      ).toQueryParameters(),
      throwsArgumentError,
    );
    expect(
      () => request(
        const MapFeatureFilters(hideOthersWithoutMeaningfulDialect: true),
      ).toQueryParameters(),
      throwsArgumentError,
    );
    for (final owner in ['all', 'others']) {
      final absent = resolveRecordingAuthorFilter(
        requestedFilter: owner,
        storedUserId: null,
        requiresUserId: true,
      );
      expect(absent.isAvailable, false);
      final present = resolveRecordingAuthorFilter(
        requestedFilter: owner,
        storedUserId: '42',
        requiresUserId: true,
      );
      expect(present.userId, 42);
    }
    expect(
      resolveRecordingAuthorFilter(
        requestedFilter: 'others',
        storedUserId: null,
      ).isAvailable,
      false,
    );
  });

  testWidgets(
    'each switch updates its request value and defaults reset all options',
    (tester) async {
      var value = const MapFeatureFilters();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Column(
                  children: [
                    MapFeatureFilterControls(
                      value: value,
                      clustered: true,
                      canFilterByUser: true,
                      onChanged: (next) => setState(() => value = next),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => value = const MapFeatureFilters()),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mixDialects')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('advanced-map-filters')));
      await tester.pumpAndSettle();
      for (final key in [
        'mixDialects',
        'mixSources',
        'onlyMeaningfulDialects',
        'hideOthersWithoutMeaningfulDialect',
      ]) {
        final control = find.byKey(ValueKey(key));
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(
          request(value, userId: 42).toQueryParameters()[key],
          key == 'onlyMeaningfulDialects' ||
              key == 'hideOthersWithoutMeaningfulDialect',
        );
      }
      await tester.ensureVisible(find.text('Reset'));
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(value, const MapFeatureFilters());
    },
  );

  testWidgets('mixing is disabled without clustering and retains selections', (
    tester,
  ) async {
    const value = MapFeatureFilters(mixDialects: false, mixSources: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapFeatureFilterControls(
            value: value,
            clustered: false,
            canFilterByUser: true,
            onChanged: (_) => fail('Disabled cluster control changed'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('advanced-map-filters')));
    await tester.pumpAndSettle();
    for (final key in ['mixDialects', 'mixSources']) {
      final tile = tester.widget<SwitchListTile>(find.byKey(ValueKey(key)));
      expect(tile.onChanged, isNull);
      expect(tile.value, false);
    }
  });

  testWidgets('guest cannot select relative owner or hide-others filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                MapOwnerFilterControl(
                  value: 'all',
                  canFilterByUser: false,
                  onChanged: (_) {},
                ),
                MapFeatureFilterControls(
                  value: const MapFeatureFilters(),
                  clustered: true,
                  canFilterByUser: false,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('advanced-map-filters')));
    await tester.pumpAndSettle();
    for (final owner in ['me', 'others']) {
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(ValueKey('map-owner-$owner')))
            .onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('hideOthersWithoutMeaningfulDialect')),
          )
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('map-owner-all')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('other recordings can be selected', (tester) async {
    var owner = 'all';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapOwnerFilterControl(
            value: owner,
            canFilterByUser: true,
            onChanged: (value) => owner = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('map-owner-others')));
    expect(owner, 'others');
  });

  for (final locale in ['cs', 'en', 'de']) {
    testWidgets('$locale filter controls fit a narrow screen', (tester) async {
      await tester.runAsync(
        () => Localization.load('assets/lang/$locale.json'),
      );
      await tester.binding.setSurfaceSize(const Size(360, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSwatch().copyWith(
              primary: Colors.blue,
            ),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('filters-golden'),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    MapOwnerFilterControl(
                      value: 'others',
                      canFilterByUser: true,
                      onChanged: (_) {},
                    ),
                    MapFeatureFilterControls(
                      value: const MapFeatureFilters(),
                      clustered: true,
                      canFilterByUser: true,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('filters-golden')),
        matchesGoldenFile('goldens/feature_filters_$locale.png'),
      );
      await tester.tap(find.byKey(const ValueKey('advanced-map-filters')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('filters-golden')),
        matchesGoldenFile('goldens/feature_filters_expanded_$locale.png'),
      );
    });
  }
}
