part of 'database_repository.dart';

const RecordingsController _recordingsApi = RecordingsController();
const RecordingPartsController _recordingPartsApi = RecordingPartsController();
const FilteredRecordingsController _filteredRecordingsApi =
    FilteredRecordingsController();

Future<bool> _hasInternetAccess() async {
  try {
    final result = await InternetAddress.lookup('google.com');
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } on SocketException catch (_) {
    return false;
  }
}

Future<void> _sendRecording(
    Recording recording, List<RecordingPart> recordingParts) async {
  if (!await _hasInternetAccess()) {
    logger.i('No internet connection. Recording will not be sent.');
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    return;
  }

  final String? jwt = await FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    throw FetchException('Failed to send recording to backend', 401);
  }

  final response =
      await _recordingsApi.createRecording(await recording.toBEJson());

  if (response.statusCode == 200) {
    logger.i(
        'Recording sent successfully. Sending parts. Response: ${response.data}');
    final dynamic responseBody = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    recording.BEId =
        responseBody is int ? responseBody : int.tryParse('$responseBody');
    await DatabaseNew.updateRecording(recording);

    for (final RecordingPart part in recordingParts) {
      part.recordingId = recording.id;
      part.backendRecordingId = recording.BEId;
      await _sendRecordingPart(part);
    }

    recording.sent = true;
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    logger.i('Recording id ${recording.id} sent successfully.');
  } else {
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    throw UploadException(
        'Failed to send recording to backend', response.statusCode ?? 500);
  }
}

Future<void> _sendRecordingNew(
    Recording recording, List<RecordingPart> recordingParts) async {
  if (recording.id == null) {
    logger.w('sendRecordingNew: recording has null local id, aborting.');
    return;
  }
  if (recording.sent == true) {
    logger.i(
        'sendRecordingNew: recording ${recording.id} already marked as sent. Skipping.');
    return;
  }
  if (recording.sending == true ||
      DatabaseNew._inflightRecordingIds.contains(recording.id)) {
    logger.i(
        'sendRecordingNew: recording ${recording.id} is already being sent. Skipping. sending:${recording.sending} | ${DatabaseNew._inflightRecordingIds.contains(recording.id)}');
    return;
  }

  DatabaseNew._inflightRecordingIds.add(recording.id!);
  recording.sending = true;
  await DatabaseNew.updateRecording(recording);

  if (!await Config.canUpload) {
    logger.i('Uploads are disabled by configuration.');
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    DatabaseNew._inflightRecordingIds.remove(recording.id);
    throw Exception('Uploads are disabled by configuration.');
  }

  logger.i('Sending recording id: ${recording.id}');
  final String? jwt = await FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    DatabaseNew._inflightRecordingIds.remove(recording.id);
    throw FetchException('Failed to send recording to backend', 401);
  }

  try {
    final Map<String, Object?> body = await recording.toBEJson();
    logger.i('Sending recording with body: $body');
    final response = await _recordingsApi.createRecording(body);

    if (response.statusCode == 200) {
      logger.i(
          'Recording sent successfully. Sending parts. Response: ${response.data}');
      final dynamic responseBody = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
      recording.BEId =
          responseBody is int ? responseBody : int.tryParse('$responseBody');
      await DatabaseNew.updateRecording(recording);

      for (final RecordingPart part in recordingParts) {
        try {
          part.recordingId = recording.id;
          part.backendRecordingId = recording.BEId;
          await _sendRecordingPartNew(part);
        } catch (e, stackTrace) {
          if (e is PathNotFoundException) {
            logger.e('Path not found for recording part id: ${part.id}',
                error: e, stackTrace: stackTrace);
            Sentry.captureException(e, stackTrace: stackTrace);
            if (await _handleDeletedPath(part)) {
              continue;
            } else {
              await DatabaseNew.deleteRecording(part.recordingId!);
              await _recordingsApi.deleteRecording(recording.BEId!);
            }
          }
          rethrow;
        }
      }

      recording.sent = true;
      recording.sending = false;
      await DatabaseNew.updateRecording(recording);
      logger.i('Recording id ${recording.id} sent successfully.');
    } else {
      recording.sending = false;
      await DatabaseNew.updateRecording(recording);
      throw UploadException(
          'Failed to send recording to backend', response.statusCode ?? 500);
    }
  } catch (e, stackTrace) {
    logger.e('Error sending recording: $e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    recording.sending = false;
    await DatabaseNew.updateRecording(recording);
    rethrow;
  } finally {
    if (recording.id != null) {
      DatabaseNew._inflightRecordingIds.remove(recording.id);
    }
  }
}

