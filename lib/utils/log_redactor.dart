class LogRedactor {
  const LogRedactor._();

  static const String redacted = '***';

  static const Set<String> _sensitiveKeyFragments = <String>{
    'authorization',
    'cookie',
    'password',
    'secret',
    'token',
    'jwt',
    'apikey',
    'api_key',
    'mapy.cz-key',
    'deviceid',
    'fcmtoken',
    'idtoken',
  };

  static bool isSensitiveKey(String key) {
    final lowerKey = key.toLowerCase().replaceAll('-', '');
    return _sensitiveKeyFragments.any(
      (fragment) => lowerKey.contains(fragment.replaceAll('-', '')),
    );
  }

  static Map<String, dynamic> redactMap(Map<dynamic, dynamic> input) {
    return input.map((key, value) {
      final stringKey = key.toString();
      return MapEntry(
        stringKey,
        isSensitiveKey(stringKey) ? redacted : redactValue(value),
      );
    });
  }

  static dynamic redactValue(dynamic value) {
    if (value is Map) {
      return redactMap(value);
    }
    if (value is Iterable) {
      return value.map(redactValue).toList(growable: false);
    }
    return value;
  }

  static Uri redactUri(Uri uri) {
    final redactedQuery = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      redactedQuery[key] =
          isSensitiveKey(key) ? const <String>[redacted] : values;
    });

    final redactedSegments = <String>[];
    for (int i = 0; i < uri.pathSegments.length; i++) {
      final segment = uri.pathSegments[i];
      final previous = i == 0 ? '' : uri.pathSegments[i - 1].toLowerCase();
      final next = i + 1 >= uri.pathSegments.length
          ? ''
          : uri.pathSegments[i + 1].toLowerCase();
      if (_looksSensitivePathSegment(segment, previous, next)) {
        redactedSegments.add(redacted);
      } else {
        redactedSegments.add(segment);
      }
    }

    return uri.replace(
      path: redactedSegments.isEmpty
          ? uri.path
          : '/${redactedSegments.join('/')}',
      queryParameters: redactedQuery.isEmpty
          ? null
          : redactedQuery.map(
              (key, values) =>
                  MapEntry(key, values.isEmpty ? '' : values.first),
            ),
    );
  }

  static bool _looksSensitivePathSegment(
    String segment,
    String previous,
    String next,
  ) {
    if (segment.isEmpty) return false;
    if (previous == 'delete' || previous == 'token') return true;
    if (next == 'reset-password') return true;
    if (segment.length > 80) return true;
    if (segment.split('.').length == 3 && segment.length > 40) return true;
    return false;
  }
}
