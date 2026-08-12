import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/dialects/dynamicIcon.dart';
import 'package:strnadi/map/mapUtils/dialect_marker_selection.dart';

void main() {
  group('dialect color cache scope', () {
    test('separates production and development environments', () {
      final String productionKey = DialectColorCache.preferencesKeyForScope(
        environment: 'prod',
        host: 'api.strnadi.cz',
      );
      final String developmentKey = DialectColorCache.preferencesKeyForScope(
        environment: 'dev',
        host: 'devapi.strnadi.cz',
      );

      expect(productionKey, isNot(developmentKey));
    });

    test('separates hosts even when the environment label matches', () {
      final String firstKey = DialectColorCache.preferencesKeyForScope(
        environment: 'dev',
        host: 'devapi.strnadi.cz',
      );
      final String secondKey = DialectColorCache.preferencesKeyForScope(
        environment: 'dev',
        host: 'preview-api.strnadi.cz',
      );

      expect(firstKey, isNot(secondKey));
    });

    test('normalizes equivalent scope spelling', () {
      expect(
        DialectColorCache.preferencesKeyForScope(
          environment: ' DEV ',
          host: ' DevApi.Strnadi.Cz ',
        ),
        DialectColorCache.preferencesKeyForScope(
          environment: 'dev',
          host: 'devapi.strnadi.cz',
        ),
      );
    });

    testWidgets('reads colors only from the active environment scope',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await Config.loadConfig();
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      await Config.setHostEnvironment(HostEnvironment.prod);
      final String productionKey = DialectColorCache.preferencesKeyForScope(
        environment: Config.hostEnvironment.name,
        host: Config.host,
      );
      await preferences.setString(productionKey, '{"BC":"#112233"}');

      await Config.setHostEnvironment(HostEnvironment.dev);
      final String developmentKey = DialectColorCache.preferencesKeyForScope(
        environment: Config.hostEnvironment.name,
        host: Config.host,
      );
      await preferences.setString(developmentKey, '{"BC":"#445566"}');

      await Config.setHostEnvironment(HostEnvironment.prod);
      expect(
        await DialectColorCache.getColors(<String>['BC']),
        <Color>[const Color(0xff112233)],
      );

      await Config.setHostEnvironment(HostEnvironment.dev);
      expect(
        await DialectColorCache.getColors(<String>['BC']),
        <Color>[const Color(0xff445566)],
      );

      await Config.setHostEnvironment(HostEnvironment.prod);
    });
  });

  test('environment switch clears and refreshes the new color scope', () {
    final String settingsSource =
        File('lib/user/settingsPages/appSettings.dart').readAsStringSync();
    final int switchStart =
        settingsSource.indexOf('await Config.setHostEnvironment(newVal);');
    final int logoutStart =
        settingsSource.indexOf('await widget.logout(', switchStart);
    final String switchBody =
        settingsSource.substring(switchStart, logoutStart);

    expect(switchStart, greaterThanOrEqualTo(0));
    expect(
      switchBody,
      contains(
        'await DynamicIcon.refreshAllDialects(clearExisting: true);',
      ),
    );
  });

  testWidgets('sentinel fallback is rendered as a single-color marker',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const RecordingDialectSummary emptySummary = RecordingDialectSummary(
      dialects: <String>[],
      selectedTier: SelectedDialectTier.none,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: DynamicIcon(
            key: const ValueKey<String>('sentinel-marker'),
            icon: Icons.circle,
            dialects: dialectsForMapMarker(emptySummary),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder marker = find.byKey(
      const ValueKey<String>('sentinel-marker'),
    );
    expect(marker, findsOneWidget);
    expect(
      find.descendant(of: marker, matching: find.byType(CustomPaint)),
      findsNothing,
    );
  });
}
