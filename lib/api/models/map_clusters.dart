import 'package:strnadi/auth/user_identity.dart';
import 'dart:convert';
import 'package:strnadi/utils/log_redactor.dart';
import 'map_feature_filters.dart';
import 'package:latlong2/latlong.dart';

class MapClustersRequest {
  const MapClustersRequest({
    required this.center,
    required this.zoom,
    required this.viewportWidthPx,
    required this.viewportHeightPx,
    required this.devicePixelRatio,
    required this.dialectMode,
    this.clustered = true,
    this.featureFilters = const MapFeatureFilters(),
    this.ownerScope = 'All',
    this.userId,
    this.createdFrom,
    this.createdTo,
  });
  final LatLng center;
  final double zoom, viewportWidthPx, viewportHeightPx, devicePixelRatio;
  final String dialectMode, ownerScope;
  final bool clustered;
  final MapFeatureFilters featureFilters;
  final Object? userId;
  final DateTime? createdFrom, createdTo;
  Map<String, Object> toQueryParameters() {
    if ((ownerScope != 'All' ||
            featureFilters.hideOthersWithoutMeaningfulDialect) &&
        (userId == null || parseUserId(userId) == null)) {
      throw ArgumentError('An owner filter requires a user id.');
    }
    return {
      'centerLat': center.latitude,
      'centerLng': center.longitude,
      'zoom': zoom,
      'viewportWidthPx': viewportWidthPx.round(),
      'viewportHeightPx': viewportHeightPx.round(),
      'devicePixelRatio': devicePixelRatio,
      'dialectMode': dialectMode,
      'clustered': clustered,
      ...featureFilters.toQueryParameters(),
      'ownerScope': ownerScope,
      if (userId != null) 'userId': userId!,
      if (createdFrom != null) 'createdFrom': _date(createdFrom!),
      if (createdTo != null) 'createdTo': _date(createdTo!),
    };
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class MapBounds {
  const MapBounds(this.north, this.south, this.east, this.west);
  final double north, south, east, west;
  double get longitudeSpan => east >= west ? east - west : 360 + east - west;
  bool get coincident =>
      (north - south).abs() < 0.000001 && longitudeSpan < 0.000001;
  factory MapBounds.fromJson(dynamic value) {
    final j = _object(value);
    final b = MapBounds(
      _number(j, 'north'),
      _number(j, 'south'),
      _number(j, 'east'),
      _number(j, 'west'),
    );
    if (b.south > b.north ||
        b.south < -90 ||
        b.north > 90 ||
        b.east.abs() > 180 ||
        b.west.abs() > 180) {
      throw const FormatException('Invalid map bounds.');
    }
    return b;
  }
}

class MapClusterDialect {
  const MapClusterDialect({
    required this.id,
    required this.code,
    required this.color,
    required this.contributionCount,
    required this.percentage,
  });
  final int id, color, contributionCount;
  final String code;
  final double percentage;
  factory MapClusterDialect.fromJson(dynamic value) {
    final j = _object(value);
    final color = _string(j, 'color');
    final percent = _number(j, 'percentage');
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color) ||
        percent < 0 ||
        percent > 100) {
      throw const FormatException('Invalid dialect color or percentage.');
    }
    return MapClusterDialect(
      id: _positive(j, 'id'),
      code: _string(j, 'dialectCode'),
      color: 0xff000000 | int.parse(color.substring(1), radix: 16),
      contributionCount: _positive(j, 'contributionCount'),
      percentage: percent,
    );
  }
}

class MapClusterItem {
  const MapClusterItem({
    required this.recordingId,
    required this.position,
    required this.source,
    required this.locationPartId,
    required this.locationSource,
    required this.createdAt,
    this.representativePartId,
    this.name,
  });
  final int recordingId, locationPartId;
  final int? representativePartId;
  final LatLng position;
  final String source, locationSource;
  final String? name;
  final DateTime createdAt;
  factory MapClusterItem.fromJson(dynamic value, {bool feature = false}) {
    final j = _object(value);
    final loc = _string(j, 'locationSource');
    final rep = j['representativePartId'];
    final date = DateTime.tryParse(_string(j, 'createdAt'));
    if (!['representative', 'latestPart'].contains(loc) ||
        date == null ||
        (rep != null && (rep is! int || rep <= 0)) ||
        (loc == 'representative' && rep == null) ||
        (loc == 'latestPart' && rep != null) ||
        (j['name'] != null && j['name'] is! String)) {
      throw const FormatException('Invalid recording metadata.');
    }
    return MapClusterItem(
      recordingId: _positive(j, 'recordingId'),
      position: _position(feature ? j : j['position']),
      source: _source(j),
      locationPartId: _positive(j, 'locationPartId'),
      locationSource: loc,
      representativePartId: rep as int?,
      name: j['name'] as String?,
      createdAt: date,
    );
  }
}

