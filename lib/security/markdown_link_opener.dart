import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Try a downloaded attachment first, then its original URL. A missing viewer
/// or a failed platform launch is an ordinary open failure, not an uncaught
/// asynchronous exception from the Markdown tap callback.
Future<bool> openMarkdownLink({
  required Uri url,
  required Future<bool> Function(Uri) openRemote,
  Future<String?> Function()? download,
  Future<bool> Function(String)? openLocal,
}) async {
  if (url.scheme == 'file') return false;
  if (download != null && openLocal != null) {
    try {
      final path = await download();
      if (path != null && await openLocal(path)) return true;
    } on Exception {
      // Fall back to the original URL if a download/viewer is unavailable.
    }
  }
  try {
    return await openRemote(url);
  } on Exception {
    return false;
  }
}

Future<bool> openLocalMarkdownAttachment(String path) async {
  if (!Platform.isAndroid) {
    return launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
  }
  final cache = await getTemporaryDirectory();
  final directory = await Directory('${cache.path}/markdown-attachments')
      .create(recursive: true);
  // A unique subdirectory prevents one open from replacing another viewer's
  // file. The provider exposes only this attachment directory, never recordings.
  final stagedDirectory = await directory.createTemp('open-');
  final name = File(path).uri.pathSegments.last;
  final staged = await File(path).copy('${stagedDirectory.path}/$name');
  return await const MethodChannel('com.delta.strnadi/markdown_files')
          .invokeMethod<bool>('openFile', {'path': staged.path}) ??
      false;
}
