import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/post_json_with_redirect.dart';
import 'package:strnadi/config/config.dart';

class RecordingsController {
  const RecordingsController();

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

  Future<Response<dynamic>> createRecording(
    Map<String, Object?> body, {
    String? accessToken,
    String? idempotencyKey,
    String? host,
    required Future<void> Function() beforePost,
  }) {
    return postJsonWithSameOriginRedirect(
      dio: _dio,
      uri: _uri('/recordings', host: host),
      body: body,
      headers: <String, Object?>{
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
      beforePost: beforePost,
    );
  }

  Future<Response<dynamic>> updateRecording(
    int backendRecordingId,
    Map<String, Object?> body, {
    String? accessToken,
    String? host,
  }) {
    return _dio.patchUri(
      _uri('/recordings/$backendRecordingId', host: host),
      data: body,
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> deleteRecording(
    int backendRecordingId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.deleteUri(
      _uri('/recordings/$backendRecordingId', host: host),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchRecordingsForUser(
    String userId, {
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri(
        '/recordings',
        host: host,
        queryParameters: {
          'parts': 'true',
          'userId': userId,
        },
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchRecordings({
    String? userId,
    bool includeParts = true,
    bool includeSound = false,
  }) {
    return _dio.getUri(
      _uri('/recordings', queryParameters: <String, Object>{
        'parts': includeParts,
        'sound': includeSound,
        if (userId != null) 'userId': userId,
      }),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> fetchIncompleteRecordings({
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri('/recordings/incomplete', host: host),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchRecordingById(
    int backendRecordingId, {
    bool includeParts = true,
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri(
        '/recordings/$backendRecordingId',
        host: host,
        queryParameters: {
          'parts': includeParts ? 'true' : 'false',
        },
      ),
      options: Options(
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (int? status) => status != null && status < 500,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchRecordingPartSummary(int backendRecordingId) {
    return _dio.getUri(
      _uri('/recordings/$backendRecordingId', queryParameters: {
        'parts': 'true',
        'sound': 'false',
      }),
      options: Options(
        extra: <String, Object>{
          // This endpoint can be called before auth state is settled.
          'authRequired': false,
        },
      ),
    );
  }
}
