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