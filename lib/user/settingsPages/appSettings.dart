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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/localization/localization.dart';
import '../../bottomBar.dart';
import '../settingsManager.dart';
import 'package:strnadi/config/config.dart';

class SettingsPage extends StatefulWidget {
  SettingsPage({super.key, required this.logout});
  Function(BuildContext, {bool popUp}) logout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();

  late String language = 'cs';

  bool useMobileData = true;

  int _localRecodingsMax = 50;

  // Secure role-gated environment switch
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _canEditEnv = false;
  HostEnvironment _env = HostEnvironment.prod;
  bool _envChanging = false;

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
    var prefs = await SharedPreferences.getInstance();
    var language = await Config.getLanguagePreference();
    setState(() {
      this.language = Config.StringFromLanguagePreference(language) ?? 'cs';
    });
  }

  Future<void> _loadEnvAccessAndValue() async {
    try {
      final role = await _secure.read(key: 'role') ?? '';
      final allowed = role == 'admin' || role == 'tester' || Config.hostEnvironment == HostEnvironment.dev;
      _canEditEnv = allowed;
      _env = Config.hostEnvironment;
    } catch (e) {
      _canEditEnv = false;
      _env = Config.hostEnvironment;
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLanguage();
    _loadEnvAccessAndValue();
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
            if (_canEditEnv) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Developer settings'),
              _buildEnvDropdown(),
            ],
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
        DropdownMenuItem(value: 'de', child: Text('Deutsch')),
      ],
      onChanged: (String? newValue) async {
        if (newValue != null) {
          Localization.load('assets/lang/$newValue.json').then((_) {
            setState(() {});
          });
          final prefs = await SharedPreferences.getInstance();

          await prefs.setString('lang', newValue);
          Config.setLanguagePreference(Config.LangFromString(newValue));
          // Optionally save the selected language to persistent storage
        }
      },
    );
  }

  Widget _buildEnvDropdown() {
    return DropdownButtonFormField<HostEnvironment>(
      value: _env,
      decoration: InputDecoration(
        labelText: 'Server environment',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: const [
        DropdownMenuItem(
          value: HostEnvironment.prod,
          child: Text('Production'),
        ),
        DropdownMenuItem(
          value: HostEnvironment.dev,
          child: Text('Development'),
        ),
      ],
      onChanged: _envChanging
          ? null
          : (HostEnvironment? newVal) async {
              if (newVal == null || newVal == _env) return;

              final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Change environment?'),
                      content: const Text(
                        'Switching environment will sign you out immediately. Continue?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  ) ??
                  false;

              if (!confirmed) return;

              setState(() => _envChanging = true);
              try {
                await Config.setHostEnvironment(newVal);

                // Reload local env + role access (role likely wiped on logout)
                await _loadEnvAccessAndValue();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      newVal == HostEnvironment.dev
                          ? 'Environment set to Development. You have been signed out.'
                          : 'Environment set to Production. You have been signed out.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );

                widget.logout(context, popUp: false);
                // Return to app root so auth guard can redirect to sign-in
                //Navigator.of(context).popUntil((route) => route.isFirst);
              } finally {
                if (mounted) setState(() => _envChanging = false);
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
