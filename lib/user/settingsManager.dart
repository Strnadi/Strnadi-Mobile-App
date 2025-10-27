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
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strnadi/config/config.dart';

class SettingsService {
  static const String _cellular = 'CellularData';

  Future<void> setCellular(
    bool cellular, {
    VoidCallback? onStart,
    VoidCallback? onDone,
  }) async {
    onStart?.call();
    try {
      await Config.setDataUsageOption(
        cellular ? DataUsageOption.wifiAndMobile : DataUsageOption.wifiOnly,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cellular, cellular);
    } finally {
      onDone?.call();
    }
  }

  Future<bool> isCellular() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cellular) ?? true; // Default: cellular data is enabled
  }

  Future<bool> setLocalRecordingsMax(int localRecodingsMax) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.setInt('LocalRecordingsMax', localRecodingsMax);
  }

  Future<int> getLocalRecordingsMax() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('LocalRecordingsMax') ?? 50;
  }
}
