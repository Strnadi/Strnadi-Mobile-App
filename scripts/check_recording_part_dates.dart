import 'dart:convert';
import 'dart:io';

/// Read-only preproduction diagnostic. Never prints audio, GPS, or user details.
/// Run: dart run scripts/check_recording_part_dates.dart
/// Optional authentication: STRNADI_ACCESS_TOKEN environment variable.
/// Exit codes: 0 = clean, 1 = invalid dates found, 2 = request/schema error.
List<Map<String, Object?>> findInvalidPartDates(dynamic payload) {
  if (payload is! List) {
    throw const FormatException('Expected a recordings array');
  }
  final issues = <Map<String, Object?>>[];
  for (final recording in payload) {
    if (recording is! Map ||
        (recording['parts'] != null && recording['parts'] is! List)) {
      throw const FormatException('Invalid recording or parts structure');
    }
    for (final part in (recording['parts'] as List? ?? const [])) {
      if (part is! Map) {
        throw const FormatException('Expected a part object');
      }
      final invalidFields = <String, String>{};
      for (final field in ['startDate', 'endDate']) {
        final value = part[field];
        final String? problem = !part.containsKey(field)
            ? 'missing'
            : value == null
                ? 'null'
                : value is! String
                    ? 'not a string'
                    : DateTime.tryParse(value) == null
                        ? 'invalid date string'
                        : null;
        if (problem != null) invalidFields[field] = problem;
      }
      if (invalidFields.isNotEmpty) {
        issues.add({
          'recordingId': recording['id'],
          'partId': part['id'],
          'invalidFields': invalidFields,
        });
      }
    }
  }
  return issues;
}

Future<void> main() async {
  final uri = Uri.https('preprod-api.strnadi.cz', '/recordings', {
    'parts': 'true',
    'sound': 'false',
  });
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final token = Platform.environment['STRNADI_ACCESS_TOKEN'];
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(const Duration(seconds: 60));
    if (response.statusCode != HttpStatus.ok) {
      stderr.writeln('GET $uri returned HTTP ${response.statusCode}.');
      if (response.statusCode == 401 || response.statusCode == 403) {
        stderr
            .writeln('Set STRNADI_ACCESS_TOKEN to an authorized access token.');
      }
      exitCode = 2;
      return;
    }
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 60));
    final payload = jsonDecode(body);
    final issues = findInvalidPartDates(payload);
    final recordings = payload as List;
    final partCount = recordings.fold<int>(
      0,
      (count, recording) =>
          count + ((recording['parts'] as List?)?.length ?? 0),
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'endpoint': uri.toString(),
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'recordingsChecked': recordings.length,
      'partsChecked': partCount,
      'invalidParts': issues,
    }));
    exitCode = issues.isEmpty ? 0 : 1;
  } catch (error) {
    // Avoid echoing response content or credentials in exception messages.
    stderr.writeln(
        'Diagnostic failed (${error.runtimeType}); no complete result.');
    exitCode = 2;
  } finally {
    client.close(force: true);
  }
}
