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
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:logger/logger.dart';

final logger = Logger();

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == "sendRecording") {
      int recordingId = inputData?["recordingId"];
      // Retrieve the recording from the database
      Recording? recording = await DatabaseNew.getRecordingFromDbById(recordingId);
      if (recording != null) {
        if(recording.sending) return Future.value(false);
        recording.sending = true;
        await DatabaseNew.updateRecording(recording);
        // Retrieve parts – assuming BEId is set for recordings that are ready to send
        List<RecordingPart> parts = DatabaseNew.getPartsById(recording.id ?? 0);
        try {
          await DatabaseNew.sendRecording(recording, parts);
          logger.i("Recording $recordingId uploaded successfully in background");
        } catch (e, stackTrace) {
          recording.sending = false;
          DatabaseNew.updateRecording(recording);
          logger.e("Failed to upload recording $recordingId in background: $e", error: e, stackTrace: stackTrace);
        } catch (e) {
          logger.e("Failed to upload recording $recordingId in background: ${e.toString()}");
        }
      } else {
        if(recording!=null) {
          recording.sending = false;
          DatabaseNew.updateRecording(recording);
        }
        logger.e("Recording $recordingId not found in DB");
      }
    }
    // Return true when the task is complete.
    return Future.value(true);
  });
}
