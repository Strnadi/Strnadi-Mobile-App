import 'dart:async';
import 'dart:convert';

import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/telemetry_consent.dart';
import 'package:strnadi/utils/log_redactor.dart';

const appSentryDsn =
    'https://b1b107368f3bf10b865ea99f191b2022@o4508834111291392.ingest.de.sentry.io/4508834113519696';

/// Receives sanitized records; original exceptions stay in local hint metadata
/// for deduplication and are never passed to Sentry's exception serializer.
class SentryLogSink implements AppLogSink {
  SentryLogSink({
    Hub? hub,
    Future<bool> Function()? isAuthorized,
    DateTime Function()? clock,
  }) : _hub = hub ?? HubAdapter(),
       _isAuthorized = isAuthorized ?? TelemetryConsent.instance.isAuthorized,
       _clock = clock ?? DateTime.now;

  static const _failureHint = 'strnadi.log.failure';
  static const _exceptionTypeHint = 'strnadi.log.exception_type';
  static final Expando<String> _capturedStacks = Expando(
    'Sentry failure stack',
  );
  static final Expando<List<_AutomaticOccurrence>> _automaticOccurrences =
      Expando('automatic Sentry occurrences');
  static const _automaticDuplicateWindow = Duration(seconds: 1);
  final Hub _hub;
  final Future<bool> Function() _isAuthorized;
  final DateTime Function() _clock;

  /// One policy shared by foreground initialization and task-owned Dart hubs.
  /// SDK hash-only deduplication runs before beforeSend and cannot distinguish
  /// repeated throws of a const exception at separate sites.
  void configureOptions(SentryOptions options) {
    options
      ..enableDeduplication = false
      ..enablePrintBreadcrumbs = false
      ..beforeSend = beforeSend
      ..beforeSendTransaction = beforeSendTransaction
      ..beforeBreadcrumb = beforeBreadcrumb;
  }

  @override
  FutureOr<void> add(AppLogRecord record) {
    // Widget builds can emit thousands of routine trace/debug records. Keep
    // those in the console without starting platform reads or pending futures.
    // Failures remain diagnostic even when the caller chose a low log level.
    if (record.level == AppLogLevel.off ||
        (record.failure == null &&
            record.level.index < AppLogLevel.info.index)) {
      return null;
    }
    return _add(record);
  }

  Future<void> _add(AppLogRecord record) async {
    if (!await _isAuthorized()) return;
    final data = <String, Object?>{
      ...record.context,
      if (record.reason != null) 'reason': record.reason,
      if (record.exceptionType != null) 'exception_type': record.exceptionType,
      if (record.errorDescription != null)
        'error_description': record.errorDescription,
      if (record.stackTraceOrigin != null)
        'stack_trace_origin': record.stackTraceOrigin,
    };
    final failure = record.failure;
    final report = failure != null
        ? !failure.expected && record.level.index >= AppLogLevel.warning.index
        : record.level.index >= AppLogLevel.error.index;
    if (report && record.level != AppLogLevel.off) {
      final hint = Hint.withMap({
        _failureHint: ?failure,
        _exceptionTypeHint: record.exceptionType ?? 'ApplicationError',
      });
      await _hub.captureEvent(
        SentryEvent(
          timestamp: record.timestamp,
          logger: record.scope,
          level: _level(record.level),
          message: SentryMessage(LogRedactor.redactText(record.message)),
          throwable: _SanitizedLogException(
            LogRedactor.redactText(
              record.errorDescription ?? record.reason ?? record.message,
            ),
          ),
          contexts: Contexts()..['app_log'] = LogRedactor.redactMap(data),
          tags: {'log_scope': record.scope},
        ),
        stackTrace: record.stackTrace,
        hint: hint,
      );
    }
    if (record.level != AppLogLevel.off) {
      await _hub.addBreadcrumb(
        Breadcrumb(
          timestamp: record.timestamp,
          category: record.scope,
          level: _level(record.level),
          message: LogRedactor.redactText(record.message),
          data: LogRedactor.redactMap(data),
        ),
      );
    }
  }