class MapCluster {
  const MapCluster({
    required this.id,
    required this.center,
    required this.count,
    required this.dialects,
    required this.items,
    required this.source,
    required this.hasMoreItems,
    this.nextItemsCursor,
    this.bounds,
    this.recording,
  });
  final String id, source;
  final LatLng center;
  final int count;
  final List<MapClusterDialect> dialects;
  final List<MapClusterItem> items;
  final bool hasMoreItems;
  final String? nextItemsCursor;
  final MapBounds? bounds;
  final MapClusterItem? recording;
  bool get isRecording => recording != null;
  factory MapCluster.fromJson(dynamic value) {
    final j = _object(value);
    final kind = _string(j, 'kind');
    if (!['recording', 'cluster'].contains(kind)) {
      throw const FormatException('Unknown feature kind.');
    }
    final dialects = _list(
      j,
      'dialects',
    ).map(MapClusterDialect.fromJson).toList(growable: false);
    if (dialects.isEmpty ||
        dialects.map((d) => d.id).toSet().length != dialects.length ||
        (dialects.fold<double>(0, (s, d) => s + d.percentage) - 100).abs() >
            0.011) {
      throw const FormatException('Invalid dialect aggregates.');
    }
    if (kind == 'recording') {
      final item = MapClusterItem.fromJson(j, feature: true);
      return MapCluster(
        id: 'recording-${item.recordingId}',
        center: item.position,
        count: 1,
        dialects: dialects,
        items: [item],
        source: item.source,
        hasMoreItems: false,
        recording: item,
      );
    }
    final count = _positive(j, 'count');
    final items = _list(
      j,
      'items',
    ).map(MapClusterItem.fromJson).toList(growable: false);
    final more = _boolean(j, 'hasMoreItems');
    final cursor = _cursor(j, more);
    if (count < 2 ||
        items.length != (count < 5 ? count : 5) ||
        more != (count > items.length)) {
      throw const FormatException('Invalid cluster preview.');
    }
    _uniqueItems(items);
    return MapCluster(
      id: _string(j, 'id'),
      center: _position(j),
      count: count,
      dialects: dialects,
      items: items,
      source: _source(j, cluster: true),
      hasMoreItems: more,
      nextItemsCursor: cursor,
      bounds: MapBounds.fromJson(j['bounds']),
    );
  }
}

class MapClusterItemsPage {
  const MapClusterItemsPage({
    required this.clusterId,
    required this.count,
    required this.items,
    required this.hasMoreItems,
    this.nextItemsCursor,
  });
  final String clusterId;
  final int count;
  final List<MapClusterItem> items;
  final bool hasMoreItems;
  final String? nextItemsCursor;
  factory MapClusterItemsPage.fromResponseData(dynamic data) {
    final j = _decode(data);
    final items = _list(
      j,
      'items',
    ).map(MapClusterItem.fromJson).toList(growable: false);
    final more = _boolean(j, 'hasMoreItems');
    if (items.isEmpty || items.length > 50) {
      throw const FormatException('Invalid items page.');
    }
    _uniqueItems(items);
    return MapClusterItemsPage(
      clusterId: _string(j, 'clusterId'),
      count: _positive(j, 'count'),
      items: items,
      hasMoreItems: more,
      nextItemsCursor: _cursor(j, more),
    );
  }
}

class MapClustersResponse {
  const MapClustersResponse({
    required this.features,
    required this.bounds,
    required this.clustered,
    required this.visibleRecordingCount,
  });
  final List<MapCluster> features;
  final MapBounds bounds;
  final bool clustered;
  final int visibleRecordingCount;
  factory MapClustersResponse.fromResponseData(dynamic data) {
    final j = _decode(data);
    final features = _list(
      j,
      'features',
    ).map(MapCluster.fromJson).toList(growable: false);
    final count = j['visibleRecordingCount'];
    final clustered = _boolean(j, 'clustered');
    if (count is! int ||
        count < 0 ||
        features.fold<int>(0, (s, f) => s + f.count) != count ||
        features.map((f) => f.id).toSet().length != features.length ||
        (!clustered && features.any((f) => !f.isRecording))) {
      throw const FormatException('Invalid feature counts.');
    }
    return MapClustersResponse(
      features: features,
      bounds: MapBounds.fromJson(j['bounds']),
      clustered: clustered,
      visibleRecordingCount: count,
    );
  }
}

Map<String, dynamic> _decode(dynamic value) =>
    _object(value is String ? jsonDecode(value) : value);
Map<String, dynamic> _object(dynamic value) =>
    _asMap(value) ?? (throw const FormatException('Expected object.'));
