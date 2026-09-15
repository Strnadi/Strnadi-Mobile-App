import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/models/map_search_result.dart';

class MapSearchController {
  const MapSearchController({Dio? dio}) : _client = dio;

  final Dio? _client;

  Future<List<MapSearchResult>> search(String query) async {
    final response = await (_client ?? ApiDioClient.instance).getUri<dynamic>(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'cz',
      }),
      options: Options(
        headers: const {
          'User-Agent': 'FlutterMapApp/1.0 (marpecqueur@gmail.com)',
        },
        extra: const {'authRequired': false},
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200) return const [];
    final payload = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;
    if (payload is! List) return const [];
    return payload
        .map(MapSearchResult.fromJson)
        .whereType<MapSearchResult>()
        .toList();
  }
}
