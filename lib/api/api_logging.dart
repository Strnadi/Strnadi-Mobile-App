import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';

const _failureKey = 'strnadi.logFailure';
const _observedResponseKey = 'strnadi.observedResponse';
int _requestCounter = 0;

/// Preserve the response status even if Dio's JSON decoder rejects its body.
void installApiLogging(Dio client, AppLogger logger) {
  if (client.transformer is! _ObservingTransformer) {
    client.transformer = _ObservingTransformer(client.transformer);
  }
  client.interceptors.add(apiLoggingInterceptor(logger));
}

class _ObservingTransformer extends Transformer {
  _ObservingTransformer(this.delegate);
  final Transformer delegate;

  @override
  Future<String> transformRequest(RequestOptions options) =>
      delegate.transformRequest(options);

  @override
  Future<dynamic> transformResponse(
    RequestOptions options,
    ResponseBody response,
  ) {
    try {
      final headers = Headers.fromMap(response.headers);
      options.extra[_observedResponseKey] = ApiDiagnostics.fromResponse(
        method: options.method,
        uri: options.uri,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        durationMs: _duration(options),
        requestId: options.extra['requestId']?.toString(),
        traceId: _correlationHeader(headers),
      );
    } catch (_) {
      // Observing headers must not replace the decoder's result or failure.
    }
    return delegate.transformResponse(options, response);
  }
}

String? _correlationHeader(Headers headers) =>
    headers['x-request-id']?.firstOrNull ??
    headers['x-correlation-id']?.firstOrNull;

/// Observes outcomes without changing status validation, auth, or retries.
Interceptor apiLoggingInterceptor(AppLogger logger) => InterceptorsWrapper(
  onRequest: (options, handler) {
    options.extra.remove(_failureKey);
    options.extra.remove(_observedResponseKey);
    options.extra['requestId'] = (++_requestCounter).toString();
    options.extra['startedAt'] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  },
  onResponse: (response, handler) {
    try {
      if (response.statusCode == null || response.statusCode! >= 400) {
        final failure = apiFailureForResponse(response);
        logger.api(failure.api!, failure: failure);
      } else {
        logger.api(apiDiagnosticsForResponse(response));
      }
    } catch (_) {
      // Diagnostics must never hide a durable backend upload outcome.
    }
    handler.next(response);
  },
  onError: (error, handler) {
    logApiDioError(logger, error);
    handler.next(error);
  },
);

void logApiDioError(AppLogger logger, DioException error) {
  try {
    final failure = apiFailureForDioError(error);
    logger.api(
      failure.api!,
      error: error,
      stackTrace: error.stackTrace,
      failure: failure,
    );
  } catch (_) {
    // Logging is ancillary to request cancellation/failure delivery.
  }
}

int? _duration(RequestOptions options) {
  final startedAt = options.extra['startedAt'];
  return startedAt is int
      ? (DateTime.now().millisecondsSinceEpoch - startedAt).clamp(0, 1 << 53)
      : null;
}

ApiDiagnostics apiDiagnosticsForResponse(
  Response<dynamic> response, {
  String? reason,
}) => ApiDiagnostics.fromResponse(
  method: response.requestOptions.method,
  uri: response.requestOptions.uri,
  statusCode: response.statusCode,
  payload: response.data,
  statusMessage: response.statusMessage,
  reason: reason,
  durationMs: _duration(response.requestOptions),
  requestId: response.requestOptions.extra['requestId']?.toString(),
  traceId: _correlationHeader(response.headers),
);

/// Returns the same occurrence through HTTP-to-domain exception translation.
/// Calling this on a successful response describes a new protocol failure.
AppFailure apiFailureForResponse(
  Response<dynamic> response, {
  String? reason,
  StackTrace? stackTrace,
  bool? expected,
}) {
  final existing = response.extra[_failureKey];
  if (existing is AppFailure) return existing;
  final api = apiDiagnosticsForResponse(
    response,
    reason:
        reason ??
        ((response.statusCode ?? 500) < 400 ? 'Unexpected API response' : null),
  );
  final failure = AppFailure(
    reason: reason ?? api.reason,
    api: api,
    expected:
        expected ??
        (response.statusCode != null &&
            response.statusCode! >= 400 &&
            response.statusCode! < 500),
    stackTrace: stackTrace ?? StackTrace.current,
    stackTraceOrigin: stackTrace == null ? 'response' : 'exception',
  );
  response.extra[_failureKey] = failure;
  response.requestOptions.extra[_failureKey] = failure;
  return failure;
}

