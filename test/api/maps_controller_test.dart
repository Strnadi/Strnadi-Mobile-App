import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/controllers/maps_controller.dart';

void main() {
  test('every map style uses the requested API host without a client key', () {
    const controller = MapsController();
    for (final style in MapTileStyle.values) {
      final template = controller.tileUrlTemplate(
        style: style,
        host: 'preprod-api.example.test',
      );
      expect(
        template,
        'https://preprod-api.example.test/map/v1/maptiles/${style.path}/256/{z}/{x}/{y}',
      );
      expect(template, isNot(contains('apikey')));
    }
  });

  test('tile URLs isolate environments and default to outdoor', () {
    const controller = MapsController();
    final production = controller.tileUrlTemplate(host: 'api.example.test');
    final preprod = controller.tileUrlTemplate(host: 'preprod.example.test');
    expect(production, contains('/outdoor/256/{z}/{x}/{y}'));
    expect(production, isNot(preprod));
  });

  test(
    'reverse geocoding proxies anonymously and preserves location labels',
    () async {
      final adapter = _ResponseAdapter(200, {
        'items': [
          {'name': 'Louka u lesa', 'municipality': 'Brno'},
        ],
      });
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);

      final label = await MapsController(
        dio: dio,
      ).reverseGeocode(49.2, 16.6, host: 'preprod-api.example.test');

      expect(label, 'Brno, Louka u lesa');
      final request = adapter.request!;
      expect(request.uri.host, 'preprod-api.example.test');
      expect(request.uri.path, '/map/v1/rgeocode');
      expect(request.uri.queryParameters, {'lat': '49.2', 'lon': '16.6'});
      expect(request.extra['authRequired'], false);
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.followRedirects, false);
    },
  );

  test(
    'unavailable or unrecognizable geocoding does not invent a label',
    () async {
      for (final (status, payload) in <(int, Object)>[
        (404, {'message': 'Not found'}),
        (200, {'items': []}),
        (200, []),
      ]) {
        final dio = Dio()
          ..httpClientAdapter = _ResponseAdapter(status, payload);
        addTearDown(dio.close);
        expect(
          await MapsController(
            dio: dio,
          ).reverseGeocode(49, 16, host: 'api.example.test'),
          isNull,
        );
      }
    },
  );

  test(
    'upstream server errors remain failures for the caller to handle',
    () async {
      final dio = Dio()..httpClientAdapter = _ResponseAdapter(503, {});
      addTearDown(dio.close);
      await expectLater(
        MapsController(
          dio: dio,
        ).reverseGeocode(49, 16, host: 'api.example.test'),
        throwsA(isA<DioException>()),
      );
    },
  );
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.status, this.payload);

  final int status;
  final Object payload;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
