import 'package:strnadi/logging/api_diagnostics.dart';

/// Implemented by domain errors which retain the observed request failure.
abstract interface class DiagnosticException {
  AppFailure? get logFailure;
}

/// One occurrence, shared by a transport, its translated error, and its callers.
/// Raw [error] is an in-process identity only and must never be serialized.
class AppFailure {
  AppFailure({
    required this.reason,
    this.api,
    this.expected = false,
    this.error,
    this.stackTrace,
    this.stackTraceOrigin,
  }) : id = '${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';

  static int _nextId = 0;
  final String id;
  final String reason;
  final ApiDiagnostics? api;
  final bool expected;
  final Object? error;
  final StackTrace? stackTrace;
  final String? stackTraceOrigin;
  bool telemetryClaimed = false;
  String? telemetryEventId;
}

/// Weakly associates errors with occurrences without retaining recorded data.
/// Stack identity distinguishes repeated throws of the same const exception.
class AppFailureRegistry {
  AppFailureRegistry._();

  static final Expando<List<AppFailure>> _failures = Expando('log failures');

  static bool _supportsWeakIdentity(Object? error) =>
      error != null && error is! num && error is! String && error is! bool;

  static void attach(Object error, AppFailure failure) {
    if (!_supportsWeakIdentity(error)) return;
    final entries = _failures[error] ??= <AppFailure>[];
    if (entries.contains(failure)) return;
    entries.add(failure);
    if (entries.length > 8) entries.removeAt(0);
  }

  static AppFailure? lookup(Object? error, [StackTrace? stackTrace]) {
    if (error is DiagnosticException && error.logFailure != null) {
      return error.logFailure;
    }
    if (!_supportsWeakIdentity(error)) return null;
    final entries = _failures[error!];
    if (entries == null || entries.isEmpty) return null;
    if (stackTrace == null) return entries.last;
    // A transport's provenance survives translated/caller stack boundaries.
    if (entries.last.api != null) return entries.last;
    for (final failure in entries.reversed) {
      if (identical(failure.stackTrace, stackTrace)) {
        return failure;
      }
    }
    return null;
  }
}
