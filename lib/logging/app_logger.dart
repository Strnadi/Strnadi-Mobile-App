import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart' as console;
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:strnadi/exceptions.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/log_failure.dart';
import 'package:strnadi/utils/log_redactor.dart';

export 'package:strnadi/logging/log_failure.dart';

enum AppLogLevel { trace, debug, info, warning, error, fatal, off }

class AppLogRecord {
  const AppLogRecord({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.message,
    this.reason,
    this.exceptionType,
    this.errorDescription,
    this.stackTrace,
    this.stackTraceOrigin,
    this.context = const {},
    this.failure,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String scope;
  final String message;
  final String? reason;
  final String? exceptionType;
  final String? errorDescription;
  final StackTrace? stackTrace;
  final String? stackTraceOrigin;
  final Map<String, Object?> context;

  /// Identity/provenance only. Sinks serialize the sanitized fields above.
  final AppFailure? failure;
}

abstract interface class AppLogSink {
  FutureOr<void> add(AppLogRecord record);
}

class _ConsoleSink implements AppLogSink {
  final console.Logger _logger = console.Logger(
    filter: console.ProductionFilter(),
    level: console.Level.trace,
    printer: console.PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 12,
      lineLength: 120,
      colors: false,
      printEmojis: false,
    ),
  );

  @override
  void add(AppLogRecord record) {
    final details = <String, Object?>{
      ...record.context,
      if (record.reason != null) 'reason': record.reason,
      if (record.exceptionType != null) 'exceptionType': record.exceptionType,
      if (record.stackTraceOrigin != null)
        'stackTraceOrigin': record.stackTraceOrigin,
    };
    _logger.log(
      console.Level.values.byName(record.level.name),
      '[${record.scope}] ${record.message}'
      '${details.isEmpty ? '' : ' | $details'}',
      time: record.timestamp,
      error: record.errorDescription,
      stackTrace: record.stackTrace,
    );
  }
}

class _TelemetryContext {
  _TelemetryContext(this.sink);
  final AppLogSink? sink;
  final Set<Future<void>> pending = {};
}

/// Shared console and telemetry boundary. Logging never throws into app code.
class AppLogger {
  AppLogger({
    this.scope = 'app',
    AppLogSink? consoleSink,
    this.telemetrySink,
    this.level = AppLogLevel.trace,
  }) : _consoleSink = consoleSink ?? _defaultConsole;

  final String scope;
  final AppLogLevel level;
  final AppLogSink _consoleSink;
  final AppLogSink? telemetrySink;
  static final AppLogSink _defaultConsole = _ConsoleSink();
  static final Object _telemetryKey = Object();
  static _TelemetryContext _global = _TelemetryContext(null);
  static bool Function() _enabled = () => true;

  static void configure({
    AppLogSink? telemetrySink,
    bool Function()? telemetryEnabled,
  }) {
    _global = _TelemetryContext(telemetrySink);
    _enabled = telemetryEnabled ?? () => true;
  }

  static Future<T> runWithTelemetry<T>(
    AppLogSink? sink,
    Future<T> Function() action,
  ) => runZoned(action, zoneValues: {_telemetryKey: _TelemetryContext(sink)});

  static Future<void> flush({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final context =
        Zone.current[_telemetryKey] as _TelemetryContext? ?? _global;
    try {
      await Future.wait(
        List<Future<void>>.of(context.pending),
      ).timeout(timeout);
    } catch (_) {
      // Delivery is best effort and must not change an upload result.
    }
  }

  void t(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.trace,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );
  void d(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.debug,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );
  void i(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.info,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );
  void w(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );
  void e(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );
  void f(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) => _log(
    AppLogLevel.fatal,
    message,
    error: error,
    stackTrace: stackTrace,
    reason: reason,
    context: context,
    failure: failure,
    expected: expected,
  );

  Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
  }) async {
    e(
      reason ?? 'Operation failed.',
      error: error,
      stackTrace: stackTrace,
      reason: reason,
      context: context,
    );
    await flush();
  }

  void api(
    ApiDiagnostics diagnostics, {
    Object? error,
    StackTrace? stackTrace,
    AppFailure? failure,
  }) {
    final failed =
        failure != null ||
        error != null ||
        (diagnostics.statusCode ?? 0) >= 400;
    if (failed) {
      failure ??= AppFailure(
        reason: diagnostics.reason,
        api: diagnostics,
        error: error,
        stackTrace: stackTrace ?? StackTrace.current,
        stackTraceOrigin: stackTrace == null ? 'response' : 'exception',
        expected:
            diagnostics.statusCode != null &&
            diagnostics.statusCode! >= 400 &&
            diagnostics.statusCode! < 500,
      );
    }
    _log(
      failed
          ? (failure?.expected == true
                ? AppLogLevel.warning
                : AppLogLevel.error)
          : AppLogLevel.info,
      '${diagnostics.method} ${diagnostics.endpoint}',
      error: error,
      stackTrace: stackTrace,
      reason: failed ? diagnostics.reason : null,
      context: diagnostics.toContext(),
      failure: failure,
      expected: failed
          ? (diagnostics.statusCode != null && diagnostics.statusCode! < 500)
          : null,
    );
  }