AppFailure apiFailureForHttpResponse(
  http.Response response, {
  String? reason,
  StackTrace? stackTrace,
  bool? expected,
}) {
  final existing = AppFailureRegistry.lookup(response);
  if (existing != null) return existing;
  final api = ApiDiagnostics.fromResponse(
    method: response.request?.method ?? 'UNKNOWN',
    uri: response.request?.url ?? Uri(path: '/unknown'),
    statusCode: response.statusCode,
    payload: response.bodyBytes,
    statusMessage: response.reasonPhrase,
    reason:
        reason ??
        (response.statusCode < 400 ? 'Unexpected API response' : null),
    traceId:
        response.headers['x-request-id'] ??
        response.headers['x-correlation-id'],
  );
  final failure = AppFailure(
    reason: api.reason,
    api: api,
    expected:
        expected ?? (response.statusCode >= 400 && response.statusCode < 500),
    stackTrace: stackTrace ?? StackTrace.current,
    stackTraceOrigin: stackTrace == null ? 'response' : 'exception',
  );
  AppFailureRegistry.attach(response, failure);
  return failure;
}

/// Compatibility bridge for callers using either Dio or package:http APIs.
AppFailure apiFailureForResult(
  Object response, {
  String? reason,
  StackTrace? stackTrace,
  bool? expected,
}) {
  if (response is Response) {
    return apiFailureForResponse(
      response,
      reason: reason,
      stackTrace: stackTrace,
      expected: expected,
    );
  }
  final existing = AppFailureRegistry.lookup(response);
  if (existing != null) return existing;
  if (response is http.Response) {
    return apiFailureForHttpResponse(
      response,
      reason: reason,
      stackTrace: stackTrace,
      expected: expected,
    );
  }
  return AppFailure(
    reason: reason ?? 'Unexpected API result type',
    expected: expected ?? false,
    stackTrace: stackTrace ?? StackTrace.current,
    stackTraceOrigin: stackTrace == null ? 'logger' : 'exception',
  );
}

AppFailure apiFailureForDioError(DioException error, {StackTrace? stackTrace}) {
  final existing = error.requestOptions.extra[_failureKey];
  if (existing is AppFailure) {
    AppFailureRegistry.attach(error, existing);
    return existing;
  }
  final response = error.response;
  final observed = error.requestOptions.extra[_observedResponseKey];
  final AppFailure failure;
  if (response != null && error.type == DioExceptionType.badResponse) {
    failure = apiFailureForResponse(
      response,
      stackTrace: stackTrace ?? error.stackTrace,
    );
  } else if (observed is ApiDiagnostics && (observed.statusCode ?? 0) >= 400) {
    final api = ApiDiagnostics.fromResponse(
      method: error.requestOptions.method,
      uri: error.requestOptions.uri,
      statusCode: observed.statusCode,
      statusMessage: observed.reason,
      durationMs: _duration(error.requestOptions),
      requestId: observed.requestId,
      traceId: observed.traceId,
      transportType: error.type.name,
    );
    failure = AppFailure(
      reason: api.reason,
      api: api,
      expected: observed.statusCode! < 500,
      error: error,
      stackTrace: stackTrace ?? error.stackTrace,
    );
  } else {
    final reason = switch (error.type) {
      DioExceptionType.connectionTimeout => 'Connection to API timed out',
      DioExceptionType.sendTimeout => 'Sending API request timed out',
      DioExceptionType.receiveTimeout => 'Receiving API response timed out',
      DioExceptionType.transformTimeout => 'Decoding API response timed out',
      DioExceptionType.connectionError => 'API connection is unavailable',
      DioExceptionType.cancel => 'API request was cancelled',
      DioExceptionType.badCertificate => 'API certificate validation failed',
      DioExceptionType.badResponse => 'API returned an invalid HTTP response',
      DioExceptionType.unknown =>
        error.error is FormatException
            ? 'API response could not be decoded'
            : 'Unexpected API transport failure',
    };
    final api = ApiDiagnostics.fromResponse(
      method: error.requestOptions.method,
      uri: error.requestOptions.uri,
      statusCode: response?.statusCode,
      payload: response?.data,
      durationMs: _duration(error.requestOptions),
      requestId: error.requestOptions.extra['requestId']?.toString(),
      reason: reason,
      transportType: error.type.name,
    );
    failure = AppFailure(
      reason: reason,
      api: api,
      expected: const {
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.cancel,
      }.contains(error.type),
      error: error,
      stackTrace: stackTrace ?? error.stackTrace,
    );
  }
  error.requestOptions.extra[_failureKey] = failure;
  AppFailureRegistry.attach(error, failure);
  return failure;
}
