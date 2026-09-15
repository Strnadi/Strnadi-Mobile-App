import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:strnadi/api/controllers/map_search_controller.dart';

void main() {
  test(
    'search preserves Nominatim parameters and validates result coordinates',
    () async {
      final adapter = _SearchAdapter(200, [
        {'display_name': 'Brno', 'lat': '49.2', 'lon': '16.6'},
        {'display_name': 'Outside latitude', 'lat': '91', 'lon': '16.6'},
        {'display_name': 'Outside longitude', 'lat': '49.2', 'lon': '181'},
        {'display_name': 'Not finite', 'lat': 'NaN', 'lon': '16.6'},
        {'display_name': '', 'lat': '49.2', 'lon': '16.6'},
        {'display_name': 'Missing coordinates'},
        null,
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);

      final results = await MapSearchController(
        dio: dio,
      ).search('Brno & okolí');

      expect(results, hasLength(1));
      expect(results.single.name, 'Brno');
      expect(results.single.latLng, const LatLng(49.2, 16.6));
      final request = adapter.request!;
      expect(request.uri.host, 'nominatim.openstreetmap.org');
      expect(request.uri.path, '/search');
      expect(request.uri.queryParameters, {
        'q': 'Brno & okolí',
        'format': 'json',
        'limit': '5',
        'countrycodes': 'cz',
      });
      expect(request.headers['User-Agent'], isNotEmpty);
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.extra['authRequired'], false);
    },
  );

  test(
    'non-success responses and non-list payloads do not become results',
    () async {
      for (final (status, payload) in <(int, Object)>[
        (429, {'error': 'Too many requests'}),
        (200, {'unexpected': 'object'}),
        (200, []),
      ]) {
        final dio = Dio()..httpClientAdapter = _SearchAdapter(status, payload);
        addTearDown(dio.close);
        expect(await MapSearchController(dio: dio).search('Brno'), isEmpty);
      }
    },
  );
}

class _SearchAdapter implements HttpClientAdapter {
  _SearchAdapter(this.status, this.payload);

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
