import 'dart:async';

/// Coalesces overlapping requests into one asynchronous operation.
///
/// The active future is installed before [operation] is invoked, so even a
/// synchronous re-entrant call observes the in-flight work. Failures are
/// delivered to every caller and never leave the gate permanently locked.
class AsyncSingleFlight {
  Future<void>? _inFlight;

  bool get isRunning => _inFlight != null;

  Future<void> run(Future<void> Function() operation) {
    final Future<void>? active = _inFlight;
    if (active != null) return active;

    final Completer<void> completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(_complete(operation, completer));
    return completer.future;
  }

  Future<void> _complete(
    Future<void> Function() operation,
    Completer<void> completer,
  ) async {
    try {
      await operation();
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      if (identical(_inFlight, completer.future)) {
        _inFlight = null;
      }
    }
  }
}
