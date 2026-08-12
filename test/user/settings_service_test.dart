import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/user/settingsManager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mobile upload preference (no API or DB)', () {
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      service = SettingsService();
      await Config.loadDataUsageOption();
    });

    test('enabling mobile uploads immediately changes policy and persists',
        () async {
      await service.setCellular(true);

      expect(Config.dataUsageOption, DataUsageOption.wifiAndMobile);
      expect(await service.isCellular(), isTrue);
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      expect(preferences.getBool('CellularData'), isTrue);
      expect(
        preferences.getString('data_usage_option'),
        DataUsageOption.wifiAndMobile.toString(),
      );
    });

    test('disabling mobile uploads immediately changes policy and persists',
        () async {
      await service.setCellular(true);
      await service.setCellular(false);

      expect(Config.dataUsageOption, DataUsageOption.wifiOnly);
      expect(await service.isCellular(), isFalse);
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      expect(preferences.getBool('CellularData'), isFalse);
      expect(
        preferences.getString('data_usage_option'),
        DataUsageOption.wifiOnly.toString(),
      );
    });

    test('settings switch awaits persistence without touching the spinner', () {
      final String source = File(
        'lib/user/settingsPages/appSettings.dart',
      ).readAsStringSync();
      final int switchBuilder = source.indexOf(
        'Widget _buildSwitchTile(',
      );
      final String method = source.substring(switchBuilder);

      expect(method, contains('onChanged(newValue);'));
      expect(method, contains('await _saveSettings();'));
    });
  });
}
