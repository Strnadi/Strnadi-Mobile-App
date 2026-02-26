import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:strnadi/api/controllers/articles_controller.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/md_renderer.dart';

class _ArticleItem {
  final int id;
  final String name;
  final String description;

  const _ArticleItem({
    required this.id,
    required this.name,
    required this.description,
  });
}

class _ArticleCategory {
  final int id;
  final String label;
  final String name;
  final List<_ArticleItem> articles;

  const _ArticleCategory({
    required this.id,
    required this.label,
    required this.name,
    required this.articles,
  });
}

class BlogExplorerContent extends StatefulWidget {
  const BlogExplorerContent({super.key});

  @override
  State<BlogExplorerContent> createState() => _BlogExplorerContentState();
}

class _BlogExplorerContentState extends State<BlogExplorerContent> {
  static const ArticlesController _articlesController = ArticlesController();

  bool _isLoading = true;
  String? _error;
  String _search = '';
  int? _openingArticleId;

  List<_ArticleCategory> _categories = <_ArticleCategory>[];
  List<_ArticleItem> _uncategorized = <_ArticleItem>[];

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<String> _readLanguageTag() async {
    switch (await Config.getLanguagePreference()) {
      case LanguagePreference.cs:
        return 'cs-CZ';
      case LanguagePreference.en:
        return 'en-US';
      case LanguagePreference.de:
        return 'de-DE';
    }
  }

  List<dynamic> _decodeResponseList(dynamic responseData) {
    final dynamic raw =
        responseData is String ? jsonDecode(responseData) : responseData;
    return raw is List ? raw : <dynamic>[];
  }

  String _decodeResponseText(dynamic responseData) {
    if (responseData is List<int>) {
      return utf8.decode(responseData);
    }
    if (responseData is String) {
      return responseData;
    }
    return responseData?.toString() ?? '';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  String _toStringValue(dynamic value) {
    final String text = value?.toString() ?? '';
    return text.trim();
  }

  List<_ArticleItem> _parseArticles(dynamic responseData) {
    final List<_ArticleItem> items = <_ArticleItem>[];
    for (final dynamic raw in _decodeResponseList(responseData)) {
      if (raw is! Map) continue;
      final int id = _toInt(raw['id']);
      final String name = _toStringValue(raw['name']);
      if (id <= 0 || name.isEmpty) continue;
      items.add(
        _ArticleItem(
          id: id,
          name: name,
          description: _toStringValue(raw['description']),
        ),
      );
    }
    return items;
  }

  List<_ArticleCategory> _parseCategories(dynamic responseData) {
    final List<_ArticleCategory> categories = <_ArticleCategory>[];
    for (final dynamic raw in _decodeResponseList(responseData)) {
      if (raw is! Map) continue;
      final int id = _toInt(raw['id']);
      if (id <= 0) continue;
      categories.add(
        _ArticleCategory(
          id: id,
          label: _toStringValue(raw['label']),
          name: _toStringValue(raw['name']),
          articles: _parseArticles(raw['articles']),
        ),
      );
    }
    return categories;
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final responses = await Future.wait([
        _articlesController.fetchArticleCategories(includeArticles: true),
        _articlesController.fetchArticles(),
      ]);

      final categoriesResponse = responses[0];
      final articlesResponse = responses[1];

      if (![200, 204].contains(categoriesResponse.statusCode) ||
          ![200, 204].contains(articlesResponse.statusCode)) {
        throw Exception('Failed to load blog content');
      }

      final List<_ArticleCategory> parsedCategories =
          categoriesResponse.statusCode == 204
              ? <_ArticleCategory>[]
              : _parseCategories(categoriesResponse.data);
      final List<_ArticleItem> allArticles = articlesResponse.statusCode == 204
          ? <_ArticleItem>[]
          : _parseArticles(articlesResponse.data);

      final Set<int> assignedIds = <int>{};
      for (final category in parsedCategories) {
        for (final article in category.articles) {
          assignedIds.add(article.id);
        }
      }
      final List<_ArticleItem> uncategorized = allArticles
          .where((article) => !assignedIds.contains(article.id))
          .toList();

      if (!mounted) return;
      setState(() {
        _categories = parsedCategories;
        _uncategorized = uncategorized;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = t('blogExplorer.errors.load');
        _isLoading = false;
      });
    }
  }

  Future<void> _openArticle(_ArticleItem article) async {
    if (_openingArticleId != null) return;
    setState(() => _openingArticleId = article.id);
    try {
      final response = await _articlesController.fetchArticleMarkdown(
        articleId: article.id,
        languageTag: await _readLanguageTag(),
      );
      if (response.statusCode != 200) {
        _showError(t('blogExplorer.errors.open'));
        return;
      }
      final String markdown = _decodeResponseText(response.data);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MDRender(
            mdContent: markdown,
            title: article.name,
            articleId: article.id,
          ),
          settings: RouteSettings(name: '/blog/${article.id}'),
        ),
      );
    } catch (_) {
      _showError(t('blogExplorer.errors.open'));
    } finally {
      if (mounted) {
        setState(() => _openingArticleId = null);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('map.dialogs.error.title')),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('auth.buttons.ok')),
          ),
        ],
      ),
    );
  }

  bool _matchesQuery(String text) {
    if (_search.isEmpty) return true;
    return text.toLowerCase().contains(_search.toLowerCase());
  }

  Widget _buildArticleTile(_ArticleItem article) {
    return ListTile(
      title: Text(article.name),
      subtitle: article.description.isEmpty ? null : Text(article.description),
      trailing: _openingArticleId == article.id
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: () => _openArticle(article),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_ArticleCategory> filteredCategories = _categories
        .map((category) {
          final filteredArticles = category.articles.where((article) {
            return _matchesQuery(article.name) ||
                _matchesQuery(article.description);
          }).toList();
          final bool categoryMatch =
              _matchesQuery(category.label) || _matchesQuery(category.name);
          if (!categoryMatch && filteredArticles.isEmpty) {
            return null;
          }
          return _ArticleCategory(
            id: category.id,
            label: category.label,
            name: category.name,
            articles: categoryMatch && _search.isNotEmpty
                ? category.articles
                : filteredArticles,
          );
        })
        .whereType<_ArticleCategory>()
        .toList();

    final List<_ArticleItem> filteredUncategorized = _uncategorized
        .where((article) =>
            _matchesQuery(article.name) || _matchesQuery(article.description))
        .toList();

    final bool hasResults =
        filteredCategories.isNotEmpty || filteredUncategorized.isNotEmpty;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadContent,
                child: Text(t('blogExplorer.retry')),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              onChanged: (value) {
                setState(() => _search = value.trim());
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t('blogExplorer.searchHint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (!hasResults)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                t('blogExplorer.empty'),
                textAlign: TextAlign.center,
              ),
            ),
          ...filteredCategories.map(
            (category) => Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ExpansionTile(
                title: Text(
                  category.label.isNotEmpty ? category.label : category.name,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                children: category.articles.map(_buildArticleTile).toList(),
              ),
            ),
          ),
          if (filteredUncategorized.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                t('blogExplorer.uncategorized'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ...filteredUncategorized.map(_buildArticleTile),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
