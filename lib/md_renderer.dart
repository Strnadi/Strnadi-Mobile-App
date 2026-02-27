/*
 * Copyright (C) 2025 Marian Pecqueur && Jan Drobílek
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:strnadi/config/config.dart';
import 'package:url_launcher/url_launcher.dart';

/// A widget that renders a Markdown file from the given asset path.
class MDRender extends StatefulWidget {
  /// The asset path to the Markdown file.
  final String? mdPath;
  final String? mdContent;
  final int? articleId;
  final String title;
  final bool showScaffold;

  const MDRender({
    Key? key,
    this.mdPath,
    required this.title,
    this.mdContent,
    this.articleId,
    this.showScaffold = true,
  }) : super(key: key);

  @override
  _MDRenderState createState() => _MDRenderState();
}

class _MDRenderState extends State<MDRender> {
  String? _markdownContent;

  @override
  void initState() {
    super.initState();
    _loadMarkdownContent();
  }

  Future<void> _loadMarkdownContent() async {
    if (widget.mdContent != null) {
      setState(() {
        _markdownContent = widget.mdContent;
      });
      return;
    }
    try {
      final data = await rootBundle.loadString(widget.mdPath!);
      setState(() {
        _markdownContent = data;
      });
    } catch (e) {
      setState(() {
        _markdownContent = 'Error loading Markdown file: $e';
      });
    }
  }

  Future<void> _openLink(String href) async {
    final Uri? url = _resolveMarkdownUri(href);
    if (url == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve link: $href')),
      );
      return;
    }
    final bool opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $href')),
      );
    }
  }

  Uri? _resolveMarkdownUri(String rawHref) {
    final String href = rawHref.trim();
    if (href.isEmpty) {
      return null;
    }

    if (href.startsWith('//')) {
      return Uri.tryParse('https:$href');
    }

    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return null;
    }

    if (uri.hasScheme) {
      return uri;
    }

    if (uri.path.startsWith('/articles/')) {
      return Uri(
        scheme: 'https',
        host: Config.host,
        path: uri.path,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      );
    }

    final int? articleId = widget.articleId;
    if (articleId == null) {
      return null;
    }

    final String path =
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (path.isEmpty) {
      return null;
    }

    final List<String> fileSegments =
        path.split('/').where((segment) => segment.isNotEmpty).toList();
    if (fileSegments.isEmpty) {
      return null;
    }

    return Uri(
      scheme: 'https',
      host: Config.host,
      pathSegments: <String>[
        'articles',
        articleId.toString(),
        ...fileSegments,
      ],
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  String? _resolveAssetImagePath(Uri uri) {
    if (uri.hasScheme) {
      return null;
    }

    final String rawPath = uri.path.trim();
    if (rawPath.isEmpty) {
      return null;
    }

    final String normalizedPath =
        rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;
    if (normalizedPath.startsWith('assets/')) {
      return normalizedPath;
    }

    final String? mdPath = widget.mdPath;
    if (mdPath == null || rawPath.startsWith('/')) {
      return null;
    }

    final int separator = mdPath.lastIndexOf('/');
    if (separator < 0) {
      return null;
    }

    return '${mdPath.substring(0, separator + 1)}$normalizedPath';
  }

  Widget _buildImageError(String source, String? alt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        alt?.trim().isNotEmpty == true ? alt! : 'Unable to load image: $source',
        style: const TextStyle(color: Color(0xFF475569)),
      ),
    );
  }

  Widget _buildMarkdownImage(MarkdownImageConfig config) {
    final Uri uri = config.uri;
    final String? title = config.title;
    final String? alt = config.alt;

    final String? assetPath = _resolveAssetImagePath(uri);
    if (assetPath != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.asset(
          assetPath,
          width: config.width,
          height: config.height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              _buildImageError(assetPath, alt ?? title),
        ),
      );
    }

    final Uri? resolvedUri = _resolveMarkdownUri(uri.toString());
    if (resolvedUri == null ||
        (resolvedUri.scheme != 'http' && resolvedUri.scheme != 'https')) {
      return _buildImageError(uri.toString(), alt ?? title);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Image.network(
        resolvedUri.toString(),
        width: config.width,
        height: config.height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            _buildImageError(resolvedUri.toString(), alt ?? title),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF1F2937),
        fontSize: 16,
        height: 1.6,
      ),
      a: theme.textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF0B7285),
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w600,
      ),
      h1: theme.textTheme.headlineMedium?.copyWith(
        color: const Color(0xFF0F172A),
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      h2: theme.textTheme.headlineSmall?.copyWith(
        color: const Color(0xFF0F172A),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h3: theme.textTheme.titleLarge?.copyWith(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      h4: theme.textTheme.titleMedium?.copyWith(
        color: const Color(0xFF1E293B),
        fontWeight: FontWeight.w700,
      ),
      h5: theme.textTheme.titleSmall?.copyWith(
        color: const Color(0xFF334155),
        fontWeight: FontWeight.w700,
      ),
      h6: theme.textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF334155),
        fontWeight: FontWeight.w700,
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF7C2D12),
        fontFamily: 'monospace',
        backgroundColor: const Color(0xFFFFF4E6),
      ),
      listBullet: theme.textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF1F2937),
      ),
      blockquote: theme.textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF475569),
        height: 1.6,
      ),
    );
  }

  Widget _buildContent(Widget child, {bool useSafeArea = true}) {
    final Widget inner = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD8E4EE)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A0F172A),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: child,
            ),
          ),
        ),
      ),
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF3F8FC),
            Color(0xFFE7F0F7),
          ],
        ),
      ),
      child: useSafeArea ? SafeArea(child: inner) : inner,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = _markdownContent == null
        ? const Center(child: CircularProgressIndicator())
        : Markdown(
            data: _markdownContent!,
            styleSheet: _markdownStyle(context),
            selectable: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            sizedImageBuilder: _buildMarkdownImage,
            onTapLink: (text, href, title) async {
              if (href == null || href.isEmpty) return;
              await _openLink(href);
            },
          );

    final Widget body = _buildContent(
      content,
      useSafeArea: widget.showScaffold,
    );

    if (!widget.showScaffold) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(widget.title),
        centerTitle: true,
      ),
      body: body,
    );
  }
}
