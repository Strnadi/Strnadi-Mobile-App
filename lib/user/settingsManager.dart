import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _cellular = 'CellularData';

  Future<void> setCellular(bool cellular) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cellular, cellular);
  }

  Future<bool> isCellular() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cellular) ?? true; // Default: cellular data is enabled
  }

  Future<bool> isNotification() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('Notification') ?? true; // Default: notifications are enabled
  }

  Future<void> setNotification(bool notification) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('Notification', notification);
  }

  Future<bool> setLocalRecordingsMax(int localRecodingsMax) async {
    final prefs = SharedPreferences.getInstance();
    prefs.then((value) => value.setInt('LocalRecordingsMax', localRecodingsMax));
    return true;
  }

  Future<int> getLocalRecordingsMax() async {
    final prefs = SharedPreferences.getInstance();
    return prefs.then((value) => value.getInt('LocalRecordingsMax') ?? 50);
  }
}
