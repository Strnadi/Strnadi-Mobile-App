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
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

Logger logger = Logger();

class DeepLinkHandler {
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  late GlobalKey<NavigatorState> navigatorKey;

  Future<void> _ensureNavigatorReady() async {
    // Wait until a NavigatorState is available. This covers cold-start deep links.
    while (navigatorKey.currentState == null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _handleUri(Uri uri) {
    logger.i('Received deep link: $uri');
    switch (uri.path) {
      case '/ucet/obnova-hesla':
        logger.i('Navigating to Reset Password page');
        final token = uri.queryParameters['token'];
        if (token != null) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/reset-password',
            (route) => false,
            arguments: {'token': token},
          );
        } else {
          logger.w('Missing token in reset-password link');
        }
        break;
      case '/ucet/email-overen':
        logger.i('Navigating to Email Verified page');
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/email-verified',
          (route) => false,
        );
        break;
      case '/ucet/email-neoveren':
        logger.i('Navigating to Email Not Verified page');
        navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/email-not-verified',
          (route) => false,
        );
        break;
      default:
        logger.w('Unhandled deep link path: ${uri.path}');
    }
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  StreamSubscription? _sub;
  final AppLinks _appLinks = AppLinks();

  void initialize() {
    // Listen for incoming deep link changes using app_links package.
    // Handle the initial deep link if the app was launched via a Universal Link.
    _appLinks.getInitialLink().then((Uri? initialUri) async {
      if (initialUri != null) {
        await _ensureNavigatorReady();
        _handleUri(initialUri);
      }
    }).catchError((error) {
      logger.e('Initial deep link error: $error');
    });

    _sub = _appLinks.uriLinkStream.listen((Uri? uri) async {
      if (uri != null) {
        await _ensureNavigatorReady();
        _handleUri(uri);
      }
    }, onError: (error) {
      logger.e('Deep link error: $error');
    });
  }

  void dispose() {
    _sub?.cancel();
  }
}