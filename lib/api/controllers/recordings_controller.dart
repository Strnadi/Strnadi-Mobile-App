import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class RecordingsController {
  const RecordingsController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path, {Map<String, dynamic>? queryParameters}) {
    return Uri(
      scheme: 'https',
      host: Config.host,
      path: path,
      queryParameters: queryParameters?.map(
        (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  Future<Response<dynamic>> createRecording(Map<String, Object?> body) {
    return _dio.postUri(
      _uri('/recordings'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> updateRecording(
      int backendRecordingId, Map<String, Object?> body) {
    return _dio.patchUri(
      _uri('/recordings/$backendRecordingId'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> deleteRecording(int backendRecordingId) {
    return _dio.deleteUri(
      _uri('/recordings/$backendRecordingId'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> fetchRecordingsForUser(String userId) {
    return _dio.getUri(
      _uri('/recordings', queryParameters: {
        'parts': 'true',
        'userId': userId,
      }),
      options: Options(contentType: Headers.jsonContentType),
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

  Future<Response<dynamic>> fetchRecordingById(
    int backendRecordingId, {
    bool includeParts = true,
  }) {
    return _dio.getUri(
      _uri('/recordings/$backendRecordingId', queryParameters: {
        'parts': includeParts ? 'true' : 'false',
      }),
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
