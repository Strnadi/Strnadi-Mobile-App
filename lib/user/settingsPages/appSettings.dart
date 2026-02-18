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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/Models/recordingPart.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:logger/logger.dart';
import '../../bottomBar.dart';
import '../settingsManager.dart';
import 'package:strnadi/config/config.dart';

final _logger = Logger();

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
  bool _cacheLoading = false;
  final List<_CachedRecordingItem> _cachedRecordings = [];

  Future<void> _loadSettings() async {
    useMobileData = await _settingsService.isCellular();
    _localRecodingsMax = await _settingsService.getLocalRecordingsMax();
    setState(() {});
  }

  Future<void> _loadCachedRecordings() async {
    if (mounted) {
      setState(() {
        _cacheLoading = true;
      });
    }
    try {
      final List<Recording> recordings =
          await DatabaseNew.getDownloadedRecordingsForCurrentUser();
      final List<_CachedRecordingItem> loaded = [];
      for (final Recording recording in recordings) {
        loaded.add(
          _CachedRecordingItem(
            recording: recording,
            sizeBytes: await _calculateRecordingSize(recording),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _cachedRecordings
          ..clear()
          ..addAll(loaded);
      });
    } catch (e, stackTrace) {
      _logger.e('Failed to load cached recordings',
          error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _cachedRecordings.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _cacheLoading = false;
        });
      }
    }
  }

  Future<int> _calculateRecordingSize(Recording recording) async {
    final Set<String> paths = <String>{};
    if (recording.path != null && recording.path!.isNotEmpty) {
      paths.add(recording.path!);
    }
    if (recording.id != null) {
      final List<RecordingPart> parts =
          await DatabaseNew.getPartsByRecordingId(recording.id!);
      for (final RecordingPart part in parts) {
        if (part.path != null && part.path!.isNotEmpty) {
          paths.add(part.path!);
        }
      }
    }

    int total = 0;
    for (final String path in paths) {
      final file = File(path);
      if (await file.exists()) {
        total += await file.length();
      }
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _fallbackRecordingName(Recording recording) {
    final String? name = recording.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (recording.BEId != null) return 'Recording #${recording.BEId}';
    if (recording.id != null) return 'Recording #${recording.id}';
    return t('user.settings.cacheManager.unnamed');
  }

  Future<void> _deleteCachedRecording(_CachedRecordingItem item) async {
    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t('user.settings.cacheManager.confirmTitle')),
            content: Text(t('user.settings.cacheManager.confirmMessage')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t('user.settings.cacheManager.buttons.cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t('user.settings.cacheManager.buttons.remove')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    if (item.recording.id == null) return;
    try {
      await DatabaseNew.deleteRecordingFromCache(item.recording.id!);
      await _loadCachedRecordings();
    } catch (e, stackTrace) {
      _logger.e('Failed to delete cached recording ${item.recording.id}',
          error: e, stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('recListItem.errors.errorDownloading'))),
      );
    }
  }

  Future<bool> _saveSettings() async {
    await _settingsService.setCellular(useMobileData);
    await _settingsService.setLocalRecordingsMax(_localRecodingsMax);
    return true;
  }

  Future<void> _loadLanguage() async {
    var language = await Config.getLanguagePreference();
    setState(() {
      this.language = Config.StringFromLanguagePreference(language) ?? 'cs';
    });
  }

  Future<void> _loadEnvAccessAndValue() async {
    try {
      final role = await _secure.read(key: 'role') ?? '';
      final allowed = role == 'admin' ||
          role == 'tester' ||
          Config.hostEnvironment == HostEnvironment.dev;
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
    _loadCachedRecordings();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      allowArrowBack: true,
      appBarTitle: t('user.settings.title'),
      content: SingleChildScrollView(
        child: Padding(
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
              const SizedBox(height: 20),
              _buildSectionTitle(t('user.settings.cacheManager.title')),
              Text(
                t('user.settings.cacheManager.description'),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              if (_cacheLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_cachedRecordings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    t('user.settings.cacheManager.empty'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cachedRecordings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = _cachedRecordings[index];
                    final isDev =
                        item.recording.env == HostEnvironment.dev.name;
                    return ListTile(
                      tileColor: Colors.grey.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      title: Text(
                        _fallbackRecordingName(item.recording),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_formatBytes(item.sizeBytes)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDev)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'DEV',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          IconButton(
                            tooltip: t('recListItem.buttons.deleteCache'),
                            onPressed: () => _deleteCachedRecording(item),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (_canEditEnv) ...[
                const SizedBox(height: 20),
                _buildSectionTitle('Developer settings'),
                _buildEnvDropdown(),
              ],
              const SizedBox(height: 20),
            ],
          ),
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
      inactiveThumbColor: Colors.grey.shade600,
      selectedTileColor: Colors.grey,
      inactiveTrackColor: Colors.grey.shade300,
    );
  }
}

class _CachedRecordingItem {
  final Recording recording;
  final int sizeBytes;

  const _CachedRecordingItem({
    required this.recording,
    required this.sizeBytes,
  });
}
