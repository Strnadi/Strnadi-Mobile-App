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
import 'package:strnadi/localization/localization.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

/// A widget that renders a Markdown file from the given asset path.
class MDRender extends StatefulWidget {
  /// The asset path to the Markdown file.
  final String mdPath;
  final String title;

  const MDRender({Key? key, required this.mdPath, required this.title}) : super(key: key);

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
    try {
      final data = await rootBundle.loadString(widget.mdPath);
      setState(() {
        _markdownContent = data;
      });
    } catch (e) {
      setState(() {
        _markdownContent = 'Error loading Markdown file: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_markdownContent == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black),
      h1: Theme.of(context).textTheme.displayLarge?.copyWith(color: Colors.black),
      h2: Theme.of(context).textTheme.displayMedium?.copyWith(color: Colors.black),
      h3: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.black),
      h4: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.black),
      h5: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.black),
      h6: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.black),
    );
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(),
        title: Text(widget.title),
      ),
      body: Container(
        color: Colors.white,
        child: Markdown(
          data: _markdownContent!,
          styleSheet: markdownStyle,
          onTapLink: (text, href, title) async {
            if (href != null) {
              final Uri url = Uri.parse(href);
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${t('Could not launch')} $href')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}