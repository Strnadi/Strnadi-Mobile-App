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
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:strnadi/localization/localization.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/user/logout_safety.dart';
import 'package:strnadi/user/profile_account_safety.dart';
import 'package:strnadi/user/settingsList.dart';
import 'package:strnadi/privacy/tracking_consent.dart';
import '../config/config.dart';
import 'package:strnadi/firebase/firebase.dart' as strnadiFirebase;

import '../navigation/scaffold_with_bottom_bar.dart';

class UserPage extends StatefulWidget {
  const UserPage({Key? key}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  static const UserController _userController = UserController();
  static const ProfilePhotoPublishCoordinator _photoPublisher =
      ProfilePhotoPublishCoordinator();

  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();

  late String userName = 'null';
  late String lastName = 'null';
  late String nickName = 'null';
  String? profileImagePath;
  bool _isConnected = true;

  final logger = Logger();

  bool _isLoading = false;

  void _showLoader() {
    if (mounted) setState(() => _isLoading = true);
  }

  void _hideLoader() {
    if (mounted) setState(() => _isLoading = false);
  }

  Future<T?> _withLoader<T>(Future<T> Function() action) async {
    if (_isLoading) return null; // prevent duplicate presses
    _showLoader();
    try {
      return await action();
    } finally {
      _hideLoader();
    }
  }

  Future<void> setName() async {
    final ActivatedAuthSessionSnapshot? session =
        await _captureVerifiedSession();
    if (session == null) return;
    final String f =
        await secureStorage.read(key: profileFirstNameStorageKey) ?? 'username';
    final String l =
        await secureStorage.read(key: profileLastNameStorageKey) ?? 'LastName';
    final String n =
        await secureStorage.read(key: profileNicknameStorageKey) ?? 'nickName';
    if (!await activatedAuthSessions.isCurrent(session)) return;
    if (!mounted) return;
    setState(() {
      userName = f;
      lastName = l;
      nickName = n;
    });
  }

  Future<ActivatedAuthSessionSnapshot?> _captureVerifiedSession() async {
    final ActivatedAuthSessionSnapshot? session =
        await activatedAuthSessions.capture();
    final int? userId = int.tryParse(session?.userId ?? '');
    if (session == null || !session.verified || userId == null || userId <= 0) {
      return null;
    }
    return session;
  }

  @override
  void initState() {
    super.initState();
    setName(); // local storage fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _withLoader(() async {
        await checkConnectivity();
        await Future.wait([
          getUserData(),
          getProfilePic(null),
        ]);
      });
    });
  }

  Future<void> checkConnectivity() async {
    bool connected = await Config.hasBasicInternet;
    if (!mounted) return;
    setState(() {
      _isConnected = connected;
    });
  }

  Future<void> refreshUserData() async {
    await _withLoader(() async {
      await getUserData();
      await getProfilePic(null);
      await setName(); // also refresh nickname (and first/last) from secure storage
    });
  }

  Future<void> getProfilePic(String? mail) async {
    final ActivatedAuthSessionSnapshot? session =
        await _captureVerifiedSession();
    if (session == null) return;
    final int userId = int.parse(session.userId);
    final String host = Config.host;
    final String cacheKey = profilePhotoCacheKey(
      ownerUserId: session.userId,
      environment: Config.hostEnvironment.name,
    );
    final cacheManager = DefaultCacheManager();

    final cachedFile = await cacheManager.getFileFromCache(cacheKey);
    if (cachedFile != null && await cachedFile.file.exists()) {
      if (!await activatedAuthSessions.isCurrent(session) ||
          Config.host != host) {
        return;
      }
      if (!mounted) return;
      setState(() => profileImagePath = cachedFile.file.path);
      return;
    }

    try {
      final value = await _userController.getProfilePhoto(
        userId,
        accessToken: session.accessToken,
        host: host,
      );
      if (value.statusCode == 200) {
        final Map<String, dynamic>? data = decodeProfileMapPayload(value.data);
        final Object? encodedPhoto = data?['photoBase64'];
        final Object? rawFormat = data?['format'];
        if (encodedPhoto is! String ||
            encodedPhoto.isEmpty ||
            rawFormat is! String) {
          logger.w('Profile picture payload was invalid.');
          return;
        }
        final photoBytes = base64Decode(encodedPhoto);
        if (!await activatedAuthSessions.isCurrent(session) ||
            Config.host != host) {
          return;
        }
        final File file = await cacheManager.putFile(
          cacheKey,
          photoBytes,
          fileExtension: profilePhotoFormatFromPath('photo.$rawFormat'),
        );

        if (!await activatedAuthSessions.isCurrent(session) ||
            Config.host != host) {
          return;
        }
        if (!mounted) return;
        setState(() => profileImagePath = file.path);
      } else {
        logger.w(
          'Profile picture download failed with status '
          '${value.statusCode}.',
        );
      }
    } catch (_) {
      logger.w('Profile picture download failed.');
    }
  }

  Future<void> getUserData() async {
    final ActivatedAuthSessionSnapshot? session =
        await _captureVerifiedSession();
    if (session == null) return;
    final int userId = int.parse(session.userId);
    final String host = Config.host;

    try {
      final response = await _userController.getUserById(
        userId,
        accessToken: session.accessToken,
        host: host,
      );
      final UserProfileData? data = parseSuccessfulUserProfile(
        statusCode: response.statusCode,
        payload: response.data,
      );
      if (data == null ||
          !await activatedAuthSessions.isCurrent(session) ||
          Config.host != host) {
        return;
      }

      await secureStorage.write(
        key: profileFirstNameStorageKey,
        value: data.firstName,
      );
      await secureStorage.write(
        key: profileLastNameStorageKey,
        value: data.lastName,
      );
      await secureStorage.write(
        key: profileNicknameStorageKey,
        value: data.nickname,
      );
      if (data.role != null) {
        await secureStorage.write(
          key: profileRoleStorageKey,
          value: data.role,
        );
      }

      if (!await activatedAuthSessions.isCurrent(session) ||
          Config.host != host ||
          !mounted) {
        return;
      }
      setState(() {
        userName = data.firstName;
        lastName = data.lastName;
        nickName = data.nickname;
      });
    } catch (_) {
      logger.w('User profile refresh failed.');
    }
  }

  Future<void> pickProfileImage() async {
    if (_isLoading) return;
    try {
      await _withLoader(() async {
        final XFile? pickedFile =
            await ImagePicker().pickImage(source: ImageSource.gallery);
        if (pickedFile == null) return;
        await _uploadProfilePic(pickedFile.path);
      });
    } catch (_) {
      logger.w('Profile picture selection failed.');
      _showMessage(t('user.profile.dialogs.error.profilePhotoUpload'));
    }
  }

  Future<void> _uploadProfilePic(String imagePath) async {
    final ActivatedAuthSessionSnapshot? session =
        await _captureVerifiedSession();
    if (session == null) {
      _showMessage(t('user.profile.dialogs.error.auth'));
      return;
    }
    final int userId = int.parse(session.userId);
    final String host = Config.host;
    final String cacheKey = profilePhotoCacheKey(
      ownerUserId: session.userId,
      environment: Config.hostEnvironment.name,
    );
    final File candidateFile = File(imagePath);

    try {
      final ProfilePhotoPublishOutcome outcome =
          await _photoPublisher.publishBoundedCandidate(
        candidateLength: candidateFile.length,
        readCandidate: candidateFile.readAsBytes,
        uploadCandidate: (imageBytes) async {
          final value = await _userController.uploadProfilePhoto(
            userId: userId,
            photoBase64: base64Encode(imageBytes),
            format: profilePhotoFormatFromPath(imagePath),
            accessToken: session.accessToken,
            host: host,
          );
          return value.statusCode;
        },
        isSessionCurrent: () async =>
            await activatedAuthSessions.isCurrent(session) &&
            Config.host == host,
        commitScopedCache: (imageBytes) async {
          final File cachedFile = await DefaultCacheManager().putFile(
            cacheKey,
            imageBytes,
            fileExtension: profilePhotoFormatFromPath(imagePath),
          );
          return cachedFile.path;
        },
        publishVisiblePath: (String cachedPath) async {
          if (!mounted) return;
          setState(() => profileImagePath = cachedPath);
        },
      );

      if (!mounted) return;
      if (outcome == ProfilePhotoPublishOutcome.published) {
        _showMessage(t('user.profile.dialogs.success.profilePhotoUploaded'));
      } else if (outcome != ProfilePhotoPublishOutcome.sessionChanged) {
        _showMessage(t('user.profile.dialogs.error.profilePhotoUpload'));
      }
    } catch (_) {
      logger.w('Profile picture upload failed.');
      if (await activatedAuthSessions.isCurrent(session)) {
        _showMessage(t('user.profile.dialogs.error.profilePhotoUpload'));
      }
    }
  }

  Future<void> logout(BuildContext context, {bool popUp = true}) async {
    if (popUp) {
      final NavigatorState navigator = Navigator.of(context);
      showDialog(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(t('logout.title')),
              content: Text(t('logout.message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(t('logout.cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    if (_isLoading) return;
                    Navigator.of(dialogContext).pop();
                    await _withLoader(() async {
                      await runOrderedLogoutCleanup(
                        captureLogoutEvent: () =>
                            TrackingConsentManager.captureEvent(
                          'logout',
                          properties: const {'method': 'manual'},
                        ),
                        resetAnalyticsIdentity:
                            TrackingConsentManager.resetIdentity,
                        deleteDeviceToken: strnadiFirebase.deleteToken,
                        clearAuthSession: () =>
                            activatedAuthSessions.clearAllPreservingGeneration(
                          secureStorage.deleteAll,
                        ),
                        signOutIdentityProvider: GoogleSignInService.signOut,
                      );
                      if (!mounted || !navigator.mounted) return;
                      navigator.pushNamedAndRemoveUntil(
                          '/authorizator', (route) => false);
                    });
                  },
                  child: Text(t('logout.logout')),
                ),
              ],
            );
          });
    } else {
      await _withLoader(() async {
        await runOrderedLogoutCleanup(
          captureLogoutEvent: () => TrackingConsentManager.captureEvent(
            'logout',
            properties: const {'method': 'manual'},
          ),
          resetAnalyticsIdentity: TrackingConsentManager.resetIdentity,
          deleteDeviceToken: strnadiFirebase.deleteToken,
          clearAuthSession: () =>
              activatedAuthSessions.clearAllPreservingGeneration(
            secureStorage.deleteAll,
          ),
          signOutIdentityProvider: GoogleSignInService.signOut,
        );
        if (!mounted) return;
        Navigator.of(this.context)
            .pushNamedAndRemoveUntil('/authorizator', (route) => false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isLoading,
      child: Stack(
        children: [
          ScaffoldWithBottomBar(
            selectedPage: BottomBarItem.user,
            appBarTitle: '',
            logout: () => !_isLoading ? logout(context) : null,
            content: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    height: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Builder(builder: (context) {
                          final String normalizedNick = nickName.trim();
                          final bool hasNickname = normalizedNick.isNotEmpty &&
                              normalizedNick != 'null' &&
                              normalizedNick != 'nickName';
                          final String displayName = hasNickname
                              ? normalizedNick
                              : '$userName $lastName';

                          return Column(
                            children: [
                              GestureDetector(
                                onTap: !_isLoading ? pickProfileImage : null,
                                child: CircleAvatar(
                                  radius: 50,
                                  backgroundImage: profileImagePath != null
                                      ? FileImage(File(profileImagePath!))
                                      : const AssetImage(
                                              './assets/images/default.jpg')
                                          as ImageProvider,
                                ),
                              ),
                              Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  _isConnected
                      ? MenuScreen(
                          refreshUserCallback: refreshUserData,
                          logout: logout,
                        )
                      : Text(t('user.menu.error.noInternet')),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMessage(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
    ));
  }
}