List<dynamic> _list(Map<String, dynamic> j, String key) =>
    j[key] is List ? j[key] as List : throw FormatException('Missing $key.');
String _string(Map<String, dynamic> j, String key) =>
    j[key] is String && (j[key] as String).isNotEmpty
    ? j[key] as String
    : throw FormatException('Invalid $key.');
int _positive(Map<String, dynamic> j, String key) =>
    j[key] is int && (j[key] as int) > 0
    ? j[key] as int
    : throw FormatException('Invalid $key.');
double _number(Map<String, dynamic> j, String key) =>
    j[key] is num && (j[key] as num).isFinite
    ? (j[key] as num).toDouble()
    : throw FormatException('Invalid $key.');
bool _boolean(Map<String, dynamic> j, String key) =>
    j[key] is bool ? j[key] as bool : throw FormatException('Invalid $key.');
LatLng _position(dynamic value) {
  final j = _object(value);
  final lat = _number(j, 'latitude'), lng = _number(j, 'longitude');
  if (lat.abs() > 90 || lng.abs() > 180) {
    throw const FormatException('Invalid coordinates.');
  }
  return LatLng(lat, lng);
}

String _source(Map<String, dynamic> j, {bool cluster = false}) {
  final s = _string(j, 'source');
  if (![
    'confirmed',
    'ai',
    'user',
    'unknown',
    if (cluster) 'mixed',
  ].contains(s)) {
    throw const FormatException('Invalid source.');
  }
  return s;
}

String? _cursor(Map<String, dynamic> j, bool more) {
  if (more) return _string(j, 'nextItemsCursor');
  if (j['nextItemsCursor'] != null) {
    throw const FormatException('Unexpected cursor.');
  }
  return null;
}

void _uniqueItems(List<MapClusterItem> items) {
  if (items.map((i) => i.recordingId).toSet().length != items.length ||
      List.generate(
        items.isNotEmpty ? items.length - 1 : 0,
        (i) => items[i].recordingId >= items[i + 1].recordingId,
      ).any((v) => v)) {
    throw const FormatException('Duplicate items.');
  }
}

/// A bounded, structured summary of a rejected map-clusters request.
///
/// The backend returns an error object with fields such as `error`, `reason`,
/// and `message`. Full response bodies are deliberately not logged because
/// they can become large or gain fields that are unsuitable for telemetry.
class MapClustersApiError {
  const MapClustersApiError({
    required this.statusCode,
    this.error,
    this.reason,
    this.message,
    this.traceId,
  });

  final int? statusCode;
  final String? error;
  final String? reason;
  final String? message;
  final String? traceId;

  factory MapClustersApiError.fromResponse({
    required int? statusCode,
    required dynamic payload,
  }) {
    final Map<String, dynamic>? root = _decodeErrorObject(payload);
    final Map<String, dynamic>? nested = root == null
        ? null
        : _asMap(root['error']) ?? _asMap(root['problem']);
    return MapClustersApiError(
      statusCode: statusCode,
      error: _errorValue(root, nested, const <String>['error', 'code', 'type']),
      reason: _errorValue(root, nested, const <String>['reason', 'title']),
      message: _errorValue(root, nested, const <String>['message', 'detail']),
      traceId: _errorValue(root, nested, const <String>[
        'traceId',
        'requestId',
        'correlationId',
      ]),
    );
  }

  String toLogMessage() {
    final List<String> fields = <String>[
      'status=${statusCode ?? 'unknown'}',
      if (error != null) 'error=$error',
      if (reason != null) 'reason=$reason',
      if (message != null) 'message=$message',
      if (traceId != null) 'traceId=$traceId',
    ];
    return 'map-clusters request failed (${fields.join(', ')})';
  }
}

Map<String, dynamic>? _decodeErrorObject(dynamic payload) {
  if (payload is String) {
    try {
      return _asMap(jsonDecode(payload));
    } on FormatException {
      return null;
    }
  }
  return _asMap(payload);
}

String? _errorValue(
  Map<String, dynamic>? root,
  Map<String, dynamic>? nested,
  List<String> keys,
) {
  for (final Map<String, dynamic>? source in <Map<String, dynamic>?>[
    root,
    nested,
  ]) {
    if (source == null) continue;
    for (final String key in keys) {
      final Object? value = source[key];
      if (value is! String && value is! num && value is! bool) continue;
      final String sanitized = LogRedactor.redactText(
        value.toString(),
      ).replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
      if (sanitized.isNotEmpty) {
        return sanitized.length <= 200
            ? sanitized
            : '${sanitized.substring(0, 197)}...';
      }
    }
  }
  return null;
}

Map<String, dynamic>? _asMap(dynamic value) => value is Map
    ? value.map((dynamic key, dynamic item) => MapEntry(key.toString(), item))
    : null;
