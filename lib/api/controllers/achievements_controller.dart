import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class AchievementsController {
  const AchievementsController();

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

  Future<Response<dynamic>> fetchAll() {
    return _dio.getUri(
      _uri('/achievements'),
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<Response<dynamic>> fetchForUser(int userId) {
    return _dio.getUri(
      _uri('/achievements', queryParameters: <String, int>{
        'userId': userId,
      }),
      options: Options(contentType: Headers.jsonContentType),
    );
  }
}