Future<bool> _handleDeletedPath(RecordingPart recordingPart) async {
  if (recordingPart.BEId == null || recordingPart.backendRecordingId == null) {
    return false;
  }

  final response = await _recordingPartsApi.fetchPart(
    recordingPart.backendRecordingId!,
    recordingPart.BEId!,
  );

  if (response.statusCode == 200) {
    logger.i(
        'Recording part id: ${recordingPart.id} found on backend, marking as sent.');
    final Directory tempDir = await getApplicationDocumentsDirectory();
    final String partFilePath =
        '${tempDir.path}/recording_${recordingPart.backendRecordingId}_${recordingPart.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
    final File file = await File(partFilePath).create();
    final dynamic data = response.data;
    if (data is List<int>) {
      await file.writeAsBytes(data);
    } else if (data is String) {
      await file.writeAsString(data);
    } else {
      await file.writeAsString(data.toString());
    }
    recordingPart.sent = true;
    recordingPart.sending = false;
    await DatabaseNew.updateRecordingPart(recordingPart);
  }

  return true;
}

Future<void> _sendRecordingPart(RecordingPart recordingPart) async {
  if (recordingPart.id != null &&
      DatabaseNew._inflightPartIds.contains(recordingPart.id)) {
    logger.i(
        'sendRecordingPart: part ${recordingPart.id} already in-flight. Skipping.');
    return;
  }

  recordingPart.sending = true;
  await DatabaseNew.updateRecordingPart(recordingPart);

  try {
    if (recordingPart.dataBase64 == null) {
      throw UploadException('Recording part data is null', 410);
    }
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw UploadException('Failed to send recording part to backend', 401);
    }

    logger.i(
        'Uploading recording part (backendRecordingId: ${recordingPart.backendRecordingId}) with data length: ${recordingPart.dataBase64?.length}');

    try {
      final Map<String, Object?> jsonBody = recordingPart.toBEJson();
      final response =
          await _recordingPartsApi.uploadRecordingPartJson(jsonBody);

      if (response.statusCode == 200) {
        logger.i(response.data);
        final dynamic responseBody = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final int returnedId = responseBody is int
            ? responseBody
            : int.tryParse('$responseBody') ?? 0;
        recordingPart.BEId = returnedId;
        recordingPart.sent = true;
        recordingPart.sending = false;
        await DatabaseNew.updateRecordingPart(recordingPart);
        final SendPort? port =
            IsolateNameServer.lookupPortByName('upload_progress_port');
        if (port != null && recordingPart.id != null) {
          port.send(['done', recordingPart.id!]);
        }
        logger
            .i('Recording part id: ${recordingPart.id} uploaded successfully.');
      } else {
        recordingPart.sending = false;
        await DatabaseNew.updateRecordingPart(recordingPart);
        throw UploadException('Failed to upload part id: ${recordingPart.id}',
            response.statusCode ?? 500);
      }
    } catch (e) {
      recordingPart.sending = false;
      await DatabaseNew.updateRecordingPart(recordingPart);
      rethrow;
    }
  } catch (e, stackTrace) {
    if (e is PathNotFoundException) {
      logger.e('Path not found for recording part id: ${recordingPart.id}',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recordingPart.sending = false;
      await DatabaseNew.updateRecordingPart(recordingPart);
      rethrow;
    }

    logger.e('Error uploading part: $e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    recordingPart.sending = false;
    await DatabaseNew.updateRecordingPart(recordingPart);
    rethrow;
  }
}

Future<void> _sendRecordingPartNew(RecordingPart recordingPart,
    {UploadProgress? onProgress}) async {
  if (recordingPart.id == null) {
    logger.w('sendRecordingPartNew: part has null id, aborting.');
    return;
  }
  if (recordingPart.sent == true) {
    logger.i(
        'sendRecordingPartNew: part ${recordingPart.id} already sent. Skipping.');
    return;
  }
  if (recordingPart.sending == true ||
      DatabaseNew._inflightPartIds.contains(recordingPart.id)) {
    logger.i(
        'sendRecordingPartNew: part ${recordingPart.id} already in-flight. Skipping.');
    return;
  }

  DatabaseNew._inflightPartIds.add(recordingPart.id!);
  recordingPart.sending = true;
  await DatabaseNew.updateRecordingPart(recordingPart);

  try {
    if (recordingPart.path == null) {
      throw UploadException('Recording part data is null', 410);
    }
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw UploadException('Failed to send recording part to backend', 401);
    }

    logger.i(
        'Uploading recording part (backendRecordingId: ${recordingPart.backendRecordingId}) with data length: ${recordingPart.dataBase64?.length}');
    void reportUploadProgress(int sent, int total, {bool redirected = false}) {
      if (total > 0) {
        logger.i(
            'Upload progress${redirected ? ' (redirect)' : ''}: $sent / $total (${(sent / total * 100).toStringAsFixed(1)}%)');
      } else {
        logger.i(
            'Upload progress${redirected ? ' (redirect)' : ''}: $sent bytes');
      }
      UploadProgressBus.update(recordingPart.id!, sent, total);
      if (onProgress != null) {
        onProgress(sent, total);
      }

      final SendPort? port =
          IsolateNameServer.lookupPortByName('upload_progress_port');
      if (port == null) {
        logger.w(
            '[UploadBridge] lookupPortByName("upload_progress_port") returned NULL - likely a background isolate cannot see the UI port. partId=${recordingPart.id}, sent=$sent, total=$total');
      } else {
        logger.i(
            '[UploadBridge] sending progress to UI port: partId=${recordingPart.id}, sent=$sent, total=$total');
        port.send(['update', recordingPart.id!, sent, total]);
      }
    }

    Response response = await _recordingPartsApi.uploadRecordingPartMultipart(
      filePath: recordingPart.path!,
      backendRecordingId: recordingPart.backendRecordingId,
      startDate: recordingPart.startTime,
      endDate: recordingPart.endTime,
      gpsLatitudeStart: recordingPart.gpsLatitudeStart,
      gpsLatitudeEnd: recordingPart.gpsLatitudeEnd,
      gpsLongitudeStart: recordingPart.gpsLongitudeStart,
      gpsLongitudeEnd: recordingPart.gpsLongitudeEnd,
      onSendProgress: (sent, total) => reportUploadProgress(sent, total),
    );

    if (response.statusCode != null &&
        response.statusCode! >= 300 &&
        response.statusCode! < 400) {
      final String? loc = response.headers.value('location');
      if (loc != null && loc.isNotEmpty) {
        final String initialUrl = Uri(
          scheme: 'https',
          host: Config.host,
          path: '/recordings/part-new',
        ).toString();
        final String redirectedUrl = Uri.parse(loc).isAbsolute
            ? loc
            : Uri.parse(initialUrl).resolve(loc).toString();
        logger.w(
            'Multipart POST received ${response.statusCode} redirect -> $redirectedUrl. Retrying with fresh FormData.');

        response = await _recordingPartsApi.uploadRecordingPartMultipart(
          filePath: recordingPart.path!,
          backendRecordingId: recordingPart.backendRecordingId,
          startDate: recordingPart.startTime,
          endDate: recordingPart.endTime,
          gpsLatitudeStart: recordingPart.gpsLatitudeStart,
          gpsLatitudeEnd: recordingPart.gpsLatitudeEnd,
          gpsLongitudeStart: recordingPart.gpsLongitudeStart,
          gpsLongitudeEnd: recordingPart.gpsLongitudeEnd,
          overrideUrl: redirectedUrl,
          onSendProgress: (sent, total) =>
              reportUploadProgress(sent, total, redirected: true),
        );
      }
    }

    if (response.statusCode == 200) {
      logger.i(response.data);
      final int returnedId = response.data is int
          ? response.data
          : (response.data is String ? int.parse(response.data) : 0);
      recordingPart.BEId = returnedId;
      recordingPart.sent = true;
      recordingPart.sending = false;
      UploadProgressBus.markDone(recordingPart.id!);
      final SendPort? port =
          IsolateNameServer.lookupPortByName('upload_progress_port');
      if (port == null) {
        logger.w(
            '[UploadBridge] done: UI port not found; cannot notify UI isolate. partId=${recordingPart.id}');
      } else {
        logger.i(
            '[UploadBridge] done: notifying UI isolate for partId=${recordingPart.id}');
        port.send(['done', recordingPart.id!]);
      }
      await DatabaseNew.updateRecordingPart(recordingPart);
      logger.i('Recording part id: ${recordingPart.id} uploaded successfully.');
    } else {
      recordingPart.sending = false;
      UploadProgressBus.clear(recordingPart.id ?? -1);
      await DatabaseNew.updateRecordingPart(recordingPart);
      throw UploadException('Failed to upload part id: ${recordingPart.id}',
          response.statusCode!);
    }
  } catch (e, stackTrace) {
    if (e is PathNotFoundException) {
      logger.e('Path not found for recording part id: ${recordingPart.id}',
          error: e, stackTrace: stackTrace);
      Sentry.captureException(e, stackTrace: stackTrace);
      recordingPart.sending = false;
      UploadProgressBus.clear(recordingPart.id ?? -1);
      await DatabaseNew.updateRecordingPart(recordingPart);
      rethrow;
    }

    logger.e('Error uploading part: $e', error: e, stackTrace: stackTrace);
    Sentry.captureException(e, stackTrace: stackTrace);
    recordingPart.sending = false;
    await DatabaseNew.updateRecordingPart(recordingPart);
    rethrow;
  } finally {
    if (recordingPart.id != null) {
      DatabaseNew._inflightPartIds.remove(recordingPart.id);
    }
  }
}

