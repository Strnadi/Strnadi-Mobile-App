import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class FilteredRecordingsController {
  const FilteredRecordingsController();

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

  Future<Response<dynamic>> fetchFilteredParts({
    int? recordingId,
    bool? verified,
  }) {
    return _dio.getUri(
      _uri('/recordings/filtered', queryParameters: {
        if (recordingId != null) 'recordingId': recordingId,
        if (verified != null) 'verified': verified,
      }),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> createFilteredPart(Map<String, dynamic> body) {
    return _dio.postUri(
      _uri('/recordings/filtered'),
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
