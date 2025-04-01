import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// A widget that renders a Markdown file from the given asset path.
class MDRender extends StatefulWidget {
  /// The asset path to the Markdown file.
  final String mdPath;

  const MDRender({Key? key, required this.mdPath}) : super(key: key);

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
        title: const Text('Markdown'),
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
                  SnackBar(content: Text('Could not launch $href')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}