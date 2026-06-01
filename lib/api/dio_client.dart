import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/api_logger.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/utils/log_redactor.dart';

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

          final sanitizedHeaders = LogRedactor.redactMap(options.headers);
          final Uri sanitizedUri = LogRedactor.redactUri(options.uri);

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
          final Uri sanitizedUri =
              LogRedactor.redactUri(response.requestOptions.uri);

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
          final Uri sanitizedUri =
              LogRedactor.redactUri(error.requestOptions.uri);

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
}
