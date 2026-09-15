import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/observing_http_client.dart';

/// Uses Flutter Map's cancellation and cache support for public API tiles.
/// TileLayer disposes the provider and its internally owned HTTP client.
NetworkTileProvider createMapTileProvider({
  http.Client? httpClient,
  AppLogger? logger,
  MapCachingProvider? cachingProvider,
}) => _ObservedMapTileProvider(
  ObservingHttpClient(
    RetryClient(httpClient ?? http.Client()),
    logger: logger ?? AppLogger(scope: 'map.tiles'),
    onFailure: (failure) =>
        (Zone.current[_tileLoadKey] as _TileLoadFailures?)?.add(failure),
  ),
  cachingProvider: cachingProvider,
);

final Object _tileLoadKey = Object();

/// Scoped to one actual image load, including its fallback request. This is
/// intentionally not keyed globally by URL: concurrent failures are independent.
class _TileLoadFailures {
  final List<AppFailure> _failures = [];

  void add(AppFailure failure) {
    _failures.add(failure);
    if (_failures.length > 4) _failures.removeAt(0);
  }

  void attach(Object error) {
    if (error is! NetworkImageLoadException) return;
    final endpoint = ApiDiagnostics.sanitizedEndpoint(error.uri);
    for (final failure in _failures.reversed) {
      if (failure.api?.statusCode == error.statusCode &&
          failure.api?.endpoint == endpoint) {
        AppFailureRegistry.attach(error, failure);
        return;
      }
    }
  }
}

/// Keeps Flutter Map's original keys and completers. Only provenance of a
/// transformed HTTP exception is added; decoding and cache behavior stay owned
/// by the original image provider.
class _ObservedTileImageProvider extends ImageProvider<Object> {
  const _ObservedTileImageProvider(this._delegate);

  final ImageProvider<Object> _delegate;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      _delegate.obtainKey(configuration);

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    final failures = _TileLoadFailures();
    return runZoned(() {
      // The decorator forwards the existing provider's protected loader with
      // its original key and decoder, as Flutter's image cache would do.
      // ignore: invalid_use_of_protected_member
      final completer = _delegate.loadImage(key, decode);
      completer.addEphemeralErrorListener((error, stackTrace) {
        failures.attach(error);
        // Flutter treats a returning listener as handling the error. Rethrowing
        // the identical object leaves normal listener/FlutterError handling in
        // place, without adding a listener that keeps the completer alive.
        if (stackTrace != null) Error.throwWithStackTrace(error, stackTrace);
        throw error;
      });
      return completer;
    }, zoneValues: {_tileLoadKey: failures});
  }
}

class _ObservedMapTileProvider extends NetworkTileProvider {
  _ObservedMapTileProvider(this._ownedClient, {super.cachingProvider})
    : super(httpClient: _ownedClient);

  final ObservingHttpClient _ownedClient;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => _ObservedTileImageProvider(
    super.getImageWithCancelLoadingSupport(coordinates, options, cancelLoading),
  );

  @override
  Future<void> dispose() async {
    // Flutter Map leaves externally supplied clients open. This provider owns
    // its observing/retry client, including when the leaf client is injected.
    _ownedClient.close();
    await super.dispose();
  }
}
