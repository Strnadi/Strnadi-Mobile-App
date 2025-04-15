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
/*
 * Callback_dispatcher.dart
 */

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/config/config.dart';

import 'PostRecordingForm/addDialect.dart';


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
        logger.e("BG Failed to get recording from DB: $e", error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
      }
      if (recording != null && (recording.path == null || recording.path!.isEmpty || !recording.downloaded)) {
        logger.i("Recording path is empty or not downloaded. Attempting to concatenate parts for recording id $recordingId.");
        await DatabaseNew.concatRecordingParts(recording.id!);
        recording = await DatabaseNew.getRecordingFromDbById(recording.id!);
        if (recording != null && (recording.path != null && recording.path!.isNotEmpty && recording.downloaded)) {
          logger.i("Recording updated after concatenation: path = ${recording.path}, downloaded = ${recording.downloaded}");
        } else {
          logger.w("Recording still not downloaded after attempting concatenation.");
        }
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
          await DatabaseNew.sendLocalNotification("Nahrávka se odeslala", "Nahrávka $recordingId se úspěšně odeslala.");

          // ---------------------------

          // Send dialects after successful recording upload
          List<RecordingDialect> dialectSegments = await DatabaseNew.getRecordingDialects(recording.id!);
          
          var dialects = dialectSegments.map((e) => DatabaseNew.ToDialectModel(e)).toList();
          final tokenStorage = FlutterSecureStorage();
          final jwt = await tokenStorage.read(key: 'token');

          if (jwt == null) {
            logger.e("JWT token not found in secure storage.");
          } else {
            for (DialectModel dialect in dialects) {
              final dialectBody = {
                'recordingId': recording.id,
                'StartDate': recording.createdAt
                    .add(Duration(milliseconds: dialect.startTime.toInt()))
                    .toIso8601String(),
                'endDate': recording.createdAt
                    .add(Duration(milliseconds: dialect.endTime.toInt()))
                    .toIso8601String(),
                'dialectCode': dialect.label,
              };

              try {
                final url = Uri(
                  scheme: 'https',
                  host: Config.host,
                  path: '/recordings/filtered/upload',
                );

                final response = await http.post(
                  url,
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer $jwt',
                  },
                  body: jsonEncode(dialectBody),
                );

                if (response.statusCode == 200) {
                  logger.i("Dialect ${dialect.label} sent successfully");
                } else {
                  logger.e(
                    "Dialect sending failed with status ${response.statusCode}. Response: ${response.body}",
                  );
                }
              } catch (e, stackTrace) {
                logger.e("Error sending dialect ${dialect.label}: $e", error: e, stackTrace: stackTrace);
              }
            }
          }


          // --------------------------

        } catch (e, stackTrace) {
          recording.sending = false;
          await DatabaseNew.updateRecording(recording);
          logger.e("Failed to upload recording $recordingId in background: $e", error: e, stackTrace: stackTrace);
          await DatabaseNew.sendLocalNotification("Nahrávání nahrávky selhalo", "Odesílání nahrávky $recordingId selhalo s chybou: $e");
        }
      } else {
        logger.e("Recording $recordingId not found in DB");
        await DatabaseNew.sendLocalNotification("Recording Not Found", "Recording $recordingId was not found in the database.");
      }
    }
    return Future.value(true);
  });
}