/*
 * Copyright (C) 2026 Marian Pecqueur && Jan Drobílek
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:strnadi/api/controllers/articles_controller.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/md_renderer.dart';

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

String _decodeResponseText(dynamic responseData) {
  if (responseData is List<int>) {
    return utf8.decode(responseData);
  }
  if (responseData is String) {
    return responseData;
  }
  return responseData?.toString() ?? '';
}

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  static const ArticlesController _articlesController = ArticlesController();
  static const int _guideArticleId = 5;

  bool _isLoading = true;
  String? _error;
  String? _markdown;

  @override
  void initState() {
    super.initState();
    _loadGuide();
  }

  Future<void> _loadGuide() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response =
          await _articlesController.fetchArticleMarkdownWithFallback(
        articleId: _guideArticleId,
        preferredLanguageTag: await _readLanguageTag(),
      );
      if (response.statusCode != 200) {
        setState(() {
          _error = t('blogExplorer.errors.loadGuide');
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _markdown = _decodeResponseText(response.data);
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _error = t('blogExplorer.errors.loadGuide');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t('user.menu.items.guide')),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _markdown == null || _markdown!.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t('user.menu.items.guide')),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? t('blogExplorer.errors.loadGuide'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadGuide,
                  child: Text(t('blogExplorer.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MDRender(
      mdContent: _markdown!,
      title: t('user.menu.items.guide'),
      articleId: _guideArticleId,
    );
  }
}
