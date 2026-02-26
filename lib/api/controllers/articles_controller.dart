import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class ArticlesController {
  const ArticlesController();

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

  Future<Response<dynamic>> fetchArticles() {
    return _dio.getUri(
      _uri('/articles'),
      options: Options(
        headers: const <String, String>{
          'accept': 'application/json',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchArticleCategories({
    bool includeArticles = true,
  }) {
    return _dio.getUri(
      _uri(
        '/articles/categories',
        queryParameters: <String, String>{
          'articles': includeArticles.toString(),
        },
      ),
      options: Options(
        headers: const <String, String>{
          'accept': 'application/json',
        },
      ),
    );
  }

  Future<Response<dynamic>> fetchArticleMarkdown({
    required int articleId,
    required String languageTag,
  }) {
    return _dio.getUri(
      _uri('/articles/$articleId/$languageTag.md'),
      options: Options(
        headers: const <String, String>{
          'accept': 'application/json',
        },
        responseType: ResponseType.bytes,
      ),
    );
  }
}
