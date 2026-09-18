import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class AchievementsController {
  const AchievementsController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path, {Map<String, dynamic>? queryParameters}) {
    return ApiDioClient.uri(
      path,
      host: Config.host,
      queryParameters: queryParameters,
    );
  }

  Future<Response<dynamic>> fetchAll() {
    return _dio.getUri(
      _uri('/achievements'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> fetchForUser(Object userId) {
    return _dio.getUri(
      _uri(
        '/achievements',
        queryParameters: <String, Object>{'userId': userId},
      ),
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
