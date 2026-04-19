import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/utils/markdown_html_normalizer.dart';

void main() {
  group('normalizeMarkdownHtml', () {
    test('converts html anchors into markdown links', () {
      const String input =
          'Read <a href="https://example.com/article">this article</a>.';

      final String output = normalizeMarkdownHtml(input);

      expect(
        output,
        'Read [this article](<https://example.com/article>).',
      );
    });

    test('converts audio tags with src attributes into markdown placeholders',
        () {
      const String input = '<audio controls src="/media/birds.mp3"></audio>';

      final String output = normalizeMarkdownHtml(input);

      expect(
        output,
        contains('![$markdownAudioAltToken](</media/birds.mp3>)'),
      );
    });

    test('converts bare opening audio tags into markdown placeholders', () {
      const String input = '<audio controls src="BC.mp3">';

      final String output = normalizeMarkdownHtml(input);

      expect(
        output,
        contains('![$markdownAudioAltToken](<BC.mp3>)'),
      );
    });

    test('converts audio tags with nested source tags into placeholders', () {
      const String input = '''
<audio controls>
  <source src="assets/audio/song.wav" type="audio/wav">
</audio>
''';

      final String output = normalizeMarkdownHtml(input);

      expect(
        output,
        contains('![$markdownAudioAltToken](<assets/audio/song.wav>)'),
      );
    });

    test('leaves fenced code blocks untouched', () {
      const String input = '''
```html
<a href="https://example.com/code">code link</a>
```

<a href="https://example.com/rendered">rendered link</a>
''';

      final String output = normalizeMarkdownHtml(input);

      expect(
        output,
        contains('<a href="https://example.com/code">code link</a>'),
      );
      expect(
        output,
        contains('[rendered link](<https://example.com/rendered>)'),
      );
    });
  });
}
