import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/api_logger.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/auth/administration/app_administration.dart';
import 'package:strnadi/utils/log_redactor.dart';

class ApiDioClient {
  ApiDioClient._();

  /// Shared URI construction for Tenant and Administration controllers.
  static Uri uri(
    String path, {
    Map<String, dynamic>? queryParameters,
    String? host,
  }) {
    final query =
        queryParameters?.map((key, value) => MapEntry(key, value?.toString()));
    if (Config.usesAdministration && host == Config.administrationHost) {
      return Config.administrationOrigin
          .replace(path: path, queryParameters: query);
    }
    return Uri(
        scheme: 'https',
        host: host ?? Config.host,
        path: path,
        queryParameters: query);
  }

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static final Dio _dio = _createClient();
  static final Dio _authorization = _createClient();
  static Dio _createClient() => Dio(
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
  static bool _authorizationInitialized = false;

  /// Uses the same HTTP setup and sanitized logging, but cannot attach tokens
  /// or enter the authenticated request queue while renewing its credentials.
  static Dio get authorization {
    if (!_authorizationInitialized) {
      _initialize(_authorization, attachCredentials: false);
      _authorizationInitialized = true;
    }
    return _authorization;
  }

  static int _requestCounter = 0;

  static Dio get instance {
    if (!_initialized) {
      _initialize(_dio);
      _initialized = true;
    }
    return _dio;
  }

  static void _initialize(Dio client, {bool attachCredentials = true}) {
    client.interceptors.add(
      QueuedInterceptorsWrapper(
        onRequest: (options, handler) async {
          final int requestId = ++_requestCounter;
          final int startedAt = DateTime.now().millisecondsSinceEpoch;

          options.extra['requestId'] = requestId;
          options.extra['startedAt'] = startedAt;

          bool isBackendRequest = false;
          try {
            isBackendRequest =
                options.uri.origin == Uri.https(Config.host).origin;
          } catch (_) {
            isBackendRequest = false;
          }

          final bool authRequired = attachCredentials &&
              ((options.extra['authRequired'] as bool?) ?? true);
          if (attachCredentials &&
              AppAdministration.enabled &&
              options.headers.containsKey('Authorization') &&
              !isBackendRequest &&
              options.uri.origin != Config.administrationOrigin.origin) {
            handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message:
                    'Credentials cannot be sent outside the active API origins.'));
            return;
          }
          if (AppAdministration.enabled &&
              authRequired &&
              (isBackendRequest ||
                  options.uri.origin == Config.administrationOrigin.origin) &&
              (options.headers.containsKey('Authorization') ||
                  await activatedAuthSessions.capture() != null)) {
            try {
              final supplied = options.headers['Authorization'] as String?;
              final token = await AppAdministration.token(
                capturedToken: supplied?.replaceFirst('Bearer ', ''),
                administration:
                    options.uri.origin == Config.administrationOrigin.origin &&
                        options.uri.path != '/account/profile',
              );
              options.headers['Authorization'] = 'Bearer $token';
              options.followRedirects = false;
              options.extra['activatedSession'] =
                  await activatedAuthSessions.capture();
              options.extra['environment'] = Config.dataEnvironment;
            } catch (_) {
              handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'Authentication is unavailable or changed.',
              ));
              return;
            }
          }
          final bool isAuthEndpoint = options.uri.path.startsWith('/auth');
          final bool shouldAttachToken = authRequired &&
              isBackendRequest &&
              !isAuthEndpoint &&
              !AppAdministration.enabled;

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
        onResponse: (response, handler) async {
          final snapshot = response.requestOptions.extra['activatedSession']
              as ActivatedAuthSessionSnapshot?;
          if (snapshot != null &&
              (response.requestOptions.extra['environment'] !=
                      Config.dataEnvironment ||
                  !await activatedAuthSessions.isCurrent(snapshot))) {
            handler.reject(DioException(
                requestOptions: response.requestOptions,
                type: DioExceptionType.cancel,
                message:
                    'Authentication changed while the request was in flight.'));
            return;
          }
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
            '-> ERROR (${elapsedMs}ms, ${error.type.name})',
            stackTrace: error.stackTrace,
          );
          handler.next(error);
        },
      ),
    );
  }
}