  /// Also protects automatically collected Flutter and uncaught exceptions.
  Future<SentryEvent?> beforeSend(SentryEvent event, Hint hint) async {
    try {
      if (event is SentryTransaction) {
        return await beforeSendTransaction(event, hint);
      }
      return await _prepareEvent(event, hint);
    } catch (_) {
      // The SDK otherwise keeps the original event when this hook throws.
      return null;
    }
  }

  /// Preserve the SDK's transaction instance, including its tracer and profile
  /// association. Returning a plain SentryEvent would break SDK transaction send.
  Future<SentryTransaction?> beforeSendTransaction(
    SentryTransaction transaction,
    Hint hint,
  ) async {
    try {
      if (!await _isAuthorized()) return null;
      final safe = _sanitizeEvent(transaction, hint);
      safe.contexts.trace?.sampled = transaction.contexts.trace?.sampled;
      transaction
        ..modules = safe.modules
        ..tags = safe.tags
        ..fingerprint = safe.fingerprint
        ..breadcrumbs = safe.breadcrumbs
        ..exceptions = safe.exceptions
        ..threads = safe.threads
        ..sdk = safe.sdk
        ..platform = safe.platform
        ..logger = safe.logger
        ..serverName = safe.serverName
        ..release = safe.release
        ..dist = safe.dist
        ..environment = safe.environment
        ..message = safe.message
        ..transaction = safe.transaction
        ..level = safe.level
        ..culprit = safe.culprit
        ..user = safe.user
        ..contexts = safe.contexts
        ..request = safe.request
        ..debugMeta = safe.debugMeta;
      // The SDK serializes legacy tracer data as extra on transactions.
      // ignore: deprecated_member_use
      transaction.extra = safe.extra;
      for (final span in transaction.spans) {
        final safeData = _sanitizeValue(span.data) as Map<String, dynamic>;
        final safeTags = (_sanitizeValue(span.tags) as Map<String, dynamic>)
            .cast<String, String>();
        span.data
          ..clear()
          ..addAll(safeData);
        span.tags
          ..clear()
          ..addAll(safeTags);
        span.context.operation = LogRedactor.redactText(span.context.operation);
        final description = span.context.description;
        if (description != null) {
          span.context.description = LogRedactor.redactText(description);
        }
        final origin = span.origin;
        if (origin != null) span.origin = LogRedactor.redactText(origin);
        final contextOrigin = span.context.origin;
        if (contextOrigin != null) {
          span.context.origin = LogRedactor.redactText(contextOrigin);
        }
      }
      return transaction;
    } catch (_) {
      return null;
    }
  }

  Future<SentryEvent?> _prepareEvent(SentryEvent event, Hint hint) async {
    if (!await _isAuthorized()) return null;
    final hintedFailure = hint.get(_failureHint);
    var failure = hintedFailure is AppFailure
        ? hintedFailure
        : AppFailureRegistry.lookup(event.throwable);
    final stackSignature = _stackSignature(event);
    if (hintedFailure is! AppFailure &&
        failure != null &&
        failure.api == null) {
      final previousStack = _capturedStacks[failure];
      if (previousStack != null && previousStack != stackSignature) {
        // A const exception can be thrown again at a different call site.
        // Its old occurrence must not suppress the new uncaught failure.
        failure = null;
      }
    }
    if (failure != null) {
      if (failure.expected) return null;
      final eventId = event.eventId.toString();
      if (failure.telemetryClaimed && failure.telemetryEventId != eventId) {
        return null;
      }
      failure.telemetryClaimed = true;
      failure.telemetryEventId = eventId;
      _capturedStacks[failure] = stackSignature;
      final existing = event.contexts['app_log'];
      event.contexts['app_log'] = <String, Object?>{
        if (existing is Map) ...existing.cast<String, Object?>(),
        if (failure.api != null) ...failure.api!.toContext(),
        'reason': failure.reason,
      };
    } else if (_isDuplicateAutomaticEvent(event, stackSignature)) {
      return null;
    }

    return _sanitizeEvent(event, hint);
  }

