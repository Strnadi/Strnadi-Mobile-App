String? buildLocationLabel(dynamic payload) {
  if (payload is! Map) return null;

  final Map<String, dynamic> data = payload is Map<String, dynamic>
      ? payload
      : Map<String, dynamic>.from(payload);
  final List<dynamic> items = _asList(data['items']);
  final Map<String, dynamic>? primaryItem =
      items.isNotEmpty ? _asMap(items.first) : null;

  final String? placeName =
      _extractText(primaryItem?['name']) ?? _extractText(data['name']);
  final String? municipality =
      _extractMunicipality(primaryItem) ?? _extractMunicipality(data);

  if (municipality != null && placeName != null) {
    if (_normalizeForCompare(municipality) == _normalizeForCompare(placeName)) {
      return municipality;
    }
    return '$municipality, $placeName';
  }

  return municipality ?? placeName;
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  if (value is Map) return <dynamic>[value];
  return const <dynamic>[];
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String? _extractMunicipality(Map<String, dynamic>? source) {
  if (source == null) return null;

  final String? direct = _firstNonEmpty(
    <dynamic>[
      source['municipality'],
      source['city'],
      source['town'],
      source['village'],
      source['villagePart'],
      source['locality'],
    ],
  );
  if (direct != null) return direct;

  final String? regional = _extractMunicipalityFromStructure(
    source['regionalStructure'],
  );
  if (regional != null) return regional;

  final String? address = _extractMunicipalityFromStructure(source['address']);
  if (address != null) return address;

  return null;
}

String? _extractMunicipalityFromStructure(dynamic value) {
  final Map<String, dynamic>? single = _asMap(value);
  if (single != null) {
    final String? nested = _firstNonEmpty(
      <dynamic>[
        single['municipality'],
        single['city'],
        single['town'],
        single['village'],
        single['name'],
        single['label'],
        single['title'],
      ],
    );
    if (nested != null) return nested;
  }

  final List<dynamic> entries = _asList(value);
  String? fallback;

  for (final dynamic entry in entries) {
    final Map<String, dynamic>? map = _asMap(entry);
    if (map == null) continue;

    final String? name = _firstNonEmpty(
      <dynamic>[map['name'], map['label'], map['title'], map['value']],
    );
    if (name == null) continue;

    final String type = _extractText(
          map['type'],
        )?.toLowerCase() ??
        _extractText(
          map['kind'],
        )?.toLowerCase() ??
        _extractText(
          map['level'],
        )?.toLowerCase() ??
        '';

    if (type.contains('municip') ||
        type.contains('city') ||
        type.contains('town') ||
        type.contains('village') ||
        type.contains('obec') ||
        type.contains('mesto') ||
        type.contains('město')) {
      return name;
    }

    fallback ??= name;
  }

  return fallback;
}

String? _firstNonEmpty(List<dynamic> values) {
  for (final dynamic value in values) {
    final String? text = _extractText(value);
    if (text != null) return text;
  }
  return null;
}

String? _extractText(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num) return value.toString();

  final Map<String, dynamic>? map = _asMap(value);
  if (map != null) {
    return _firstNonEmpty(
      <dynamic>[map['name'], map['label'], map['title'], map['value']],
    );
  }

  return null;
}

String _normalizeForCompare(String value) {
  return value.trim().toLowerCase();
}
