import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/api_logger.dart';
import 'package:strnadi/config/config.dart';

class ApiDioClient {
  ApiDioClient._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      validateStatus: (_) => true,
      followRedirects: true,
      maxRedirects: 5,
      headers: const {
        'Accept': 'application/json',
      },
    ),
  );

  static bool _initialized = false;
  static int _requestCounter = 0;

  static const Set<String> _sensitiveQueryKeys = <String>{

  };

  static Dio get instance {
    if (!_initialized) {
      _initialize();
    }
    return _dio;
  }

  static void _initialize() {
    _dio.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final int requestId = ++_requestCounter;
          final int startedAt = DateTime.now().millisecondsSinceEpoch;

          options.extra['requestId'] = requestId;
          options.extra['startedAt'] = startedAt;

          bool isBackendRequest = false;
          try {
            isBackendRequest = options.uri.host == Config.host;
          } catch (_) {
            isBackendRequest = false;
          }

          final bool authRequired =
              (options.extra['authRequired'] as bool?) ?? true;
          final bool isAuthEndpoint = options.uri.path.startsWith('/auth');
          final bool shouldAttachToken =
              authRequired && isBackendRequest && !isAuthEndpoint;

          if (shouldAttachToken &&
              !options.headers.containsKey('Authorization')) {
            final String? token = await _storage.read(key: 'token');
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          final Map<String, dynamic> sanitizedHeaders =
              Map<String, dynamic>.from(options.headers);
          if (sanitizedHeaders.containsKey('Authorization')) {
            //sanitizedHeaders['Authorization'] = '***';
          }

          final Uri sanitizedUri = _sanitizeUri(options.uri);

          apiLogger.i(
              '[API][$requestId] ${options.method} $sanitizedUri | headers=$sanitizedHeaders');
          handler.next(options);
        },
        onResponse: (response, handler) {
          final int? requestId =
              response.requestOptions.extra['requestId'] as int?;
          final int? startedAt =
              response.requestOptions.extra['startedAt'] as int?;
          final int elapsedMs = startedAt == null
              ? -1
              : DateTime.now().millisecondsSinceEpoch - startedAt;
          final Uri sanitizedUri = _sanitizeUri(response.requestOptions.uri);

          apiLogger.i(
              '[API][$requestId] ${response.requestOptions.method} $sanitizedUri '
              '-> ${response.statusCode} (${elapsedMs}ms)');
          handler.next(response);
        },
        onError: (error, handler) {
          final int? requestId =
              error.requestOptions.extra['requestId'] as int?;
          final int? startedAt =
              error.requestOptions.extra['startedAt'] as int?;
          final int elapsedMs = startedAt == null
              ? -1
              : DateTime.now().millisecondsSinceEpoch - startedAt;
          final Uri sanitizedUri = _sanitizeUri(error.requestOptions.uri);

          apiLogger.e(
            '[API][$requestId] ${error.requestOptions.method} $sanitizedUri '
            '-> ERROR (${elapsedMs}ms): ${error.message}',
            error: error,
            stackTrace: error.stackTrace,
          );
          handler.next(error);
        },
      ),
    );

    _initialized = true;
  }

  static Uri _sanitizeUri(Uri uri) {
    if (uri.queryParametersAll.isEmpty) {
      return uri;
    }

    final Map<String, List<String>> redacted = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      final String lowerKey = key.toLowerCase();
      final bool isSensitive = _sensitiveQueryKeys
          .any((sensitiveKey) => lowerKey.contains(sensitiveKey.toLowerCase()));
      redacted[key] = isSensitive ? <String>['***'] : values;
    });

    return uri.replace(queryParameters: null).replace(
          queryParameters: redacted.map(
            (key, values) => MapEntry(key, values.isEmpty ? '' : values.first),
          ),
        );
  }
}
