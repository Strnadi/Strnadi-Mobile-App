import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class ArticlesController {
  const ArticlesController();

  Dio get _dio => ApiDioClient.instance;

  Uri _uri(String path) {
    return Uri(
      scheme: 'https',
      host: Config.host,
      path: path,
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
