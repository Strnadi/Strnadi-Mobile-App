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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/utils/markdown_html_normalizer.dart';
import 'package:url_launcher/url_launcher.dart';

const FlutterSecureStorage _markdownFileStorage = FlutterSecureStorage();
const Set<String> _markdownImageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'svg',
  'heic',
  'heif',
};
const Set<String> _markdownWebPageExtensions = <String>{
  'htm',
  'html',
  'md',
};

String? _markdownPathExtension(String path) {
  final List<String> segments =
      path.split('/').where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) {
    return null;
  }

  final String lastSegment = segments.last;
  final int dotIndex = lastSegment.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == lastSegment.length - 1) {
    return null;
  }

  return lastSegment.substring(dotIndex + 1).toLowerCase();
}

bool _markdownPathLooksLikeFile(String path) {
  return _markdownPathExtension(path) != null;
}

Future<Map<String, String>> _markdownDownloadHeaders(Uri uri) async {
  if (uri.host != Config.host) {
    return const <String, String>{};
  }

  final String? token = await _markdownFileStorage.read(key: 'token');
  if (token == null || token.isEmpty) {
    return const <String, String>{};
  }

  return <String, String>{
    'Authorization': 'Bearer $token',
  };
}

Future<String?> _downloadMarkdownFilePath(List<Uri> candidates) async {
  for (final Uri candidate in candidates) {
    try {
      final Map<String, String> headers =
          await _markdownDownloadHeaders(candidate);
      final file = await DefaultCacheManager().getSingleFile(
        candidate.toString(),
        key: candidate.toString(),
        headers: headers.isEmpty ? null : headers,
      );
      return file.path;
    } catch (_) {
      // Try the next candidate URI before surfacing a failure.
    }
  }

  return null;
}

/// A widget that renders a Markdown file from the given asset path.
class MDRender extends StatefulWidget {
  /// The asset path to the Markdown file.
  final String? mdPath;
  final String? mdContent;
  final int? articleId;
  final String title;
  final bool showScaffold;

  const MDRender({
    this.mdPath,
    required this.title,
    this.mdContent,
    this.articleId,
    this.showScaffold = true,
    super.key,
  });

