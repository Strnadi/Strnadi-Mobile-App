import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/api/map_tile_provider.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/sentry_log_sink.dart';

class _MemoryTransport extends Transport {
  final List<SentryEvent> events = [];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    events.addAll(
      envelope.items
          .map((item) => item.originalObject)
          .whereType<SentryEvent>(),
    );
    return envelope.header.eventId;
  }
}

class _QuietSink implements AppLogSink {
  @override
  void add(AppLogRecord record) {}
}

class _TileClient extends http.BaseClient {
  _TileClient(this.statuses);

  final List<int> statuses;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final status = statuses[calls++];
    await Future<void>.delayed(Duration.zero);
    return http.StreamedResponse(
      status == 200 ? Stream.value([1, 2, 3]) : const Stream.empty(),
      status,
      request: request,
    );
  }
}

// TileLayer supplies URL configuration only. Avoid its unrelated default client.
class _ConfigurationTileProvider extends TileProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Hub hub;
  late _MemoryTransport transport;
  late AppLogger logger;
  late FlutterExceptionHandler? originalErrorHandler;
  late List<FlutterErrorDetails> reports;
  late Completer<void> firstReport;
  late TileLayer layer;
  final providers = <NetworkTileProvider>[];
  const coordinates = TileCoordinates(1, 2, 3);

  setUp(() {
    layer = TileLayer(
      urlTemplate: 'https://api.test/tiles/{z}/{x}/{y}.png',
      tileProvider: _ConfigurationTileProvider(),
    );
    originalErrorHandler = FlutterError.onError;
    reports = [];
    firstReport = Completer<void>();
    FlutterError.onError = (details) {
      reports.add(details);
      if (!firstReport.isCompleted) firstReport.complete();
    };
    transport = _MemoryTransport();
    final options = SentryOptions()
      ..dsn = 'https://public@example.test/1'
      ..transport = transport
      ..sendClientReports = false;
    hub = Hub(options);
    final sink = SentryLogSink(hub: hub, isAuthorized: () async => true);
    options.beforeSend = sink.beforeSend;
    logger = AppLogger(consoleSink: _QuietSink(), telemetrySink: sink);
  });

  tearDown(() async {
    FlutterError.onError = originalErrorHandler;
    for (final provider in providers) {
      await provider.dispose();
    }
    providers.clear();
    await hub.close();
    AppLogger.configure();
  });

  NetworkTileProvider provider(List<int> statuses) {
    final result = createMapTileProvider(
      httpClient: _TileClient(statuses),
      logger: logger,
      cachingProvider: const DisabledMapCachingProvider(),
    );
    providers.add(result);
    return result;
  }

  Future<ImageStreamCompleter> load(ImageProvider image) async {
    final key = await image.obtainKey(ImageConfiguration.empty);
    // Invoke exactly the loader Flutter's image cache invokes, but independently
    // of its global cache so tests can exercise concurrent loads of one URL.
    // ignore: invalid_use_of_protected_member
    return image.loadImage(key, (buffer, {getTargetSize}) async {
      buffer.dispose();
      throw StateError('Tile decoding failed after a successful response');
    });
  }

  Future<void> captureAutomatic(FlutterErrorDetails report) => hub.captureEvent(
    SentryEvent(
      throwable: ThrowableMechanism(
        Mechanism(type: 'FlutterError', handled: false),
        report.exception,
      ),
    ),
    stackTrace: report.stack,
  );

  for (final status in [404, 500]) {
    test(
      'transformed tile HTTP $status preserves occurrence and event policy',
      () async {
        final image = provider([status]).getImageWithCancelLoadingSupport(
          coordinates,
          layer,
          Completer<void>().future,
        );
        final completer = await load(image);
        // Ephemeral observation must not keep the image or its network load alive.
        // ignore: invalid_use_of_protected_member
        expect(completer.hasListeners, isFalse);
        await firstReport.future;
        expect(reports, hasLength(1));
        final report = reports.single;
        expect(report.exception, isA<NetworkImageLoadException>());
        final failure = AppFailureRegistry.lookup(
          report.exception,
          report.stack,
        );
        expect(failure, isNotNull);
        expect(failure!.api!.statusCode, status);
        expect(failure.expected, status < 500);
        await captureAutomatic(report);
        await AppLogger.flush();
        expect(transport.events, hasLength(status < 500 ? 0 : 1));
      },
    );
  }

  test(
    'concurrent independent loads of the same URI retain separate failures',
    () async {
      final image = provider([500, 500]).getImageWithCancelLoadingSupport(
        coordinates,
        layer,
        Completer<void>().future,
      );
      final bothReported = Completer<void>();
      FlutterError.onError = (details) {
        reports.add(details);
        if (reports.length == 2) bothReported.complete();
      };
      await Future.wait([load(image), load(image)]);
      await bothReported.future;
      expect(reports, hasLength(2));
      final first = AppFailureRegistry.lookup(reports.first.exception)!;
      final second = AppFailureRegistry.lookup(reports.last.exception)!;
      expect(first.id, isNot(second.id));
      expect(first.api!.endpoint, second.api!.endpoint);
      await Future.wait(reports.map(captureAutomatic));
      await AppLogger.flush();
      expect(transport.events, hasLength(2));
    },
  );

  test('decorated providers retain Flutter Map image cache keys', () async {
    final observed = provider([200]);
    final original = NetworkTileProvider(
      httpClient: _TileClient([200]),
      cachingProvider: const DisabledMapCachingProvider(),
    );
    final cancellation = Completer<void>().future;
    final originalKey = await original
        .getImageWithCancelLoadingSupport(coordinates, layer, cancellation)
        .obtainKey(ImageConfiguration.empty);
    final observedKey = await observed
        .getImageWithCancelLoadingSupport(coordinates, layer, cancellation)
        .obtainKey(ImageConfiguration.empty);
    expect(observedKey, originalKey);
    expect(observedKey.runtimeType, originalKey.runtimeType);
    await original.dispose();
  });

  test(
    'an existing image error handler remains responsible for handling errors',
    () async {
      final image = provider([404]).getImageWithCancelLoadingSupport(
        coordinates,
        layer,
        Completer<void>().future,
      );
      final completer = await load(image);
      final handled = Completer<Object>();
      final listener = ImageStreamListener(
        (_, _) {},
        onError: (error, stack) {
          handled.complete(error);
        },
      );
      completer.addListener(listener);
      final error = await handled.future;
      expect(reports, isEmpty);
      expect(AppFailureRegistry.lookup(error)!.expected, isTrue);
      completer.removeListener(listener);
      await AppLogger.flush();
      expect(transport.events, isEmpty);
    },
  );

  test(
    'successful fallback decoding failures do not inherit an earlier 404',
    () async {
      final fallbackLayer = TileLayer(
        urlTemplate: 'https://api.test/tiles/{z}/{x}/{y}.png',
        fallbackUrl: 'https://api.test/fallback/{z}/{x}/{y}.png',
        tileProvider: _ConfigurationTileProvider(),
      );
      final image = provider([404, 200]).getImageWithCancelLoadingSupport(
        coordinates,
        fallbackLayer,
        Completer<void>().future,
      );
      await load(image);
      await firstReport.future;
      expect(reports.single.exception, isA<StateError>());
      expect(AppFailureRegistry.lookup(reports.single.exception), isNull);
      await captureAutomatic(reports.single);
      await AppLogger.flush();
      expect(transport.events, hasLength(1));
    },
  );
}
