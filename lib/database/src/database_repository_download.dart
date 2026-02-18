part of 'database_repository.dart';

Future<int?> _downloadRecording(
  int recordingBeId, {
  DownloadProgress? onProgress,
  CancelToken? cancelToken,
}) async {
  Recording? recording =
      await DatabaseNew.getRecordingFromDbById(recordingBeId);
  if (recording == null) {
    recording = await DatabaseNew.getRecordingFromDbByBEId(recordingBeId);
    if (recording == null) {
      await DatabaseNew.fetchRecordingFromBE(recordingBeId);
      recording = await DatabaseNew.getRecordingFromDbByBEId(recordingBeId);
      if (recording == null) {
        throw FetchException(
            'Could not find recording in local db and download if from BE',
            404);
      }
    }
  }

  if (recording.downloaded) return recording.id;

  if (recording.id == null) {
    throw FetchException('Recording has no local ID', 500);
  }

  final String? jwt = await FlutterSecureStorage().read(key: 'token');
  if (jwt == null) {
    throw FetchException('Failed to fetch recordings from backend', 401);
  }

  final List<RecordingPart> parts =
      await DatabaseNew.getPartsByRecordingId(recording.id!);
  final Directory tempDir = await getApplicationDocumentsDirectory();
  final List<String> paths = <String>[];
  int completedParts = 0;
  double currentPartProgress = 0.0;

  void reportProgress() {
    if (onProgress == null) return;
    if (parts.isEmpty) {
      onProgress(1.0);
      return;
    }
    final double progress =
        ((completedParts + currentPartProgress) / parts.length).clamp(0.0, 1.0);
    onProgress(progress);
  }

  onProgress?.call(0.0);

  for (final part in parts) {
    currentPartProgress = 0.0;
    reportProgress();

    try {
      final Response<List<int>> response =
          await _recordingPartsApi.downloadPartSound(
        recording.BEId!,
        part.BEId!,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            currentPartProgress = (received / total).clamp(0.0, 1.0);
            reportProgress();
          }
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        throw FetchException(
            'Failed to download recording part: /recordings/part/${recording.BEId}/${part.BEId}/sound',
            response.statusCode ?? 500);
      }

      final String partFilePath =
          '${tempDir.path}/recording_${recording.BEId}_${part.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
      final File file = await File(partFilePath).create();
      await file.writeAsBytes(response.data!);

      part.path = partFilePath;
      part.sent = true;
      await DatabaseNew.updateRecordingPart(part);

      paths.add(partFilePath);
      completedParts += 1;
      currentPartProgress = 0.0;
      reportProgress();
    } catch (e, stackTrace) {
      if (e is FetchException) {
        rethrow;
      } else if (e is DioException && e.type == DioExceptionType.cancel) {
        rethrow;
      } else {
        logger.e('Error downloading part BEID: ${part.BEId}: $e',
            error: e, stackTrace: stackTrace);
        Sentry.captureException(e, stackTrace: stackTrace);
        throw FetchException(
            'Error downloading recording part: /recordings/part/${recording.BEId}/${part.BEId}/sound',
            500);
      }
    }
  }

  logger.i('Dowloaded all parts');

  final String outputPath =
      '${tempDir.path}/recording_${recording.BEId}_${DateTime.now().microsecondsSinceEpoch}.wav';
  await concatWavFiles(paths, outputPath);

  recording.path = outputPath;
  recording.downloaded = true;
  await DatabaseNew.updateRecording(recording);

  logger.i(
      'Downloaded recording id: ${recording.BEId}. File saved to: $outputPath');
  onProgress?.call(1.0);
  return recording.id;
}
