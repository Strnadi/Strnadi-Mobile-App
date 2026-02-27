import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class DialectsController {
  const DialectsController();

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

  Future<Response<dynamic>> fetchDialectsForRecording(int recordingId) {
    return _dio.getUri(
      _uri('/dialects', queryParameters: {'recordingId': recordingId}),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> fetchDialectPalette() {
    return _dio.getUri(
      _uri('/recordings/dialects'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
