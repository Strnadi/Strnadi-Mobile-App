import 'dart:convert';

import 'package:strnadi/utils/log_redactor.dart';

/// Bounded, sanitized API metadata. Never retains request or response bodies.
class ApiDiagnostics {
  const ApiDiagnostics({
    required this.method,
    required this.endpoint,
    required this.reason,
    this.queryParameters = const {},
    this.statusCode,
    this.durationMs,
    this.requestId,
    this.errorCode,
    this.message,
    this.traceId,
    this.transportType,
  });

  final String method;
  final String endpoint;
  final Map<String, List<String>> queryParameters;
  final int? statusCode;
  final int? durationMs;
  final String? requestId;
  final String? errorCode;
  final String reason;
  final String? message;
  final String? traceId;
  final String? transportType;

  static const int maximumBodyBytes = 64 * 1024;
  static const int maximumFieldLength = 200;

  factory ApiDiagnostics.fromResponse({
    required String method,
    required Uri uri,
    int? statusCode,
    Object? payload,
    String? statusMessage,
    int? durationMs,
    String? requestId,
    String? reason,
    String? transportType,
    String? traceId,
  }) {
    // Successful binary downloads must never be inspected or copied for logs.
    final root = statusCode != null && statusCode >= 400
        ? _errorObject(payload)
        : null;
    final nested = root?['error'] is Map
        ? root!['error'] as Map
        : root?['problem'] is Map
        ? root!['problem'] as Map
        : null;
    final sources = <Map?>[root, nested];
    final errorCode = _field(sources, const ['error', 'code', 'type']);
    final errorMessage = _field(sources, const [
      'message',
      'detail',
      'error_description',
    ]);
    final validation = _validationReason(root?['errors'] ?? nested?['errors']);
    return ApiDiagnostics(
      method: _scalar(method) ?? 'UNKNOWN',
      endpoint: sanitizedEndpoint(uri),
      queryParameters: _queryParameters(uri),
      statusCode: statusCode,
      durationMs: durationMs,
      requestId: _scalar(requestId),
      errorCode: errorCode,
      reason:
          _scalar(reason) ??
          _field(sources, const ['reason', 'title']) ??
          errorMessage ??
          validation ??
          errorCode ??
          _scalar(statusMessage) ??
          httpReason(statusCode),
      message: errorMessage ?? validation,
      traceId:
          _field(sources, const ['traceId', 'requestId', 'correlationId']) ??
          _scalar(traceId),
      transportType: _scalar(transportType),
    );
  }

  Map<String, Object?> toContext() => <String, Object?>{
    'method': method,
    'endpoint': endpoint,
    if (queryParameters.isNotEmpty) 'queryParameters': queryParameters,
    if (statusCode != null) 'statusCode': statusCode,
    if (durationMs != null) 'durationMs': durationMs,
    if (requestId != null) 'requestId': requestId,
    if (errorCode != null) 'errorCode': errorCode,
    'reason': reason,
    if (message != null) 'message': message,
    if (traceId != null) 'traceId': traceId,
    if (transportType != null) 'transportType': transportType,
  };

  /// Keep query diagnostics separate so URL sanitization cannot strip them.
  static Map<String, List<String>> _queryParameters(Uri uri) {
    if (uri.query.length > maximumBodyBytes) {
      return const {
        'omitted': ['Query exceeds diagnostic inspection limit'],
      };
    }
    return Map.unmodifiable({
      for (final entry in uri.queryParametersAll.entries.take(50))
        _scalar(entry.key) ?? '[empty key]': List<String>.unmodifiable(
          LogRedactor.isSensitiveKey(entry.key) ||
                  const {
                    'key',
                    'sig',
                    'signature',
                    'cursor',
                  }.contains(entry.key.toLowerCase())
              ? [LogRedactor.redacted]
              : entry.value.take(10).map((value) => _scalar(value) ?? ''),
        ),
    });
  }

  static String sanitizedEndpoint(Uri uri) {
    final safe = LogRedactor.endpoint(uri);
    return safe.length <= maximumFieldLength
        ? safe
        : '${safe.substring(0, maximumFieldLength - 3)}...';
  }

  static String httpReason(int? status) => switch (status) {
    null => 'No HTTP response received',
    400 => 'Bad request',
    401 => 'Authentication required',
    403 => 'Access denied',
    404 => 'Resource not found',
    408 => 'Request timed out',
    409 => 'Request conflicts with current state',
    410 => 'Resource is no longer available',
    422 => 'Request validation failed',
    429 => 'Too many requests',
    500 => 'Internal server error',
    502 => 'Invalid response from upstream server',
    503 => 'Service unavailable',
    504 => 'Upstream server timed out',
    >= 200 && < 300 => 'Request completed',
    >= 300 && < 400 => 'HTTP redirect or cache response',
    _ => 'HTTP request failed',
  };

  static Map? _errorObject(Object? payload) {
    Object? decoded = payload;
    if (payload is List<int>) {
      if (payload.length > maximumBodyBytes) return null;
      try {
        decoded = utf8.decode(payload);
      } on FormatException {
        return null;
      }
    }
    if (decoded is String) {
      if (decoded.length > maximumBodyBytes) return null;
      try {
        decoded = jsonDecode(decoded);
      } on FormatException {
        return null;
      }
    }
    return decoded is Map ? decoded : null;
  }

  static String? _field(List<Map?> sources, List<String> keys) {
    for (final source in sources) {
      if (source == null) continue;
      for (final key in keys) {
        final value = _scalar(source[key]);
        if (value != null) return value;
      }
    }
    return null;
  }

  static String? _validationReason(Object? errors) {
    final values = errors is Map
        ? errors.values.take(3)
        : errors is List
        ? errors.take(3)
        : const <Object>[];
    final messages = <String>[];
    for (final value in values) {
      final items = value is List ? value.take(2) : [value];
      for (final item in items) {
        final message = _scalar(item);
        if (message != null) messages.add(message);
      }
    }
    return _scalar(messages.join('; '));
  }

  static String? _scalar(Object? value) {
    if (value is! String && value is! num && value is! bool) return null;
    final text = value.toString();
    if (text.length > maximumBodyBytes) return null;
    final safe = LogRedactor.redactText(
      text,
    ).replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (safe.isEmpty) return null;
    return safe.length <= maximumFieldLength
        ? safe
        : '${safe.substring(0, maximumFieldLength - 3)}...';
  }
}
