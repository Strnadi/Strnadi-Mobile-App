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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/auth/appleAuth.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/google_sign_in_service.dart' hide logger;
import 'package:strnadi/config/config.dart' hide logger;
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/user/connected_platforms_logic.dart';
import '../../HealthCheck/serverHealth.dart' show logger;
import '../../navigation/scaffold_with_bottom_bar.dart';

class Connectedplatforms extends StatefulWidget {
  const Connectedplatforms({super.key});

  @override
  State<Connectedplatforms> createState() => _ConnectedPlatformsState();
}

class _ConnectedPlatformsState extends State<Connectedplatforms> {
  static const AuthController _authController = AuthController();
  late final ConnectedPlatformsCoordinator _coordinator;

  bool? _shouldShowAppleSignIn;
  bool? _shouldShowGoogleSignIn;
  bool _isConnectingApple = false;
  bool _isConnectingGoogle = false;
  bool _isRefreshing = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _coordinator = ConnectedPlatformsCoordinator(
      captureSession: _captureSession,
      isSessionCurrent: _isSessionCurrent,
    );
    unawaited(_refreshConnectionStatus());
  }

  Future<ConnectedAccountSession?> _captureSession() async {
    final snapshot = await activatedAuthSessions.capture();
    final int? userId = int.tryParse(snapshot?.userId ?? '');
    if (snapshot == null ||
        !snapshot.verified ||
        userId == null ||
        userId <= 0) {
      return null;
    }
    return ConnectedAccountSession(
      userId: userId,
      accessToken: snapshot.accessToken,
      sessionId: snapshot.sessionId,
      host: Config.host,
      verified: snapshot.verified,
    );
  }

  Future<bool> _isSessionCurrent(ConnectedAccountSession observed) async {
    final snapshot = await activatedAuthSessions.capture();
    return snapshot != null &&
        snapshot.verified &&
        snapshot.userId == observed.userId.toString() &&
        snapshot.accessToken == observed.accessToken &&
        snapshot.sessionId == observed.sessionId &&
        Config.host == observed.host;
  }

  Future<void> _refreshConnectionStatus() async {
    if (_isRefreshing) return;
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _loadFailed = false;
      });
    }

    try {
      final ConnectedPlatformsStatus result = await _coordinator.load(
        checkApple: (ConnectedAccountSession session) async {
          final response = await _authController.hasAppleId(
            session.userId,
            accessToken: session.accessToken,
            host: session.host,
          );
          return response.statusCode;
        },
        checkGoogle: (ConnectedAccountSession session) async {
          final response = await _authController.hasGoogleId(
            session.userId,
            accessToken: session.accessToken,
            host: session.host,
          );
          return response.statusCode;
        },
      );

      if (!mounted) return;
      setState(() {
        _shouldShowAppleSignIn =
            result.apple == ConnectedProviderState.disconnected;
        _shouldShowGoogleSignIn =
            result.google == ConnectedProviderState.disconnected;
        _loadFailed = false;
      });
    } catch (_) {
      logger.w('Connected-account status could not be loaded.');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _connectApple() async {
    if (_isConnectingApple) return;
    if (kIsWeb) {
      _showFailure();
      return;
    }

    setState(() {
      _isConnectingApple = true;
    });

    try {
      final bool connected = await _coordinator.connect(
        connectProvider: (ConnectedAccountSession session) async {
          final Map<String, dynamic>? response =
              await AppleAuth.signInAndGetJwt(session.accessToken);
          return response?['status'] as int?;
        },
      );
      if (!connected) {
        _showFailure();
        return;
      }
      await _refreshConnectionStatus();
    } catch (_) {
      logger.w('Apple account connection did not complete.');
      _showFailure();
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingApple = false;
        });
      }
    }
  }

  Future<void> _connectGoogle() async {
    if (_isConnectingGoogle) return;
    if (kIsWeb) {
      _showFailure();
      return;
    }

    setState(() {
      _isConnectingGoogle = true;
    });

    try {
      final bool connected = await _coordinator.connect(
        connectProvider: (ConnectedAccountSession session) async {
          final Map<String, dynamic>? response =
              await GoogleSignInService.googleAuth(
            jwt: session.accessToken,
          );
          return response?['status'] as int?;
        },
      );
      if (!connected) {
        _showFailure();
        return;
      }
      await _refreshConnectionStatus();
    } catch (_) {
      logger.w('Google account connection did not complete.');
      _showFailure();
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingGoogle = false;
        });
      }
    }
  }

  void _showFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t('user.connectedAccounts.error'))),
    );
  }

  Widget _buildPlatformButton({
    required String iconAsset,
    required String label,
    required bool isConnected,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isConnected || isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Image.asset(
                  iconAsset,
                  height: 24,
                  width: 24,
                ),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            elevation: 0,
            shadowColor: Colors.transparent,
            backgroundColor: isConnected ? Colors.green : Colors.black,
            foregroundColor: Colors.white,
            disabledBackgroundColor: isConnected ? Colors.green : Colors.black,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String appBarTitle = t('user.menu.items.connectedAccounts');

    if (_loadFailed) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.user,
        appBarTitle: appBarTitle,
        allowArrowBack: true,
        content: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('user.connectedAccounts.loadFailed'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isRefreshing ? null : _refreshConnectionStatus,
                  child: Text(t('user.connectedAccounts.retry')),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_isRefreshing ||
        _shouldShowAppleSignIn == null ||
        _shouldShowGoogleSignIn == null) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.user,
        appBarTitle: appBarTitle,
        allowArrowBack: true,
        content: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_shouldShowAppleSignIn == false && _shouldShowGoogleSignIn == false) {
      return ScaffoldWithBottomBar(
        selectedPage: BottomBarItem.user,
        appBarTitle: appBarTitle,
        allowArrowBack: true,
        content: Center(
            child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(
              t('user.connectedAccounts.allConnected'),
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ],
        )),
      );
    }

    return ScaffoldWithBottomBar(
      selectedPage: BottomBarItem.user,
      appBarTitle: appBarTitle,
      allowArrowBack: true,
      content: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildPlatformButton(
            iconAsset: 'assets/images/apple.png',
            label: _shouldShowAppleSignIn == true
                ? t('user.connectedAccounts.apple.connect')
                : t('user.connectedAccounts.apple.connected'),
            isConnected: _shouldShowAppleSignIn == false,
            isLoading: _isConnectingApple,
            onPressed: _connectApple,
          ),
          _buildPlatformButton(
            iconAsset: 'assets/images/google.webp',
            label: _shouldShowGoogleSignIn == true
                ? t('user.connectedAccounts.google.connect')
                : t('user.connectedAccounts.google.connected'),
            isConnected: _shouldShowGoogleSignIn == false,
            isLoading: _isConnectingGoogle,
            onPressed: _connectGoogle,
          ),
        ],
      )),
    );
  }
}
