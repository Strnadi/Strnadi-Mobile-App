import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/security/markdown_link_opener.dart';

void main() {
  final url = Uri.parse('https://example.test/attachment.pdf');
  test('downloaded attachment opens locally without launching a file URL',
      () async {
    final paths = <String>[];
    expect(
        await openMarkdownLink(
          url: url,
          download: () async => '/mock/attachment.pdf',
          openLocal: (path) async {
            paths.add(path);
            return true;
          },
          openRemote: (_) async => throw StateError('Remote must not open'),
        ),
        isTrue);
    expect(paths, ['/mock/attachment.pdf']);
  });
  for (final failure in [false, true]) {
    test(
        'unavailable viewer (throws=$failure) falls back to original HTTPS URL',
        () async {
      final opened = <Uri>[];
      expect(
          await openMarkdownLink(
            url: url,
            download: () async => '/mock/attachment.pdf',
            openLocal: (_) async {
              if (failure)
                throw PlatformException(code: 'ATTACHMENT_OPEN_FAILED');
              return false;
            },
            openRemote: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
          isTrue);
      expect(opened, [url]);
    });
  }
  test('download and remote launch failure return false without throwing',
      () async {
    expect(
        await openMarkdownLink(
          url: url,
          download: () async => throw Exception('Mock download failure'),
          openLocal: (_) async => throw StateError('No file exists'),
          openRemote: (_) async => throw PlatformException(code: 'NO_VIEWER'),
        ),
        isFalse);
  });
  test('untrusted file links never reach a downloader or launcher', () async {
    expect(
        await openMarkdownLink(
          url: Uri.file('/mock/private-recording.wav'),
          download: () async => throw StateError('Must not download'),
          openLocal: (_) async => throw StateError('Must not open local file'),
          openRemote: (_) async => throw StateError('Must not launch'),
        ),
        isFalse);
  });
}
