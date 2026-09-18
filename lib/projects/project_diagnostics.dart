import 'dart:async';

import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/telemetry_session.dart';

enum ProjectOperation {
  discover,
  catalog,
  join,
  switchProject,
  restore,
  signIn,
  authorizeProject,
  loadRouting,
  discoverMemberships,
  discoverCatalog,
  joinMembership,
  validateAccess,
  prepareCredential,
  exchangeCredential,
  refreshAdministration,
  loadSelector,
  browseSelector,
  joinSelector,
  switchSelector,
}

enum ProjectEvent {
  discovered,
  catalogLoaded,
  joinRemembered,
  rememberedJoinsLoaded,
  invalidRememberedJoins,
  routingAbsent,
  routingRestored,
  routingRejected,
  recordingBlocked,
  switchAlreadyRunning,
  commitStarted,
  rollbackStarted,
  rollbackCompleted,
  fallbackSelected,
  accessRevoked,
  firstProjectRequired,
  firstProjectChosen,
  loginChoiceRequired,
  loginChoiceSelected,
  selectionRemembered,
  defaultSelected,
  selectorOpened,
  selectorClosed,
  selectorRetry,
  selectorNavigation,
  signedOut,
}

class _ProjectTrace {
  _ProjectTrace(this.id, this.generation);
  final int id;
  final int generation;
}

/// Structural project diagnostics only. Never accepts project/account metadata,
/// URLs, credentials, request bodies or arbitrary exception messages.
class ProjectDiagnostics {
  static final _logger = AppLogger(scope: 'projects');
  static final Object _traceKey = Object();
  static int _sequence = 0;

  static Future<T> run<T>(
    ProjectOperation operation,
    Future<T> Function() action,
  ) {
    final trace = _ProjectTrace(
      ++_sequence,
      TelemetrySession.foreground.generation,
    );
    final parent = Zone.current[_traceKey] as _ProjectTrace?;
    final watch = Stopwatch()..start();
    final context = <String, Object?>{
      'operation': operation.name,
      'operationId': trace.id,
      if (parent?.generation == trace.generation)
        'parentOperationId': parent!.id,
    };
    _logger.d('Project operation started.', context: context);
    return runZoned(() async {
      try {
        final result = await action();
        if (_current(trace)) {
          _logger.i(
            'Project operation completed.',
            context: {...context, 'durationMs': watch.elapsedMilliseconds},
          );
        }
        return result;
      } catch (error, stackTrace) {
        failure(
          operation,
          error,
          stackTrace,
          durationMs: watch.elapsedMilliseconds,
        );
        rethrow;
      }
    }, zoneValues: {_traceKey: trace});
  }

  static bool _current(_ProjectTrace? trace) =>
      trace == null ||
      trace.generation == TelemetrySession.foreground.generation;

  static void event(
    ProjectEvent event, {
    int? count,
    bool afterSessionChange = false,
  }) {
    final trace = afterSessionChange
        ? null
        : Zone.current[_traceKey] as _ProjectTrace?;
    if (!_current(trace)) return;
    _logger.i(
      'Project lifecycle event.',
      context: {
        'event': event.name,
        if (trace != null) 'operationId': trace.id,
        'count': ?count,
      },
    );
  }

  /// Emitted after the activated-session marker commits; do not carry a trace
  /// from the previous telemetry session into the newly activated session.
  static void activated() => _logger.i(
    'Project session activated.',
    context: const {'event': 'sessionActivated'},
  );

  static void failure(
    ProjectOperation operation,
    Object error,
    StackTrace stackTrace, {
    int? durationMs,
    bool afterSessionChange = false,
  }) {
    final trace = afterSessionChange
        ? null
        : Zone.current[_traceKey] as _ProjectTrace?;
    if (!_current(trace)) return;
    final category = error is OAuthFailure
        ? error.kind.name
        : error is StateError &&
              const {
                'projects.recordingBlocked',
                'projects.switchFailed',
                'projects.revoked',
                'projects.empty',
              }.contains(error.message)
        ? error.message
        : 'unexpected';
    final expected = error is OAuthFailure
        ? error.kind != OAuthFailureKind.server &&
              error.kind != OAuthFailureKind.invalidResponse
        : category != 'unexpected';
    final context = <String, Object?>{
      'operation': operation.name,
      'category': category,
      'exceptionType': error.runtimeType.toString(),
      if (trace != null) 'operationId': trace.id,
      'durationMs': ?durationMs,
    };
    // Reuse transport provenance for telemetry deduplication. Unknown exception
    // text is deliberately never passed to AppLogger's string formatter.
    final failure =
        AppFailureRegistry.lookup(error, stackTrace) ??
        AppFailure(
          reason: 'Project operation failed.',
          expected: expected,
          error: error,
          stackTrace: stackTrace,
          stackTraceOrigin: 'exception',
        );
    AppFailureRegistry.attach(error, failure);
    if (expected) {
      _logger.w(
        'Project operation rejected.',
        context: context,
        stackTrace: stackTrace,
        failure: failure,
      );
    } else {
      _logger.e(
        'Project operation failed.',
        context: context,
        stackTrace: stackTrace,
        failure: failure,
      );
    }
  }
}
