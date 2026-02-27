/*
 * Copyright (C) 2024 Marian Pecqueur
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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/api/controllers/auth_controller.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:logger/logger.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
//import 'package:strnadi/auth/login.dart';
import 'package:strnadi/auth/registeration/mail.dart';
import 'package:strnadi/auth/unverifiedEmail.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/firebase/firebase.dart' as firebase;
import 'package:strnadi/localization/localization.dart';
import 'package:strnadi/md_renderer.dart';
import 'package:strnadi/privacy/tracking_consent.dart';
import 'package:strnadi/recording/streamRec.dart';
import 'package:strnadi/widgets/FlagDropdown.dart';
import 'package:strnadi/widgets/loader.dart';

// Removed: import 'package:connectivity_plus/connectivity_plus.dart';

import '../config/config.dart';
import 'launch_warning.dart';
import 'login.dart' show Login;

Logger logger = Logger();
const AuthController _authController = AuthController();
const UserController _userController = UserController();

enum AuthType { login, register }

class Authorizator extends StatefulWidget {
  const Authorizator({
    Key? key,
  }) : super(key: key);

  @override
  State<Authorizator> createState() => _AuthState();
}

enum AuthStatus { loggedIn, loggedOut, notVerified }

Future<AuthStatus> _onlineIsLoggedIn() async {
  final secureStorage = FlutterSecureStorage();
  final token = await secureStorage.read(key: 'token');
  if (token != null) {
    try {
      final response = await _authController.verifyJwt(token);

      logger.i('Response: ${response.statusCode} | ${response.data}');

      if (response.statusCode == 200) {
        await secureStorage.write(key: 'verified', value: 'true');
        DateTime expirationDate = JwtDecoder.getExpirationDate(token)!;
        if (expirationDate
            .isAfter(DateTime.now().add(const Duration(days: 7)))) {
          return AuthStatus.loggedIn;
        }
        // If the token is valid but about to expire, refresh it
        try {
          final refreshResponse = await _authController.renewJwt(token);
          if (refreshResponse.statusCode == 200) {
            String newToken = refreshResponse.data.toString();
            await secureStorage.write(key: 'token', value: newToken);
          }
        } catch (e, stackTrace) {
          Sentry.captureException(e, stackTrace: stackTrace);
          logger.e('Error refreshing token: $e',
              error: e, stackTrace: stackTrace);
        }
        return AuthStatus.loggedIn;
      } else if (response.statusCode == 403) {
        await secureStorage.write(key: 'verified', value: 'false');
        return AuthStatus.notVerified;
      } else {
        return AuthStatus.loggedOut;
      }
    } catch (error) {
      Sentry.captureException(error);
      return AuthStatus.loggedOut;
    }
  }
  return AuthStatus.loggedOut;
}

Future<AuthStatus> _offlineIsLoggedIn() async {
  FlutterSecureStorage secureStorage = FlutterSecureStorage();
  String? token = await secureStorage.read(key: 'token');
  if (token != null) {
    DateTime expirationDate = JwtDecoder.getExpirationDate(token)!;
    if (expirationDate.isAfter(DateTime.now())) {
      String? verified = await secureStorage.read(key: 'verified');
      if (verified == 'true') {
        return AuthStatus.loggedIn;
      } else {
        return AuthStatus.notVerified;
      }
    } else {
      return AuthStatus.loggedOut;
    }
  } else {
    return AuthStatus.loggedOut;
  }
}

Future<AuthStatus> isLoggedIn() async {
  // Treat either no connectivity or backend unreachable as offline
  if (!await Config.hasBasicInternet) {
    return await _offlineIsLoggedIn();
  }
  if (!await Config.isBackendAvailable) {
    return await _offlineIsLoggedIn();
  }
  return await _onlineIsLoggedIn();
}

class _AuthState extends State<Authorizator> {
  bool _isOnline = true;
  bool _isLoading = false;

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  void _trackSession(int userId, {required bool verified}) {
    unawaited(TrackingConsentManager.identifyUser(userId.toString()));
    unawaited(TrackingConsentManager.captureEvent(
      verified ? 'session_restored' : 'login_requires_verification',
      properties: const {'method': 'jwt'},
    ));
  }

  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // ignore repeated presses while loading
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  final List<Language> languages = [
    Language(name: 'Czech', code: 'cs', flag: '🇨🇿'),
    Language(name: 'English', code: 'en', flag: '🇬🇧'),
    Language(name: 'German', code: 'de', flag: '🇩🇪'),
  ];

  Language? selectedLanguage;

  @override
  void initState() {
    super.initState();
    selectedLanguage = languages.first;
    _loadSelectedLanguage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showWIPwarning();
    });
    Config.hasBasicInternet.then((online) {
      setState(() {
        _isOnline = online;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      logger.i('Checking logged-in status on app start');
      checkLoggedIn();
    });
  }

  Future<void> _loadSelectedLanguage() async {
    final languagePreference = await Config.getLanguagePreference();
    final code = Config.StringFromLanguagePreference(languagePreference);
    final resolved = languages.firstWhere(
      (language) => language.code == code,
      orElse: () => languages.first,
    );
    if (!mounted) return;
    setState(() {
      selectedLanguage = resolved;
    });
  }

  void _showWIPwarning() {
    showDialog(
      context: context,
      builder: (context) => WIP_warning(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Example color definitions
    const Color textColor = Color(0xFF2D2B18);
    const Color yellow = Color(0xFFFFD641);
    return Loader(
        isLoading: _isLoading,
        child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32.0, vertical: 20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Spacing from the top
                            //const SizedBox(height: 0),

                            // Bird image
                            Image.asset(
                              'assets/images/ncs_logo_tall_large.png',
                              // Update path if needed
                              width: 200,
                              height: 200,
                            ),

                            const SizedBox(height: 32),

                            // Main title
                            Text(
                              t('auth.title'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Subtitle
                            Text(
                              t('auth.subtitle'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),

                            const SizedBox(height: 40),

                            // "Založit účet" button (yellow background, no elevation)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    _navigateIfAllowed(const RegMail()),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  // No elevation
                                  shadowColor: Colors.transparent,
                                  // Remove shadow
                                  backgroundColor: yellow,
                                  foregroundColor: textColor,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  textStyle: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  t('auth.buttons.register'),
                                  style: TextStyle(color: textColor),
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // "Přihlásit se" button (outlined)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () =>
                                    _navigateIfAllowed(const Login()),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: textColor,
                                  side: BorderSide(
                                      color: Colors.grey[200]!, width: 2),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  textStyle: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(t('auth.buttons.login'),
                                    style: TextStyle(color: textColor)),
                              ),
                            ),

                            // Text to continue as guest
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const LiveRec()),
                                );
                              },
                              child: Text(
                                t('auth.buttons.continue_as_guest'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),

                            // Add the terms here
                            const SizedBox(height: 180),

                            // Add disclaimer and space at the bottom
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10, // 5 pixels from bottom
                    left: 0,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          t('auth.disclaimer.consent_prefix'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _launchURL(),
                          child: Text(
                            t('auth.disclaimer.privacy_policy'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CompactLanguageDropdown(
                      languages: languages,
                      selectedLanguage: selectedLanguage ?? languages.first,
                      onChanged: (Language? newValue) async {
                        if (newValue == null) return;
                        await Localization.load(
                            'assets/lang/${newValue.code}.json');
                        await Config.setLanguagePreference(
                          Config.LangFromString(newValue.code),
                        );
                        if (!mounted) return;
                        setState(() => selectedLanguage = newValue);
                        logger.i('Language changed to ${newValue.code}');
                      },
                    ),
                  )
                ],
              ),
            )));
  }

  Future<void> checkLoggedIn() async {
    _withLoader(() async {
      bool online = await Config.hasBasicInternet;
      bool serverAvailable = await Config.isBackendAvailable;
      final secureStorage = FlutterSecureStorage();
      if (!online && !serverAvailable) {
        String? token = await secureStorage.read(key: 'token');
        if (token == null) {
          logger.i("No internet and no token stored.");
          _showAlert(
            t('auth.alerts.offline_no_token.title'),
            t('auth.alerts.offline_no_token.message'),
          );
          return;
        } else {
          DateTime expirationDate = JwtDecoder.getExpirationDate(token);
          if (expirationDate.isBefore(DateTime.now())) {
            logger.i('JWT expired and no internet.');
            _showAlert(
              t('auth.alerts.offline_expired_token.title'),
              t('auth.alerts.offline_expired_token.message'),
            );
            return;
          } else {
            DateTime expirationDate = JwtDecoder.getExpirationDate(token);
            if (expirationDate.isBefore(DateTime.now())) {
              logger.i('JWT expired and no internet.');
              _showAlert(
                t('auth.alerts.offline_expired_token.title'),
                t('auth.alerts.offline_expired_token.message'),
              );
              return;
            }
            String? verified = await secureStorage.read(key: 'verified');
            if (verified != 'true') {
              logger.i('Account not verified and no internet.');
              _showAlert(
                t('auth.alerts.offline_not_verified.title'),
                t('auth.alerts.offline_not_verified.message'),
              );
              return;
            }
          }
          String? verified = await secureStorage.read(key: 'verified');
          if (verified != 'true') {
            logger.i('Account not verified and no internet.');
            _showAlert(
              t('auth.alerts.offline_not_verified.title'),
              t('auth.alerts.offline_not_verified.message'),
            );
            return;
          }
        }
      }
      //final secureStorage = FlutterSecureStorage();
      final AuthStatus status = await isLoggedIn();

      if (status == AuthStatus.loggedIn) {
        logger.i('User is logged in, fetching user data');
        String? token = await secureStorage.read(key: 'token');
        if (token == null) return;
        String? userIdS = await secureStorage.read(key: 'userId');
        int? userId;

        if (userIdS == null) {
          final idResponse = await _userController.getUserIdFromToken();
          if (idResponse.statusCode != 200) {
            logger.e(
                'Failed to fetch user id: ${idResponse.statusCode} | ${idResponse.data}');
            return;
          }
          userId = int.parse(idResponse.data.toString());
          await secureStorage.write(key: 'userId', value: userId.toString());
        } else {
          userId = int.parse(userIdS);
        }
        if (userId == null) return;
        final response = await _userController.getUserById(userId);
        if (response.statusCode != 200) {
          logger.e(
              'Failed to fetch user profile: ${response.statusCode} | ${response.data}');
          return;
        }
        final dynamic raw = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (raw is! Map) {
          logger.e('Failed to parse user profile payload: ${raw.runtimeType}');
          return;
        }
        final Map<String, dynamic> data = raw.cast<String, dynamic>();
        await secureStorage.write(key: 'user', value: data['firstName']);
        await secureStorage.write(key: 'lastname', value: data['lastName']);
        await secureStorage.write(key: 'nick', value: data['nickname']);
        await secureStorage.write(key: 'role', value: data['role']);

        if (userId != null) {
          _trackSession(userId, verified: true);
        }
        logger.i('Syncing recordings on login');
        await DatabaseNew.syncRecordings();
        logger.i('Syncing recordings on login done');
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => LiveRec(),
            settings: const RouteSettings(name: '/Recorder'),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
      } else if (status == AuthStatus.notVerified) {
        logger.i('User email not verified, navigating to verification page');
        String? token = await secureStorage.read(key: 'token');
        if (token == null) return;
        final idResponse = await _userController.getUserIdFromToken();
        if (idResponse.statusCode != 200) {
          logger.e(
              'Failed to fetch user id: ${idResponse.statusCode} | ${idResponse.data}');
          return;
        }
        int userId = int.parse(idResponse.data.toString());
        await secureStorage.write(key: 'userId', value: userId.toString());
        _trackSession(userId, verified: false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => EmailNotVerified(
                    userEmail: JwtDecoder.decode(token)['sub'],
                    userId: userId,
                  )),
        );
      } else {
        logger.i('User is not logged in');
        // If there is a token but user is not logged in (invalid token),
        // remove it and show message.
        if (await secureStorage.read(key: 'token') != null) {
          _showMessage(t('auth.alerts.logged_out'));
          await secureStorage.delete(key: 'token');
          await secureStorage.delete(key: 'user');
          await secureStorage.delete(key: 'lastname');
          await secureStorage.delete(key: 'role');
          await secureStorage.delete(key: 'userId');
          await firebase.deleteToken();
        }
      }
    });
  }

  void _showMessage(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('login.title')),
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

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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

  /// Navigate respecting internet connectivity
  Future<void> _navigateIfAllowed(Widget page) async {
    if (!await Config.hasBasicInternet) {
      _showAlert(
        t('auth.alerts.offline_action_blocked.title'),
        t('auth.alerts.offline_action_blocked.message'),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _launchURL() async {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MDRender(
                mdPath: t('auth.terms.path'),
                title: t('auth.terms.title'),
              )),
    );
  }
}
