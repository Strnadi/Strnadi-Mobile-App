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
import 'package:geolocator/geolocator.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/logging/app_logger.dart';
import '../widgets/recording_dialogs.dart';
import 'recording_permission.dart';

final logger = AppLogger(scope: 'recording.permission');

Future<bool> getLocationPermission(BuildContext context) async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (!isUsableRecordingLocationPermission(permission) &&
      permission != LocationPermission.deniedForever) {
    permission = await Geolocator.requestPermission();
  }
  if (!context.mounted) return false;
  logger.i("Location permission: $permission");
  if (isUsableRecordingLocationPermission(permission)) {
    return true;
  }

  // A denied-forever status cannot change through another request. Show one
  // actionable message and return instead of repeatedly stacking dialogs.
  showRecordingMessage(context, t('streamRec.errors.locationPermission'));
  return false;
}
