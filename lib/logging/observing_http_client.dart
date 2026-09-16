import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';

/// Observes a request without buffering successful downloads or changing the
/// request object (in particular its abort trigger and redirect policy).
class ObservingHttpClient extends http.BaseClient {
  ObservingHttpClient(this._inner, {AppLogger? logger, this.onFailure})
    : _logger = logger ?? AppLogger(scope: 'http');

  final http.Client _inner;
  final AppLogger _logger;
  final void Function(AppFailure)? onFailure;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final failureObserver = onFailure;
    final observation = HttpRequestObservation(
      method: request.method,
      uri: request.url,
      logger: _logger,
      onFailure: failureObserver == null
          ? null
          : Zone.current.bindUnaryCallback(failureObserver),
    );
    try {
      final response = await _inner.send(request);
      final stream = observation.observeResponse(
        response.stream,
        statusCode: response.statusCode,
        statusMessage: response.reasonPhrase,
        headers: response.headers,
      );
      return response is http.BaseResponseWithUrl
          ? _ObservedResponseWithUrl(
              stream,
              response,
              (response as http.BaseResponseWithUrl).url,
            )
          : _ObservedResponse(stream, response);
    } catch (error, stackTrace) {
      observation.recordTransportFailure(error, stackTrace);
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _inner.close();
  }
}

/// Shared observation for package:http and protected dart:io attachment reads.
/// The consumer owns the stream: observation never subscribes early, drains it,
/// retries a request, or changes cancellation/backpressure.
class HttpRequestObservation {
  HttpRequestObservation({
    required this.method,
    required this.uri,
    required this.logger,
    this.onFailure,
  });

  final String method;
  final Uri uri;
  final AppLogger logger;
  final void Function(AppFailure)? onFailure;
  final Stopwatch _watch = Stopwatch()..start();
  bool _reportedFailure = false;

  AppFailure _notifyFailure(AppFailure failure) {
    try {
      onFailure?.call(failure);
    } catch (_) {
      // Diagnostic adapters must not alter request or stream behavior.
    }
    return failure;
  }

  void _recordCancellation() {
    if (_reportedFailure) return;
    _reportedFailure = true;
    final diagnostics = ApiDiagnostics.fromResponse(
      method: method,
      uri: uri,
      reason: 'HTTP response stream cancelled',
      durationMs: _watch.elapsedMilliseconds,
      transportType: 'cancelled',
    );
    logger.api(
      diagnostics,
      failure: _notifyFailure(
        AppFailure(
          reason: diagnostics.reason,
          api: diagnostics,
          expected: true,
        ),
      ),
    );
  }

  void recordTransportFailure(Object error, StackTrace stackTrace) {
    if (_reportedFailure) return;
    _reportedFailure = true;
    final cancelled = error is http.RequestAbortedException;
    final expected =
        cancelled ||
        error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException;
    final reason = cancelled
        ? 'HTTP request cancelled'
        : error is TimeoutException
        ? 'HTTP request timed out'
        : 'HTTP connection or response stream failed';
    final diagnostics = ApiDiagnostics.fromResponse(
      method: method,
      uri: uri,
      reason: reason,
      durationMs: _watch.elapsedMilliseconds,
      transportType: cancelled ? 'cancelled' : error.runtimeType.toString(),
    );
    logger.api(
      diagnostics,
      error: error,
      stackTrace: stackTrace,
      failure: _notifyFailure(
        AppFailure(
          reason: reason,
          api: diagnostics,
          expected: expected,
          error: error,
          stackTrace: stackTrace,
        ),
      ),
    );
  }

  Stream<List<int>> observeResponse(
    Stream<List<int>> source, {
    required int statusCode,
    String? statusMessage,
    Map<String, String> headers = const {},
    bool treatRedirectsAsFailure = false,
  }) {
    final failed =
        statusCode >= 400 || (treatRedirectsAsFailure && statusCode >= 300);
    final prefix = <int>[];

    void reportResponse({Object? error, StackTrace? stackTrace}) {
      if (failed && _reportedFailure) return;
      if (failed) _reportedFailure = true;
      final diagnostics = ApiDiagnostics.fromResponse(
        method: method,
        uri: uri,
        statusCode: statusCode,
        statusMessage: statusMessage,
        durationMs: _watch.elapsedMilliseconds,
        payload: failed ? prefix : null,
        traceId:
            headers['x-correlation-id'] ??
            headers['x-request-id'] ??
            headers['traceparent'],
        reason: treatRedirectsAsFailure && statusCode >= 300 && statusCode < 400
            ? 'Protected attachment redirect was rejected'
            : null,
      );
      logger.api(
        diagnostics,
        error: error,
        stackTrace: stackTrace,
        failure: failed
            ? _notifyFailure(
                AppFailure(
                  reason: diagnostics.reason,
                  api: diagnostics,
                  expected: statusCode < 500,
                  error: error,
                  stackTrace: stackTrace,
                ),
              )
            : null,
      );
    }

    if (!failed) reportResponse();
    late StreamSubscription<List<int>> subscription;
    late StreamController<List<int>> controller;
    var completed = false;
    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          (chunk) {
            if (failed && prefix.length < ApiDiagnostics.maximumBodyBytes) {
              final remaining = ApiDiagnostics.maximumBodyBytes - prefix.length;
              prefix.addAll(chunk.take(remaining));
            }
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            // Preserve an observed HTTP failure if the error body is truncated
            // by a connection failure; otherwise report the transport failure.
            if (failed) {
              reportResponse(error: error, stackTrace: stackTrace);
            } else {
              recordTransportFailure(error, stackTrace);
            }
            controller.addError(error, stackTrace);
          },
          onDone: () {
            completed = true;
            if (failed) reportResponse();
            controller.close();
          },
        );
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () {
        if (failed) {
          reportResponse();
        } else if (!completed) {
          _recordCancellation();
        }
        return subscription.cancel();
      },
    );
    return controller.stream;
  }
}

class _ObservedResponse extends http.StreamedResponse {
  _ObservedResponse(Stream<List<int>> stream, http.StreamedResponse original)
    : super(
        stream,
        original.statusCode,
        contentLength: original.contentLength,
        request: original.request,
        headers: original.headers,
        isRedirect: original.isRedirect,
        persistentConnection: original.persistentConnection,
        reasonPhrase: original.reasonPhrase,
      );
}

class _ObservedResponseWithUrl extends _ObservedResponse
    implements http.BaseResponseWithUrl {
  _ObservedResponseWithUrl(super.stream, super.original, this.url);

  @override
  final Uri url;
}
