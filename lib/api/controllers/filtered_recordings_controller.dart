import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/post_json_with_redirect.dart';
import 'package:strnadi/config/config.dart';

class FilteredRecordingsController {
  const FilteredRecordingsController();

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

  Future<Response<dynamic>> fetchFilteredParts({
    int? recordingId,
    bool? verified,
    String? accessToken,
    String? host,
  }) {
    return _dio.getUri(
      _uri(
        '/recordings/filtered',
        host: host,
        queryParameters: {
          if (recordingId != null) 'recordingId': recordingId,
          if (verified != null) 'verified': verified,
        },
      ),
      options: Options(
        contentType: Headers.jsonContentType,
        followRedirects: false,
        maxRedirects: 0,
        headers: <String, Object?>{
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      ),
    );
  }

  Future<Response<dynamic>> createFilteredPart(
    Map<String, dynamic> body, {
    String? accessToken,
    String? idempotencyKey,
    String? host,
    required Future<void> Function() beforePost,
  }) {
    return postJsonWithSameOriginRedirect(
      dio: _dio,
      uri: _uri('/recordings/filtered', host: host),
      body: body,
      headers: <String, Object?>{
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      },
      beforePost: beforePost,
    );
  }
}
