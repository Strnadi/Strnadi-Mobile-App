const String markdownAudioAltToken = 'strnadi-audio';

final RegExp _fencedCodeBlockPattern = RegExp(
  r'(```[\s\S]*?```|~~~[\s\S]*?~~~)',
  multiLine: true,
);
final RegExp _htmlAnchorPattern = RegExp(
  r'<a\b(?<attributes>[^>]*)>(?<content>.*?)</a>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _htmlAudioPattern = RegExp(
  r'<audio\b(?<attributes>[^>]*)>(?<content>.*?)</audio>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _htmlSelfClosingAudioPattern = RegExp(
  r'<audio\b(?<attributes>[^>]*)/\s*>',
  caseSensitive: false,
);
final RegExp _htmlOpeningAudioPattern = RegExp(
  r'<audio\b(?<attributes>[^>]*)>',
  caseSensitive: false,
);
final RegExp _htmlSourcePattern = RegExp(
  r'<source\b(?<attributes>[^>]*)/?>',
  caseSensitive: false,
);
final RegExp _htmlLineBreakPattern = RegExp(
  r'<br\s*/?>',
  caseSensitive: false,
);
final RegExp _openingParagraphPattern = RegExp(
  r'<p\b[^>]*>',
  caseSensitive: false,
);
final RegExp _closingParagraphPattern = RegExp(
  r'</p>',
  caseSensitive: false,
);
final RegExp _htmlTagPattern = RegExp(
  r'<[^>]+>',
  caseSensitive: false,
);
final RegExp _whitespacePattern = RegExp(r'\s+');

String normalizeMarkdownHtml(String input) {
  if (input.isEmpty) {
    return input;
  }

  final StringBuffer buffer = StringBuffer();
  int cursor = 0;

  for (final Match match in _fencedCodeBlockPattern.allMatches(input)) {
    buffer
        .write(_normalizeMarkdownSegment(input.substring(cursor, match.start)));
    buffer.write(match.group(0));
    cursor = match.end;
  }

  buffer.write(_normalizeMarkdownSegment(input.substring(cursor)));
  return buffer.toString();
}

String _normalizeMarkdownSegment(String input) {
  var output = input;
  output = output.replaceAllMapped(_htmlAnchorPattern, _replaceAnchorTag);
  output = output.replaceAllMapped(_htmlAudioPattern, _replaceAudioTag);
  output = output.replaceAllMapped(
    _htmlSelfClosingAudioPattern,
    _replaceSelfClosingAudioTag,
  );
  output = output.replaceAllMapped(
    _htmlOpeningAudioPattern,
    _replaceOpeningAudioTag,
  );
  output = output.replaceAll(_htmlLineBreakPattern, '  \n');
  output = output.replaceAll(_openingParagraphPattern, '');
  output = output.replaceAll(_closingParagraphPattern, '\n\n');
  return output;
}

String _replaceAnchorTag(Match match) {
  final String attributes = match.group(1) ?? '';
  final String content = match.group(2) ?? '';
  final String? href = _extractHtmlAttribute(attributes, 'href');
  if (href == null || href.trim().isEmpty) {
    return _collapseWhitespace(_stripHtmlTags(content));
  }

  final String linkText = _collapseWhitespace(_stripHtmlTags(content));
  final String label = linkText.isEmpty ? href.trim() : linkText;
  return '[${_escapeMarkdownLinkText(label)}](<${href.trim()}>)';
}

String _replaceAudioTag(Match match) {
  final String attributes = match.group(1) ?? '';
  final String content = match.group(2) ?? '';
  return _buildAudioPlaceholder(attributes, content) ?? content;
}

String _replaceSelfClosingAudioTag(Match match) {
  final String attributes = match.group(1) ?? '';
  return _buildAudioPlaceholder(attributes, '') ?? '';
}

String _replaceOpeningAudioTag(Match match) {
  final String attributes = match.group(1) ?? '';
  return _buildAudioPlaceholder(attributes, '') ?? match.group(0)!;
}

String? _buildAudioPlaceholder(String attributes, String content) {
  final String? src =
      _extractHtmlAttribute(attributes, 'src') ?? _extractSourceSrc(content);
  if (src == null || src.trim().isEmpty) {
    return null;
  }

  final String? label = _extractHtmlAttribute(attributes, 'title') ??
      _extractHtmlAttribute(attributes, 'aria-label');
  return '\n\n![$markdownAudioAltToken](<${src.trim()}>${_formatMarkdownTitle(label)})\n\n';
}

String? _extractSourceSrc(String content) {
  final Match? match = _htmlSourcePattern.firstMatch(content);
  if (match == null) {
    return null;
  }
  return _extractHtmlAttribute(match.group(1) ?? '', 'src');
}

String? _extractHtmlAttribute(String attributes, String attribute) {
  final RegExp pattern = RegExp(
    '${RegExp.escape(attribute)}\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'=<>`]+))',
    caseSensitive: false,
  );
  final Match? match = pattern.firstMatch(attributes);
  if (match == null) {
    return null;
  }

  return match.group(1) ?? match.group(2) ?? match.group(3);
}

String _stripHtmlTags(String input) {
  return input.replaceAll(_htmlTagPattern, ' ').replaceAll('&nbsp;', ' ');
}

String _collapseWhitespace(String input) {
  return input.replaceAll(_whitespacePattern, ' ').trim();
}

String _escapeMarkdownLinkText(String input) {
  return input
      .replaceAll('\\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
}

String _formatMarkdownTitle(String? title) {
  final String normalized = title?.trim() ?? '';
  if (normalized.isEmpty) {
    return '';
  }

  final String escaped =
      normalized.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  return ' "$escaped"';
}
