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
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'recording_foreground_service.dart';

final logger = AppLogger(scope: 'recording.task');

class RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter taskStarter) async {
    logger.i("Foreground task started at $timestamp");
    if (taskStarter == TaskStarter.system) {
      try {
        // Recording is owned by the app isolate and cannot survive a process
        // restart. A system-started task can only be an orphan from an older
        // sticky-service configuration.
        await reconcileStaleRecordingForegroundService(
          service: const FlutterRecordingForegroundService(),
        );
      } catch (error, stackTrace) {
        logger.e(
          'Failed to stop a system-started recording service.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    logger.i("Foreground task destroyed at $timestamp (isTimeout: $isTimeout)");
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    logger.i("Foreground task event at $timestamp");
  }
}

void startRecordingCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}