Future<void> _updateRecordingBE(Recording recording) async {
  if (recording.BEId == null) {
    logger.w('Cannot update recording on backend because BEId is null.');
    return;
  }

  final String? jwt = await FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    throw UploadException('Failed to update recording on backend', 401);
  }

  final response = await _recordingsApi.updateRecording(
    recording.BEId!,
    <String, Object?>{
      'name': recording.name,
      'note': recording.note,
      'estimatedBirdsCount': recording.estimatedBirdsCount,
      'device': recording.device,
    },
  );

  if (response.statusCode == 200) {
    logger
        .i('Recording BEId ${recording.BEId} successfully updated on backend.');
    await DatabaseNew.updateRecording(recording);
  } else {
    throw UploadException(
      'Failed to update recording on backend',
      response.statusCode ?? 500,
    );
  }
}

Future<void> _fetchRecordingsFromBE() async {
  DatabaseNew.fetching = true;
  try {
    final String? jwt = await FlutterSecureStorage().read(key: 'token');
    if (jwt == null) {
      throw FetchException('Failed to fetch recordings from backend', 401);
    }

    final String? userId = await FlutterSecureStorage().read(key: 'userId');
    if (userId == null) {
      throw FetchException(
          'Failed to fetch recordings from backend: userId not found', 401);
    }

    final response = await _recordingsApi.fetchRecordingsForUser(userId);

    if (response.statusCode == 200) {
      final dynamic decoded = response.data is String
          ? json.decode(response.data as String)
          : response.data;
      final List<dynamic> body = decoded as List<dynamic>;
      final List<Recording> recordings =
          List<Recording>.generate(body.length, (i) {
        return Recording.fromBEJson(body[i], null);
      });
      final List<RecordingPart> parts = <RecordingPart>[];

      for (int i = 0; i < body.length; i++) {
        for (int j = 0; j < body[i]['parts'].length; j++) {
          final RecordingPart part =
              RecordingPart.fromBEJson(body[i]['parts'][j], body[i]['id']);
          parts.add(part);
          logger.i('Added part with ID: ${part.id} and BEID: ${part.BEId}');
        }
      }

      DatabaseNew.fetchedRecordings = recordings;
      DatabaseNew.fetchedRecordingParts = parts;

      final List<Recording> localRecordings = await DatabaseNew.getRecordings();
      final Set<int?> beIds = recordings.map((r) => r.BEId).toSet();

      for (final local in localRecordings) {
        if (local.sent && !beIds.contains(local.BEId)) {
          if (local.id == null) continue;
          final bool hasLocalMedia = local.downloaded ||
              (local.path != null && local.path!.isNotEmpty);
          if (hasLocalMedia) {
            // Keep cached foreign recordings for Settings cache manager,
            // but remove them from "My recordings" scope.
            local.mail = '';
            await DatabaseNew.updateRecording(local);
            logger.i(
                'Recording id ${local.id} detached from current user scope (not found in current user backend list).');
          } else {
            await DatabaseNew.deleteRecordingFromCache(local.id!);
            logger.i(
                'Recording id ${local.id} deleted locally (no longer on backend).');
          }
        }
      }

      for (final beRec in recordings) {
        try {
          final Recording local =
              localRecordings.firstWhere((r) => r.BEId == beRec.BEId);
          final bool needsUpdate = local.name != beRec.name ||
              local.note != beRec.note ||
              local.estimatedBirdsCount != beRec.estimatedBirdsCount ||
              local.device != beRec.device ||
              local.byApp != beRec.byApp;
          if (needsUpdate) {
            local.name = beRec.name;
            local.note = beRec.note;
            local.estimatedBirdsCount = beRec.estimatedBirdsCount;
            local.device = beRec.device;
            local.byApp = beRec.byApp;
            await DatabaseNew.updateRecording(local);
            logger.i('Recording id ${local.id} updated to match backend data.');
          }
        } catch (_) {
          // no local match
        }
      }
    } else if (response.statusCode == 204) {
      logger.i('No recordings found on backend.');
    } else {
      throw FetchException('Failed to fetch recordings from backend',
          response.statusCode ?? 500);
    }
  } finally {
    DatabaseNew.fetching = false;
  }
}

