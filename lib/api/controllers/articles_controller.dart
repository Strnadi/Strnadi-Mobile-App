import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/config/config.dart';

class ArticlesController {
  const ArticlesController();

  Dio get _dio => ApiDioClient.instance;
  static const List<String> _articleLanguageFallbackOrder = <String>[
    'en-US',
    'cs-CZ',
  ];

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

  Future<Response<dynamic>> fetchArticleMarkdownWithFallback({
    required int articleId,
    required String preferredLanguageTag,
  }) async {
    final List<String> languageTags = _buildLanguageFallbackChain(
      preferredLanguageTag,
    );

    Response<dynamic>? lastResponse;
    DioException? lastError;
    for (final String languageTag in languageTags) {
      try {
        final Response<dynamic> response = await fetchArticleMarkdown(
          articleId: articleId,
          languageTag: languageTag,
        );
        if (response.statusCode == 200) {
          return response;
        }
        lastResponse = response;
        if (!_canTryNextLanguage(response.statusCode)) {
          return response;
        }
      } on DioException catch (error) {
        if (!_canTryNextLanguage(error.response?.statusCode)) {
          rethrow;
        }
        lastError = error;
        if (error.response != null) {
          lastResponse = error.response;
        }
      }
    }

    if (lastResponse != null) {
      return lastResponse;
    }
    if (lastError != null) {
      throw lastError;
    }
    throw Exception('Failed to fetch article markdown.');
  }

  List<String> _buildLanguageFallbackChain(String preferredLanguageTag) {
    final List<String> result = <String>[];
    final Set<String> seen = <String>{};

    void addTag(String tag) {
      final String normalized = tag.trim();
      if (normalized.isEmpty || !seen.add(normalized)) return;
      result.add(normalized);
    }

    addTag(preferredLanguageTag);
    for (final String fallbackTag in _articleLanguageFallbackOrder) {
      addTag(fallbackTag);
    }
    return result;
  }

  bool _canTryNextLanguage(int? statusCode) {
    return statusCode == 404 || statusCode == null;
  }
}
