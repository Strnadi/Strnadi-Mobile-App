import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/utils/location_label.dart';

enum MapTileStyle {
  outdoor('outdoor'),
  aerial('aerial'),
  namesOverlay('names-overlay');

  const MapTileStyle(this.path);

  final String path;
}

/// Public map requests go through the active Tenant API, which owns the Mapy key.
class MapsController {
  const MapsController({Dio? dio}) : _client = dio;

  final Dio? _client;

  Dio get _dio => _client ?? ApiDioClient.instance;

  String tileUrlTemplate({
    MapTileStyle style = MapTileStyle.outdoor,
    String? host,
  }) {
    final origin = ApiDioClient.uri(
      '/map/v1/maptiles/${style.path}/256',
      host: host,
    );
    // Append Flutter Map placeholders after URI encoding so braces stay intact.
    return '$origin/{z}/{x}/{y}';
  }

  Future<String?> reverseGeocode(
    double latitude,
    double longitude, {
    String? host,
  }) async {
    final response = await _dio.getUri<dynamic>(
      ApiDioClient.uri(
        '/map/v1/rgeocode',
        host: host,
        queryParameters: {'lat': latitude, 'lon': longitude},
      ),
      options: Options(
        extra: const {'authRequired': false},
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200 && response.statusCode != 201) return null;
    final payload = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    return buildLocationLabel(payload);
  }
}
