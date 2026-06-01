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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/auth/appleAuth.dart';
import 'package:strnadi/auth/google_sign_in_service.dart' hide logger;
import 'package:strnadi/localization/localization.dart';
import '../../HealthCheck/serverHealth.dart' show logger;
import '../../navigation/scaffold_with_bottom_bar.dart';

class Connectedplatforms extends StatefulWidget {
  const Connectedplatforms({super.key});

  @override
  State<Connectedplatforms> createState() => _ConnectedPlatformsState();
}

class _ConnectedPlatformsState extends State<Connectedplatforms> {
  static const AuthController _authController = AuthController();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  bool? _shouldShowAppleSignIn;
  bool? _shouldShowGoogleSignIn;
  bool _isConnectingApple = false;
  bool _isConnectingGoogle = false;

  @override
  void initState() {
    super.initState();
    _refreshConnectionStatus();
  }

  Future<bool> shouldShowGoogle() async {
    final int userId =
        int.tryParse(await _storage.read(key: 'userId') ?? '') ?? -1;
    if (userId <= 0) return true;

    final response = await _authController.hasGoogleId(userId);
    logger.i(response.statusCode);
    if (response.statusCode == 200) {
      return false;
    }
    return true;
  }

  Future<bool> shouldShowApple() async {
    final int userId =
        int.tryParse(await _storage.read(key: 'userId') ?? '') ?? -1;
    if (userId <= 0) return true;

    final response = await _authController.hasAppleId(userId);
    logger.i(response.statusCode);
    if (response.statusCode == 200) {
      return false;
    }
    return true;
  }

  Future<void> _refreshConnectionStatus() async {
    final results = await Future.wait([
      shouldShowApple(),
      shouldShowGoogle(),
    ]);

    if (!mounted) return;
    setState(() {
      _shouldShowAppleSignIn = results[0];
      _shouldShowGoogleSignIn = results[1];
    });
  }

  Future<void> _connectApple() async {
    if (kIsWeb) {
      logger.w("Apple Sign-In is not supported on the web.");
      return;
    }

    setState(() {
      _isConnectingApple = true;
    });

    try {
      final jwt = await _storage.read(key: 'token');
      final resp = await AppleAuth.signInAndGetJwt(jwt);
      if (resp?['status'] != 200) {
        logger.w("Apple Sign-In was cancelled or failed.");
        return;
      }

      logger.i('Apple Sign-In successful.');
      if (mounted) {
        setState(() {
          _shouldShowAppleSignIn = false;
        });
      }
      await _refreshConnectionStatus();
    } catch (e) {
      logger.e("Error during Apple Sign-In: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingApple = false;
        });
      }
    }
  }

  Future<void> _connectGoogle() async {
    if (kIsWeb) {
      logger.w("Google Sign-In is not supported on the web.");
      return;
    }

    setState(() {
      _isConnectingGoogle = true;
    });

    try {
      final jwt = await _storage.read(key: 'token');
      final resp = await GoogleSignInService.googleAuth(jwt: jwt);
      if (resp?['status'] != 200) {
        logger.w("Google Sign-In was cancelled or failed.");
        return;
      }

      logger.i('Google Sign-In successful.');
      if (mounted) {
        setState(() {
          _shouldShowGoogleSignIn = false;
        });
      }
      await _refreshConnectionStatus();
    } catch (e) {
      logger.e("Error during Google Sign-In: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isConnectingGoogle = false;
        });
      }
    }
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

    if (_shouldShowAppleSignIn == null || _shouldShowGoogleSignIn == null) {
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
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'Váš účet je již propojen s Apple i Google.',
              style: TextStyle(fontSize: 18),
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
                ? 'Pokračovat přes Apple'
                : 'Již propojeno s Apple',
            isConnected: _shouldShowAppleSignIn == false,
            isLoading: _isConnectingApple,
            onPressed: _connectApple,
          ),
          _buildPlatformButton(
            iconAsset: 'assets/images/google.webp',
            label: _shouldShowGoogleSignIn == true
                ? 'Pokračovat přes Google'
                : 'Už propojeno s Google',
            isConnected: _shouldShowGoogleSignIn == false,
            isLoading: _isConnectingGoogle,
            onPressed: _connectGoogle,
          ),
        ],
      )),
    );
  }
}