  void _log(
    AppLogLevel severity,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
    String? reason,
    Map<String, Object?>? context,
    AppFailure? failure,
    bool? expected,
  }) {
    if (level == AppLogLevel.off || severity.index < level.index) return;
    try {
      if (error == null && (message is Exception || message is Error)) {
        error = message;
      }
      failure ??= AppFailureRegistry.lookup(error, stackTrace);
      final failed =
          failure != null ||
          error != null ||
          severity.index >= AppLogLevel.error.index;
      var describedMessage = _describe(message);
      if (error is FormatException || error is DioException) {
        // Legacy callers may interpolate the exception as well as passing it.
        // Replace its serialization before it can expose a parser's source.
        final rawError = _rawDescribe(error);
        if (rawError.isNotEmpty) {
          describedMessage = describedMessage.replaceAll(
            rawError,
            _describe(error),
          );
        }
      }
      final safeMessage = LogRedactor.redactText(describedMessage);
      final caughtStack =
          stackTrace ??
          failure?.stackTrace ??
          (error is Error ? error.stackTrace : null);
      final resolvedStack = caughtStack ?? (failed ? StackTrace.current : null);
      final resolvedReason = failed
          ? LogRedactor.redactText(
              failure?.reason ??
                  reason ??
                  _reasonFromMessage(safeMessage, error),
            )
          : reason == null
          ? null
          : LogRedactor.redactText(reason);
      if (failed && failure == null) {
        failure = AppFailure(
          reason: resolvedReason!,
          expected: expected ?? _isExpected(error, severity),
          error: error,
          stackTrace: resolvedStack,
          stackTraceOrigin: caughtStack == null ? 'logger' : 'exception',
        );
      }
      if (error != null && failure != null) {
        AppFailureRegistry.attach(error, failure);
      }
      final safeContext = LogRedactor.redactMap({
        ...?context,
        if (failure?.api != null) ...failure!.api!.toContext(),
      });
      final record = AppLogRecord(
        timestamp: DateTime.now().toUtc(),
        level: severity,
        scope: LogRedactor.redactText(scope),
        message: safeMessage,
        reason: resolvedReason,
        exceptionType: error?.runtimeType.toString(),
        errorDescription: error == null
            ? null
            : error is DioException
            ? resolvedReason
            : LogRedactor.redactText(_describe(error)),
        stackTrace: LogRedactor.redactStackTrace(resolvedStack),
        stackTraceOrigin: resolvedStack == null
            ? null
            : failure?.stackTraceOrigin ??
                  (caughtStack == null ? 'logger' : 'exception'),
        context: Map<String, Object?>.unmodifiable(safeContext),
        failure: failure,
      );
      final zoneContext = Zone.current[_telemetryKey] as _TelemetryContext?;
      final telemetryContext = zoneContext ?? _global;
      _dispatch(_consoleSink, record, telemetryContext);
      final sink = zoneContext != null
          ? zoneContext.sink
          : telemetrySink ?? (_enabled() ? _global.sink : null);
      if (sink != null) _dispatch(sink, record, telemetryContext);
    } catch (_) {
      // Neither formatting, redaction, nor logging may mask an application error.
    }
  }

  static void _dispatch(
    AppLogSink sink,
    AppLogRecord record,
    _TelemetryContext context,
  ) {
    try {
      final result = sink.add(record);
      if (result is Future) {
        final pending = result.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        context.pending.add(pending);
        unawaited(pending.then((_) => context.pending.remove(pending)));
      }
    } catch (_) {}
  }

  static String _describe(Object? value) {
    if (value is FormatException) {
      return 'FormatException: ${value.message}';
    }
    if (value is DioException) return 'DioException (${value.type.name})';
    return _rawDescribe(value);
  }

  static String _rawDescribe(Object? value) {
    try {
      return value?.toString() ?? '';
    } catch (_) {
      return 'Unprintable ${value.runtimeType}';
    }
  }

  static String _reasonFromMessage(String message, Object? error) {
    final operation = message.split(RegExp(r'[:\n]')).first.trim();
    if (operation.isNotEmpty) return operation;
    return '${error?.runtimeType ?? 'Operation'} failed';
  }

  static bool _isExpected(Object? error, AppLogLevel severity) {
    if (error is RecordingUploadSessionChangedException) return true;
    if (error is DioException) {
      return const {
        DioExceptionType.cancel,
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type);
    }
    if (error is RecordingUploadDeferredException ||
        error is UnsentPartsException ||
        error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException) {
      return true;
    }
    if (error is OAuthFailure) {
      return error.kind != OAuthFailureKind.server &&
          error.kind != OAuthFailureKind.invalidResponse;
    }
    return error == null && severity.index < AppLogLevel.error.index;
  }
}
