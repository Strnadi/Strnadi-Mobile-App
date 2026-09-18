import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/api/dio_client.dart';
import 'package:strnadi/api/controllers/maps_controller.dart';
import 'package:strnadi/config/host_environment.dart';
import 'package:strnadi/security/markdown_download_security.dart';

void main() {
  test('full URLs preserve scheme, port, path and query parameters', () {
    for (final base in [
      'http://localhost:8080/api/v2',
      'http://localhost:8080/api/v2/',
    ]) {
      expect(
        ApiDioClient.uri(
          '/recordings',
          host: base,
          queryParameters: {'parts': true},
        ).toString(),
        'http://localhost:8080/api/v2/recordings?parts=true',
      );
    }
  });

  test('preprod uses exactly the configured prefix', () {
    const controller = MapsController();
    for (final suffix in ['', '/custom', '/v1/']) {
      final base = 'https://preprod-api.strnadi.cz$suffix';
      expect(
        resolveApiHost(HostEnvironment.preprod, {
          'host': 'https://api.strnadi.cz',
          'preprodhost': base,
        }),
        base,
      );
      expect(
        controller.tileUrlTemplate(host: base),
        '${base.replaceFirst(RegExp(r"/+$"), "")}/map/v1/maptiles/outdoor/256/{z}/{x}/{y}',
      );
    }
  });

  test('legacy hostnames remain HTTPS with no automatic version', () {
    expect(
      ApiDioClient.uri(
        '/recordings',
        host: 'preprod-api.strnadi.cz',
      ).toString(),
      'https://preprod-api.strnadi.cz/recordings',
    );
  });

  test('invalid base URLs fail closed', () {
    for (final base in [
      '',
      'https://',
      'ftp://api.example.test/v1',
      'https://user:password@api.example.test/v1',
      'https://api.example.test/v1?key=value',
      'https://api.example.test/v1#fragment',
    ]) {
      expect(() => apiBaseUri(base), throwsStateError);
    }
    expect(
      () => resolveApiHost(HostEnvironment.preprod, {
        'host': 'https://prod.example.test/api',
        'preprodhost': 'https://prod.example.test/v1',
      }),
      throwsStateError,
    );
  });

  test('protected downloads recognize full API URL origin and port', () {
    expect(
      isApprovedProtectedMarkdownOrigin(
        Uri.parse('https://api.example.test:8443/v1/articles/file'),
        'https://api.example.test:8443/v1',
      ),
      isTrue,
    );
    expect(
      isApprovedProtectedMarkdownOrigin(
        Uri.parse('https://api.example.test/v1/articles/file'),
        'https://api.example.test:8443/v1',
      ),
      isFalse,
    );
  });
}