Future<void> _fetchFilteredPartsForRecordingsFromBE(List<Recording> recs,
    {bool verified = false}) async {
  DatabaseNew.fetchedFilteredRecordingParts = <FilteredRecordingPart>[];
  DatabaseNew.fetchedDetectedDialects = <DetectedDialect>[];

  for (final rec in recs) {
    if (rec.BEId == null) continue;
    try {
      final resp = await _filteredRecordingsApi.fetchFilteredParts(
        recordingId: rec.BEId!,
        verified: verified,
      );

      if (resp.statusCode == 200) {
        final dynamic decoded =
            resp.data is String ? json.decode(resp.data as String) : resp.data;
        final List<dynamic> arr = decoded as List<dynamic>;
        for (final item in arr) {
          if (item is! Map) continue;
          final map = item.cast<String, Object?>();
          final frp = FilteredRecordingPart.fromBEJson(map);
          DatabaseNew.fetchedFilteredRecordingParts!.add(frp);

          final dynList = map['detectedDialects'];
          if (dynList is List) {
            for (final d in dynList) {
              if (d is Map) {
                final dd = DetectedDialect.fromBEJson(
                  d.cast<String, Object?>(),
                  parentFilteredPartBEID: frp.BEId ?? 0,
                );
                DatabaseNew.fetchedDetectedDialects!.add(dd);
              }
            }
          }
        }
      } else if (resp.statusCode == 204) {
        // none for this recording
      } else {
        logger.w(
            'Failed to fetch filtered parts for recording ${rec.BEId}: ${resp.statusCode}');
      }
    } catch (e, st) {
      logger.e('Error fetching filtered parts for recording ${rec.BEId}: $e',
          error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }
  }
}

Future<RecordingPart?> _getRecordingPartByBEID(int id) async {
  try {
    final resp = await _recordingsApi.fetchRecordingPartSummary(id);
    if (resp.statusCode == 200) {
      logger.i('sending req was succesfull');
      final dynamic data =
          resp.data is String ? json.decode(resp.data as String) : resp.data;
      return RecordingPart.fromBEJson(data['parts'][0], id);
    }

    logger.i('req failed with statuscode ${resp.statusCode} -> ${resp.data}');
    return null;
  } catch (_) {
    return null;
  }
}

Future<int?> _fetchRecordingFromBE(int id) async {
  final String? jwt = await FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    logger.e('Could not fetch jwt');
    return null;
  }

  final response =
      await _recordingsApi.fetchRecordingById(id, includeParts: true);

  if (response.statusCode != 200) {
    logger.w(
        'Could not download recording ${response.data} | ${response.statusCode}');
  }

  final dynamic decoded = response.data is String
      ? jsonDecode(response.data as String)
      : response.data;
  final Map<String, dynamic> body = (decoded as Map).cast<String, dynamic>();
  final List<dynamic> partsArr = (body['parts'] as List?) ?? const [];
  final List<RecordingPart> parts = partsArr
      .map<RecordingPart>((row) => RecordingPart.fromBEJson(
            (row as Map).cast<String, dynamic>(),
            id,
          ))
      .toList(growable: false);

  final Recording recording = Recording.fromBEJson(body, body['userId']);
  final int localId = await DatabaseNew.insertRecording(recording);

  if (localId > 0) {
    for (final RecordingPart part in parts) {
      part.recordingId = localId;
    }
  }

  final List<Future<void>> tasks = <Future<void>>[];
  for (final RecordingPart part in parts) {
    tasks.add(() async {
      await DatabaseNew.insertRecordingPart(part);
    }());
  }
  await Future.wait(tasks);

  return localId;
}
