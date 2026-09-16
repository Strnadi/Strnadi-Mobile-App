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
    'verifier',
    'challenge',
  };

  static bool isSensitiveKey(String key) {
    final lowerKey = key.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    if (const {
      'code',
      'state',
      'authcode',
      'oauthstate',
      'body',
      'payload',
      'requestbody',
      'responsebody',
      'requestpayload',
      'responsepayload',
      'requestdata',
      'responsedata',
    }.contains(lowerKey)) {
      return true;
    }
    return _sensitiveKeyFragments.any(
      (fragment) => lowerKey.contains(fragment.replaceAll('-', '')),
    );
  }

  static Map<String, dynamic> redactMap(Map<dynamic, dynamic> input) {
    return _redactValue(input, 0) as Map<String, dynamic>;
  }

  static dynamic redactValue(dynamic value) => _redactValue(value, 0);

  static dynamic _redactValue(dynamic value, int depth) {
    if (depth > 6) return '[nested value omitted]';
    if (value is Uri) return endpoint(value);
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries.take(50))
          redactText(entry.key.toString()): isSensitiveKey(entry.key.toString())
              ? redacted
              : _redactValue(entry.value, depth + 1),
      };
    }
    if (value is Iterable) {
      return value
          .take(50)
          .map((item) => _redactValue(item, depth + 1))
          .toList(growable: false);
    }
    if (value is String) return redactText(value);
    if (value == null || value is num || value is bool) return value;
    return redactText(value.toString());
  }

  /// Sanitizes free-form reasons and exception messages at both log sinks.
  /// API adapters additionally allowlist fields instead of logging payloads.
  static String redactText(String value) {
    // Bound work even for an exception containing an enormous response body.
    var text = value.length > 16384 ? value.substring(0, 16384) : value;
    // FormatException.toString appends the rejected source after its first
    // line. That source can be a complete API payload, including credentials.
    text = text.replaceAllMapped(
      RegExp(r'FormatException:([^\r\n]*)(?:[\r\n][\s\S]*)?'),
      (match) => 'FormatException:${match[1]}',
    );
    text = text.replaceAllMapped(
      RegExp(r'''[a-zA-Z][a-zA-Z0-9+.-]*://[^\s<>"']+'''),
      (match) {
        try {
          final uri = Uri.parse(match[0]!);
          // Free-text URLs may contain GPS, search terms, or signed parameters.
          return endpoint(uri);
        } catch (_) {
          return '[redacted URL]';
        }
      },
    );
    text = text.replaceAll(
      RegExp(r'\b(?:Bearer|Basic)\s+[^\s,;"\x27}]+', caseSensitive: false),
      'Bearer $redacted',
    );
    text = text.replaceAll(
      RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
      redacted,
    );
    text = text.replaceAllMapped(
      RegExp(
        r'''(?<!Bad )(["']?(?:authorization|cookie|set-cookie|password|secret|(?:access[_-]?|refresh[_-]?|id[_-]?|fcm[_-]?)?token|jwt|api[_-]?key|code[_-]?verifier|code[_-]?challenge|code|state)["']?\s*[:=]\s*)(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;&}\]]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}$redacted',
    );
    text = text.replaceAll(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
      '[redacted email]',
    );
    text = text.replaceAll(
      RegExp(
        r'''/(?:Users|var/mobile|private/var|data/user|storage/emulated)/[^\s"']+''',
      ),
      '[redacted path]',
    );
    text = text.replaceAll(RegExp(r'[\x00-\x1f\x7f]+'), ' ').trim();
    return text.length <= 2048 ? text : '${text.substring(0, 2045)}...';
  }

  /// Keep frame boundaries for console printers and Sentry's stack parser.
  /// The original stack remains on the local occurrence for identity matching.
  static StackTrace? redactStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    final original = stackTrace.toString();
    final safe = original
        .split('\n')
        .map((frame) {
          // Protect line/column delimiters before sanitizing URL queries and
          // local paths, so sanitized frames remain parseable by the SDK.
          final locations = frame.replaceAllMapped(
            RegExp(r'\((.+):(\d+):(\d+)\)'),
            (match) =>
                '(${_redactStackLocation(match[1]!)}:${match[2]}:${match[3]})',
          );
          return redactText(locations);
        })
        .join('\n');
    return safe == original ? stackTrace : StackTrace.fromString(safe);
  }

  static String _redactStackLocation(String location) {
    final safe = redactText(location);
    if (!safe.contains('[redacted path]')) return safe;
    final basename = Uri.tryParse(location)?.pathSegments.lastOrNull;
    return basename != null &&
            RegExp(r'\.(?:dart|js|swift|kt|java|m)$').hasMatch(basename)
        ? 'redacted/${redactText(basename)}'
        : 'redacted/source';
  }

  static Uri redactUri(Uri uri) {
    final redactedQuery = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      redactedQuery[key] = isSensitiveKey(key)
          ? const <String>[redacted]
          : values;
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
      userInfo: '',
      fragment: uri.hasFragment ? redacted : null,
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

  /// A request identity without user info, query values, or fragments.
  static String endpoint(Uri uri) {
    final safe = redactUri(uri);
    return Uri(
      scheme: safe.scheme,
      host: safe.hasAuthority ? safe.host : null,
      port: safe.hasPort ? safe.port : null,
      path: safe.path,
    ).toString();
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
