/*
 * Callback_dispatcher.dart
 */

import 'package:workmanager/workmanager.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:logger/logger.dart';

final logger = Logger();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == "sendRecording") {
      int recordingId = inputData?["recordingId"];
      // Retrieve the recording from the database using the local id.
      Recording? recording = await DatabaseNew.getRecordingFromDbById(recordingId);
      if (recording != null) {
        if (recording.sending) return Future.value(false);
        recording.sending = true;
        await DatabaseNew.updateRecording(recording);
        // Retrieve parts using the local recording id.
        List<RecordingPart> parts = DatabaseNew.getPartsById(recording.id!);
        try {
          await DatabaseNew.sendRecording(recording, parts);
          logger.i("Recording $recordingId uploaded successfully in background");
          await DatabaseNew.sendLocalNotification("Recording Uploaded", "Recording $recordingId uploaded successfully in background");
        } catch (e, stackTrace) {
          recording.sending = false;
          await DatabaseNew.updateRecording(recording);
          logger.e("Failed to upload recording $recordingId in background: $e", error: e, stackTrace: stackTrace);
          await DatabaseNew.sendLocalNotification("Recording Upload Failed", "Recording $recordingId failed to upload: $e");
        }
      } else {
        logger.e("Recording $recordingId not found in DB");
        await DatabaseNew.sendLocalNotification("Recording Not Found", "Recording $recordingId was not found in the database.");
      }
    }
    return Future.value(true);
  });
}