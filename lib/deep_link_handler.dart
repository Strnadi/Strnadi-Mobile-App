import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:logger/logger.dart';

Logger logger = Logger();

class DeepLinkHandler {
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  StreamSubscription? _sub;
  final AppLinks _appLinks = AppLinks();

  void initialize() {
    // Listen for incoming deep link changes using app_links package.
    _sub = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        logger.i('Received deep link: $uri');
        // TODO: Handle deep link navigation or processing here.
      }
    }, onError: (error) {
      logger.i('Deep link error: $error');
    });
  }

  void dispose() {
    _sub?.cancel();
  }
}