  @override
  State<MDRender> createState() => _MDRenderState();
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
      _setMarkdownContent(widget.mdContent!);
      return;
    }
    try {
      final data = await rootBundle.loadString(widget.mdPath!);
      _setMarkdownContent(data);
    } catch (e) {
      _setMarkdownContent('Error loading Markdown file: $e');
    }
  }

  void _setMarkdownContent(String content) {
    setState(() {
      _markdownContent = normalizeMarkdownHtml(content);
    });
  }

  Future<void> _openLink(String href) async {
    final List<Uri> candidates =
        _resolveMarkdownUriCandidates(href, preferFilesEndpoint: true);
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve link: $href')),
      );
      return;
    }

    final Uri url = candidates.first;

    if (_shouldDownloadBeforeOpening(url)) {
      final String? localPath = await _downloadMarkdownFilePath(candidates);
      if (localPath != null) {
        final bool openedLocal = await launchUrl(
          Uri.file(localPath),
          mode: LaunchMode.externalApplication,
        );
        if (openedLocal) {
          return;
        }
      }
    }

    final bool opened =
        await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $href')),
      );
    }
  }

  bool _shouldDownloadBeforeOpening(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }

    final String? extension = _markdownPathExtension(uri.path);
    if (extension == null) {
      return false;
    }

    return !_markdownImageExtensions.contains(extension) &&
        !_markdownWebPageExtensions.contains(extension);
  }

  List<Uri> _resolveMarkdownUriCandidates(
    String rawHref, {
    bool preferFilesEndpoint = false,
  }) {
    final String href = rawHref.trim();
    if (href.isEmpty) {
      return const <Uri>[];
    }

    if (href.startsWith('//')) {
      final Uri? uri = Uri.tryParse('https:$href');
      return uri == null ? const <Uri>[] : <Uri>[uri];
    }

    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return const <Uri>[];
    }

    if (uri.hasScheme) {
      return <Uri>[uri];
    }

    if (uri.path.startsWith('/articles/')) {
      return <Uri>[
        Uri(
          scheme: 'https',
          host: Config.host,
          path: uri.path,
          query: uri.hasQuery ? uri.query : null,
          fragment: uri.fragment.isEmpty ? null : uri.fragment,
        ),
      ];
    }

    final int? articleId = widget.articleId;
    final String path =
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (path.isEmpty) {
      if (uri.path.startsWith('/')) {
        return <Uri>[
          Uri(
            scheme: 'https',
            host: Config.host,
            path: uri.path,
            query: uri.hasQuery ? uri.query : null,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          ),
        ];
      }
      return const <Uri>[];
    }

    final List<String> fileSegments =
        path.split('/').where((segment) => segment.isNotEmpty).toList();
    if (fileSegments.isEmpty) {
      return const <Uri>[];
    }

    if (articleId == null) {
      if (uri.path.startsWith('/')) {
        return <Uri>[
          Uri(
            scheme: 'https',
            host: Config.host,
            pathSegments: fileSegments,
            query: uri.hasQuery ? uri.query : null,
            fragment: uri.fragment.isEmpty ? null : uri.fragment,
          ),
        ];
      }
      return const <Uri>[];
    }

    final List<Uri> candidates = <Uri>[];

    void addCandidate(List<String> pathSegments) {
      final Uri candidate = Uri(
        scheme: 'https',
        host: Config.host,
        pathSegments: pathSegments,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.fragment.isEmpty ? null : uri.fragment,
      );
      final String serialized = candidate.toString();
      if (candidates.any((existing) => existing.toString() == serialized)) {
        return;
      }
      candidates.add(candidate);
    }

    final bool looksLikeFile = _markdownPathLooksLikeFile(path);
    if (preferFilesEndpoint && looksLikeFile) {
      addCandidate(<String>[
        'articles',
        articleId.toString(),
        'files',
        ...fileSegments,
      ]);
    }

    addCandidate(<String>[
      'articles',
      articleId.toString(),
      ...fileSegments,
    ]);

    return candidates;
  }

  Uri? _resolveMarkdownUri(String rawHref, {bool preferFilesEndpoint = false}) {
    final List<Uri> candidates = _resolveMarkdownUriCandidates(
      rawHref,
      preferFilesEndpoint: preferFilesEndpoint,
    );
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  String? _resolveAssetPath(Uri uri) {
    if (uri.scheme == 'asset') {
      final String assetPath =
          uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
      return assetPath.isEmpty ? null : assetPath;
    }

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

  Widget _buildMediaError(String source, String? alt) {
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
        alt?.trim().isNotEmpty == true ? alt! : 'Unable to load media: $source',
        style: const TextStyle(color: Color(0xFF475569)),
      ),
    );
  }

  Widget _buildMarkdownAudio(MarkdownImageConfig config) {
    final Uri uri = config.uri;
    final String? assetPath = _resolveAssetPath(uri);
    if (assetPath != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: _MarkdownAudioPlayer(
          assetPath: assetPath,
          label: config.title,
        ),
      );
    }

    final List<Uri> resolvedUris = _resolveMarkdownUriCandidates(
      uri.toString(),
      preferFilesEndpoint: true,
    );
    if (resolvedUris.isEmpty) {
      return _buildMediaError(uri.toString(), 'Unable to load audio');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _MarkdownAudioPlayer(
        sourceUris: resolvedUris,
        label: config.title,
      ),
    );
  }

  Widget _buildMarkdownImage(MarkdownImageConfig config) {
    final Uri uri = config.uri;
    final String? title = config.title;
    final String? alt = config.alt;

    if (_isMarkdownAudioPlaceholder(alt, title)) {
      return _buildMarkdownAudio(config);
    }

    final String? assetPath = _resolveAssetPath(uri);
    if (assetPath != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Image.asset(
          assetPath,
          width: config.width,
          height: config.height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              _buildMediaError(assetPath, alt ?? title),
        ),
      );
    }

    final Uri? resolvedUri = _resolveMarkdownUri(uri.toString());
    if (resolvedUri == null ||
        (resolvedUri.scheme != 'http' && resolvedUri.scheme != 'https')) {
      return _buildMediaError(uri.toString(), alt ?? title);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Image.network(
        resolvedUri.toString(),
        width: config.width,
        height: config.height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            _buildMediaError(resolvedUri.toString(), alt ?? title),
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

class _MarkdownAudioPlayer extends StatefulWidget {
  const _MarkdownAudioPlayer({
    this.assetPath,
    this.sourceUris,
    this.label,
  }) : assert(assetPath != null || sourceUris != null);

  final String? assetPath;
  final List<Uri>? sourceUris;
  final String? label;

  @override
  State<_MarkdownAudioPlayer> createState() => _MarkdownAudioPlayerState();
}

class _MarkdownAudioPlayerState extends State<_MarkdownAudioPlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isLoading = true;
  bool _isPlaying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _subscriptions.add(
      _audioPlayer.positionStream.listen((Duration position) {
        if (!mounted) return;
        setState(() {
          _position = position;
        });
      }),
    );
    _subscriptions.add(
      _audioPlayer.durationStream.listen((Duration? duration) {
        if (!mounted) return;
        setState(() {
          _duration = duration ?? Duration.zero;
        });
      }),
    );
    _subscriptions.add(
      _audioPlayer.playerStateStream.listen((PlayerState state) {
        if (state.processingState == ProcessingState.completed) {
          _audioPlayer.seek(Duration.zero);
          _audioPlayer.pause();
        }
        if (!mounted) return;
        setState(() {
          _isPlaying = state.playing;
          _isLoading = state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering;
        });
      }),
    );

    _loadAudio();
  }

  Future<void> _loadAudio() async {
    try {
      if (widget.assetPath != null) {
        await _audioPlayer.setAsset(widget.assetPath!);
      } else {
        final String? filePath =
            await _downloadMarkdownFilePath(widget.sourceUris!);
        if (filePath == null) {
          throw Exception('Unable to download audio file.');
        }
        await _audioPlayer.setFilePath(filePath);
      }
      if (!mounted) return;
      setState(() {
        _duration = _audioPlayer.duration ?? _duration;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load audio.';
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayback() async {
    if (_errorMessage != null || _isLoading) {
      return;
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }

    await _audioPlayer.play();
  }

  Future<void> _seekTo(double value) async {
    await _audioPlayer.seek(Duration(milliseconds: value.round()));
  }

  String get _displayLabel {
    final String explicitLabel = widget.label?.trim() ?? '';
    if (explicitLabel.isNotEmpty) {
      return explicitLabel;
    }

    final String? rawSource =
        widget.assetPath ?? _extractUriLabel(widget.sourceUris?.first);
    if (rawSource == null || rawSource.isEmpty) {
      return 'Audio';
    }

    return Uri.decodeComponent(rawSource.split('/').last);
  }

  String? _extractUriLabel(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final List<String> segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      return segments.last;
    }
    return uri.host;
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  void dispose() {
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (_errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          _errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: const Color(0xFF475569),
          ),
        ),
      );
    }

    final int maxMilliseconds =
        _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final int currentMilliseconds =
        _position.inMilliseconds.clamp(0, maxMilliseconds).toInt();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8E4EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: () {
                  unawaited(_togglePlayback());
                },
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Text(
                  _displayLabel,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF1F2937),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_isLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          Slider(
            value: currentMilliseconds.toDouble(),
            max: maxMilliseconds.toDouble(),
            onChanged: _duration == Duration.zero
                ? null
                : (double value) {
                    unawaited(_seekTo(value));
                  },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                _formatDuration(_position),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _isMarkdownAudioPlaceholder(String? alt, String? title) {
  String normalize(String? value) =>
      (value ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  const Set<String> acceptedTokens = <String>{
    'strnadiaudio',
  };

  return acceptedTokens.contains(normalize(alt)) ||
      acceptedTokens.contains(normalize(title));
}