  static SentryEvent _sanitizeEvent(SentryEvent event, Hint hint) {
    // Reconstruct from the wire representation so no raw throwable survives.
    // Keep stack frames and mechanisms, but omit request bodies and cookies.
    final json = event.toJson();
    final exceptionType = hint.get(_exceptionTypeHint);
    final exceptions = json['exception'];
    if (exceptionType is String && exceptions is Map) {
      final values = exceptions['values'];
      if (values is List && values.isNotEmpty && values.last is Map) {
        (values.last as Map)['type'] = exceptionType;
      }
    }
    final request = json['request'];
    if (request is Map) {
      request.remove('data');
      request.remove('cookies');
      final headers = request['headers'];
      if (headers is Map) {
        request['headers'] = Map.fromEntries(
          headers.entries.where(
            (entry) => const {
              'accept',
              'content-type',
            }.contains(entry.key.toString().toLowerCase()),
          ),
        );
      }
    }
    final safe = _sanitizeValue(json) as Map<String, dynamic>;
    return SentryEvent.fromJson(safe);
  }

  bool _isDuplicateAutomaticEvent(SentryEvent event, String stackSignature) {
    final error = event.throwable;
    if (error == null || error is num || error is String || error is bool) {
      return false;
    }
    final now = _clock();
    final occurrences = _automaticOccurrences[error] ??= [];
    occurrences.removeWhere(
      (entry) => now.difference(entry.observedAt) > _automaticDuplicateWindow,
    );
    final eventId = event.eventId.toString();
    if (occurrences.any(
      (entry) => entry.stack == stackSignature && entry.eventId != eventId,
    )) {
      return true;
    }
    occurrences.add(_AutomaticOccurrence(stackSignature, eventId, now));
    if (occurrences.length > 8) occurrences.removeAt(0);
    return false;
  }

  Breadcrumb? beforeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
    try {
      return breadcrumb == null
          ? null
          : Breadcrumb.fromJson(
              _sanitizeValue(breadcrumb.toJson()) as Map<String, dynamic>,
            );
    } catch (_) {
      return null;
    }
  }

  static String _stackSignature(SentryEvent event) => jsonEncode([
    for (final exception in event.exceptions ?? <SentryException>[])
      for (final frame in exception.stackTrace?.frames ?? <SentryStackFrame>[])
        _frameSignature(frame),
    for (final thread in event.threads ?? <SentryThread>[])
      for (final frame in thread.stacktrace?.frames ?? <SentryStackFrame>[])
        _frameSignature(frame),
  ]);

  static Map<String, Object?> _frameSignature(SentryStackFrame frame) {
    final rawPath = frame.absPath ?? frame.fileName ?? '';
    final uri = Uri.tryParse(rawPath);
    final path =
        uri?.replace(query: '', fragment: '').toString() ??
        rawPath.split('?').first.split('#').first;
    final location = path.startsWith('package:') || path.startsWith('dart:')
        ? path
        : path.replaceAll('\\', '/').split('/').last;
    return {
      'location': LogRedactor.redactText(location),
      'function': LogRedactor.redactText(frame.function ?? ''),
      'line': frame.lineNo,
      'column': frame.colNo,
      'instruction': frame.instructionAddr,
    };
  }

  // Sentry's stack-frame schema is deeper than ordinary log context. Sanitize
  // leaves while preserving its numeric fields and complete frame structure.
  static Object? _sanitizeValue(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): LogRedactor.isSensitiveKey(entry.key.toString())
              ? LogRedactor.redacted
              : _sanitizeValue(entry.value),
      };
    }
    if (value is List) return value.map(_sanitizeValue).toList(growable: false);
    return value is String ? LogRedactor.redactText(value) : value;
  }

  static SentryLevel _level(AppLogLevel level) => switch (level) {
    AppLogLevel.trace || AppLogLevel.debug => SentryLevel.debug,
    AppLogLevel.info || AppLogLevel.off => SentryLevel.info,
    AppLogLevel.warning => SentryLevel.warning,
    AppLogLevel.error => SentryLevel.error,
    AppLogLevel.fatal => SentryLevel.fatal,
  };
}

class _SanitizedLogException implements Exception {
  const _SanitizedLogException(this.description);
  final String description;

  @override
  String toString() => description;
}

class _AutomaticOccurrence {
  const _AutomaticOccurrence(this.stack, this.eventId, this.observedAt);
  final String stack;
  final String eventId;
  final DateTime observedAt;
}
