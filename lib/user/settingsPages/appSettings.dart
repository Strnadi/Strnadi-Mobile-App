/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:strnadi/localization/localization.dart';
import '../../bottomBar.dart';
import '../settingsManager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();

  late String language = 'cs';

  bool useMobileData = true;

  int _localRecodingsMax = 50;

  Future<void> _loadSettings() async {
    useMobileData = await _settingsService.isCellular();
    _localRecodingsMax = await _settingsService.getLocalRecordingsMax();
    setState(() {});
  }

  Future<bool> _saveSettings() async {
    await _settingsService.setCellular(useMobileData);
    await _settingsService.setLocalRecordingsMax(_localRecodingsMax);
    return true;
  }

  Future<void> _loadLanguage() async {
    FlutterSecureStorage storage = const FlutterSecureStorage();
    var language = await storage.read(key: 'language');
    setState(() {
      this.language = language ?? 'cs';
    });
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLanguage();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      allawArrowBack: true,
      appBarTitle: t('user.settings.title'),
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildSectionTitle(t('user.settings.app')),
            _buildSwitchTile(
              t('user.settings.fields.useMobileData'),
              useMobileData,
              (value) => setState(() => useMobileData = value),
            ),
            SpinBox(
              min: 10,
              max: 100,
              value: _localRecodingsMax.toDouble(),
              onChanged: (value) {
                setState(() => _localRecodingsMax = value.toInt());
                _saveSettings();
              },
            ),
            const SizedBox(height: 8),
            Text(
              t('user.settings.fields.localRecordingsMax'),
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            LanguageDropdown(language),
          ],
        ),
      ),
    );
  }

  Widget LanguageDropdown(String? initialValue) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue ?? 'cs',
      decoration: InputDecoration(
        labelText: t('user.settings.fields.language'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(value: 'cs', child: Text('Čeština')),
        DropdownMenuItem(value: 'en', child: Text('English')),
      ],
      onChanged: (String? newValue) {
        if (newValue != null) {
          Localization.load('assets/lang/$newValue.json').then((_) {
            setState(() {});
          });
          FlutterSecureStorage storage = const FlutterSecureStorage();
          storage.write(key: 'language', value: newValue);
          // Optionally save the selected language to persistent storage
        }
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      value: value,
      onChanged: (newValue) async {
        onChanged(newValue);
        await _saveSettings();
      },
      activeColor: Colors.green,
    );
  }
}
