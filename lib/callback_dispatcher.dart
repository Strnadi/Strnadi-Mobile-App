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
        DatabaseNew.updateRecording(recording);
        // Retrieve parts – assuming BEId is set for recordings that are ready to send
        List<RecordingPart> parts = DatabaseNew.getPartsById(recording.BEId ?? 0);
        try {
          await DatabaseNew.sendRecording(recording, parts);
          logger.i("Recording $recordingId uploaded successfully in background");
        } catch (e) {
          logger.e("Failed to upload recording $recordingId in background: $e");
        }
      } else {
        logger.e("Recording $recordingId not found in DB");
      }
    }
    // Return true when the task is complete.
    return Future.value(true);
  });
}
