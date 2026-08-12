import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/immutable_upload_file.dart';
import 'package:strnadi/api/post_json_with_redirect.dart';
import 'package:strnadi/config/config.dart';

class RecordingPartsController {
  const RecordingPartsController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? host,
  }) {
    return Uri(
      scheme: 'https',
      host: host ?? Config.host,
      path: path,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  Future<Response<dynamic>> uploadRecordingPartJson(Map<String, Object?> body) {
    return _dio.postUri(
      _uri('/recordings/part-new'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> uploadRecordingPartMultipart({
    required ReplayableUploadFile file,
    required int? backendRecordingId,
    required DateTime startDate,
    required DateTime endDate,
    required double? gpsLatitudeStart,
    required double? gpsLatitudeEnd,
    required double? gpsLongitudeStart,
    required double? gpsLongitudeEnd,
    ProgressCallback? onSendProgress,
    String? overrideUrl,
    String? accessToken,
    String? idempotencyKey,
    String? host,
  }) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromStream(
        file.openRead,
        file.byteLength,
        filename: file.filename,
      ),
      'RecordingId': backendRecordingId,
      'StartDate': startDate.toIso8601String(),
      'EndDate': endDate.toIso8601String(),
      'GpsLatitudeStart': gpsLatitudeStart,
      'GpsLatitudeEnd': gpsLatitudeEnd,
      'GpsLongitudeStart': gpsLongitudeStart,
      'GpsLongitudeEnd': gpsLongitudeEnd,
    });

    final String requestUrl =
        overrideUrl ?? _uri('/recordings/part-new', host: host).toString();

    return _dio.post<dynamic>(
      requestUrl,
      data: formData,
      options: Options(
        contentType: null,
        headers: <String, Object?>{
          'accept-encoding': 'identity',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
        },
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
      ),
      onSendProgress: onSendProgress,
    );
  }

  Future<Response<dynamic>> fetchPart(
    int backendRecordingId,
    int backendPartId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri(
        '/recordings/part/$backendRecordingId/$backendPartId/sound',
        host: host,
      ),
      options: Options(
        responseType: ResponseType.bytes,
        // This legacy sound download can carry a captured token. Never let
        // Dio forward it to a redirect target.
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<List<int>>> downloadPartSound(
    int backendRecordingId,
    int backendPartId, {
    required String accessToken,
    required String host,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return _dio.get<List<int>>(
      _uri(
        '/recordings/part/$backendRecordingId/$backendPartId/sound',
        host: host,
      ).toString(),
      options: Options(
        responseType: ResponseType.bytes,
        headers: <String, Object?>{
          'Authorization': 'Bearer $accessToken',
        },
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (status) => status != null && status < 500,
      ),
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }
}

/// Stages and uploads one immutable recording-part snapshot.
///
/// A single snapshot is retained for both the initial POST and the one allowed
/// same-origin redirect replay. It is disposed after every success or failure.
class RecordingPartMultipartUploader {
  const RecordingPartMultipartUploader({
    this.controller = const RecordingPartsController(),
    this.snapshots = const ImmutableUploadSnapshotFactory(),
    this.onCleanupError,
  });

  final RecordingPartsController controller;
  final ImmutableUploadSnapshotFactory snapshots;
  final void Function(Object error, StackTrace stackTrace)? onCleanupError;

  Future<Response<dynamic>> upload({
    required String filePath,
    required String expectedSha256,
    required int expectedByteLength,
    required int? backendRecordingId,
    required DateTime startDate,
    required DateTime endDate,
    required double? gpsLatitudeStart,
    required double? gpsLatitudeEnd,
    required double? gpsLongitudeStart,
    required double? gpsLongitudeEnd,
    required Future<void> Function() beforePost,
    ProgressCallback? onSendProgress,
    String? accessToken,
    String? idempotencyKey,
    String? host,
  }) async {
    final ImmutableUploadFileSnapshot snapshot = await snapshots.stage(
      sourcePath: filePath,
      expectedSha256: expectedSha256,
      expectedByteLength: expectedByteLength,
      onCleanupError: onCleanupError,
    );

    Response<dynamic>? response;
    Object? uploadError;
    StackTrace? uploadStackTrace;
    try {
      response = await postRebuiltWithSameOriginRedirect(
        operation: 'Recording part upload',
        post: (String? overrideUrl) async {
          // Staging can take long enough for logout, account switch, or
          // environment switch. Recheck immediately before each request leg.
          await beforePost();
          return controller.uploadRecordingPartMultipart(
            file: snapshot,
            backendRecordingId: backendRecordingId,
            startDate: startDate,
            endDate: endDate,
            gpsLatitudeStart: gpsLatitudeStart,
            gpsLatitudeEnd: gpsLatitudeEnd,
            gpsLongitudeStart: gpsLongitudeStart,
            gpsLongitudeEnd: gpsLongitudeEnd,
            onSendProgress: onSendProgress,
            overrideUrl: overrideUrl,
            accessToken: accessToken,
            idempotencyKey: idempotencyKey,
            host: host,
          );
        },
      );
    } catch (error, stackTrace) {
      uploadError = error;
      uploadStackTrace = stackTrace;
    }

    try {
      await snapshot.dispose();
    } catch (error, stackTrace) {
      try {
        onCleanupError?.call(error, stackTrace);
      } catch (_) {
        // Reporting is ancillary too; preserve the HTTP outcome below.
      }
    }

    if (uploadError != null) {
      Error.throwWithStackTrace(uploadError, uploadStackTrace!);
    }
    // Once an HTTP response exists, its body may contain the backend id for a
    // remotely committed part. Never hide that durable outcome behind a
    // best-effort temp-file cleanup failure. The reporter above keeps the
    // operational issue observable.
    return response!;
  }
}
