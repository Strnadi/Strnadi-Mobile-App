import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/security/markdown_download_security.dart';

void main() {
  group('protected Markdown origin policy', () {
    test('accepts only the exact configured HTTPS authority', () {
      expect(
        isApprovedProtectedMarkdownOrigin(
          Uri.parse('https://api.example.test/articles/7/file.wav'),
          'api.example.test',
        ),
        isTrue,
      );
      expect(
        isApprovedProtectedMarkdownOrigin(
          Uri.parse('https://api.example.test:8443/file.wav'),
          'api.example.test:8443',
        ),
        isTrue,
      );
    });

    test('rejects cleartext, subdomains, ports, and user-info tricks', () {
      for (final Uri candidate in <Uri>[
        Uri.parse('http://api.example.test/file.pdf'),
        Uri.parse('https://evil.api.example.test/file.pdf'),
        Uri.parse('https://api.example.test:8443/file.pdf'),
        Uri.parse('https://user@api.example.test/file.pdf'),
      ]) {
        expect(
          isApprovedProtectedMarkdownOrigin(
            candidate,
            'api.example.test',
          ),
          isFalse,
          reason: '$candidate must not receive a bearer token.',
        );
      }
    });

    test('recognizes same backend host even when its URI is unsafe', () {
      expect(
        targetsConfiguredBackendHost(
          Uri.parse('http://api.example.test/file.pdf'),
          'api.example.test',
        ),
        isTrue,
      );
      expect(
        targetsConfiguredBackendHost(
          Uri.parse('https://other.example.test/file.pdf'),
          'api.example.test',
        ),
        isFalse,
      );
    });
  });

  test('production protected downloads are session-bound and never cached', () {
    final String source = File('lib/md_renderer.dart').readAsStringSync();
    final int start = source.indexOf(
      'Future<String?> _downloadProtectedMarkdownFile(',
    );
    final int end = source.indexOf(
      'Future<String?> _downloadMarkdownFilePath(',
      start,
    );
    final String protectedDownload = source.substring(start, end);

    expect(protectedDownload, contains('..followRedirects = false'));
    expect(protectedDownload, contains('HttpHeaders.authorizationHeader'));
    expect(protectedDownload, contains('activatedAuthSessions.isCurrent'));
    expect(protectedDownload, contains('response.statusCode < 200'));
    expect(protectedDownload, contains('response.statusCode >= 300'));
    expect(protectedDownload, isNot(contains('DefaultCacheManager')));

    final int routingStart = end;
    final int routingEnd = source.indexOf(
      '/// A widget that renders',
      routingStart,
    );
    final String routing = source.substring(routingStart, routingEnd);
    expect(routing, contains('targetsConfiguredBackendHost('));
    expect(routing, contains('isApprovedProtectedMarkdownOrigin('));
    expect(routing, contains('activatedAuthSessions.capture()'));
    expect(
      routing.indexOf('_downloadProtectedMarkdownFile('),
      lessThan(routing.indexOf('DefaultCacheManager().getSingleFile(')),
    );
  });
}
