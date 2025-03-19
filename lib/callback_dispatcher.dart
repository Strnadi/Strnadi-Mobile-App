/*
 * Callback_dispatcher.dart
 */

import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/config/config.dart';


final logger = Logger();

Future<void> registerPlugins() async{
  await Config.loadConfig();

  await Config.loadFirebaseConfig();

  WidgetsFlutterBinding.ensureInitialized();
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    logger.i('Got background task: $task');
    await registerPlugins();
    logger.i('ensureInitialized');
    if (task == "sendRecording" || task == "com.delta.strnadi.sendRecording") {
      logger.i("Sending recording in background");
      int recordingId = inputData?["recordingId"];
      // Retrieve the recording from the database using the local id.
      logger.i('Getting recording from DB with id $recordingId');
      Recording? recording;
      try {
        recording = await DatabaseNew.getRecordingFromDbById(
            recordingId);
      } catch(e, stackTrace) {
        logger.e("BG Failed to get recording from DB: $e", error: e, stackTrace: stackTrace);Sentry.captureException(e, stackTrace: stackTrace);
      }
      logger.i('Got recording from DB with id $recordingId');
      if (recording != null) {
        if (recording.sending) return Future.value(false);
        recording.sending = true;
        logger.i('Updating recording $recordingId to sending');
        await DatabaseNew.updateRecording(recording);
        // Retrieve parts using the local recording id.
        logger.i('Getting parts from DB with recording id $recordingId');
        List<RecordingPart> parts = DatabaseNew.getPartsById(recording.id!);
        try {
          logger.i('Starting to send recording $recordingId in background');
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