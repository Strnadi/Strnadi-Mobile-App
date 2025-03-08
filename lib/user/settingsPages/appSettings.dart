import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import '../../bottomBar.dart';
import '../settingsManager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();

  bool useMobileData = true;
  bool microphonePermission = true;
  bool locationPermission = true;
  bool notificationPermission = true;

  int _localRecodingsMax = 50;

  Future<void> _loadSettings() async {
    useMobileData = await _settingsService.isCellular();
    notificationPermission = await _settingsService.isNotification();
    _localRecodingsMax = await _settingsService.getLocalRecordingsMax();
    setState(() {});
  }

  Future<bool> _saveSettings() async {
    await _settingsService.setCellular(useMobileData);
    await _settingsService.setNotification(notificationPermission);
    await _settingsService.setLocalRecordingsMax(_localRecodingsMax);
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }


  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      allawArrowBack: true,
      appBarTitle: 'Nastavení',
      content: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            _buildSectionTitle("Aplikace"),
            _buildSwitchTile(
              "Použít mobilní data pro nahrávání",
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
            const SizedBox(height: 20),
            _buildSectionTitle("Oprávnění"),
            _buildSwitchTile(
              "Mikrofon",
              microphonePermission,
              (value) => setState(() => microphonePermission = value),
            ),
            _buildSwitchTile(
              "Lokace",
              locationPermission,
              (value) => setState(() => locationPermission = value),
            ),
            _buildSwitchTile(
              "Oznámení",
              notificationPermission,
              (value) => setState(() => notificationPermission = value),
            ),
          ],
        ),
      ),
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
