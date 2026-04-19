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
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' hide Config;
import 'package:strnadi/localization/localization.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/auth/google_sign_in_service.dart';
import 'package:strnadi/bottomBar.dart';
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

  var secureStorage = const FlutterSecureStorage();

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
    final f = await secureStorage.read(key: 'firstName') ?? 'username';
    final l = await secureStorage.read(key: 'lastName') ?? 'LastName';
    final n = await secureStorage.read(key: 'nick') ?? 'nickName';
    logger.i("Loaded name from local storage: $f $l ($n)");
    if (!mounted) return;
    setState(() {
      userName = f;
      lastName = l;
      nickName = n;
    });
  }

  @override
  void initState() {
    super.initState();
    setName(); // local storage fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    setState(() {
      _isConnected = connected;
    });
  }

  Future<File> convertBase64ToImage(
      String base64String, String fileName) async {
    // Decode the base64 string to bytes
    final bytes = base64Decode(base64String);

    // Get the directory to save the file
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');

    // Write the bytes to the file
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> refreshUserData() async {
    await _withLoader(() async {
      await getUserData();
      await getProfilePic(null);
      await setName(); // also refresh nickname (and first/last) from secure storage
    });
  }

  Map<String, dynamic>? _decodeMapPayload(dynamic payload) {
    try {
      if (payload is Map) {
        return payload.cast<String, dynamic>();
      }
      if (payload is String) {
        final decoded = jsonDecode(payload);
        return decoded is Map ? decoded.cast<String, dynamic>() : null;
      }
      if (payload is List<int>) {
        final decoded = jsonDecode(utf8.decode(payload));
        return decoded is Map ? decoded.cast<String, dynamic>() : null;
      }
    } catch (_) {}
    return null;
  }

  Future<void> getProfilePic(String? mail) async {
    final id = await secureStorage.read(key: "userId");
    if (id == null) return;

    final cacheKey = 'profilePic_$id';
    final cacheManager = DefaultCacheManager();

    // Try to load from cache first
    final cachedFile = await cacheManager.getFileFromCache(cacheKey);
    if (cachedFile != null && await cachedFile.file.exists()) {
      setState(() => profileImagePath = cachedFile.file.path);
      logger.i("Loaded profile picture from cache: ${cachedFile.file.path}");
      return;
    }

    try {
      final value = await _userController.getProfilePhoto(int.parse(id));
      if (value.statusCode == 200) {
        final Map<String, dynamic>? data = _decodeMapPayload(value.data);
        if (data == null) {
          logger.e('Profile picture payload is not JSON map.');
          return;
        }
        final file = await convertBase64ToImage(
          data['photoBase64'],
          'profilePic.${data['format']}',
        );

        await cacheManager.putFile(cacheKey, await file.readAsBytes());

        if (!mounted) return;
        setState(() {
          profileImagePath = file.path;
        });
        logger.i("Profile picture downloaded $profileImagePath");
      } else {
        logger.e(
            "Profile picture download failed with status code ${value.statusCode} ${value.data}");
      }
    } catch (e, st) {
      logger.e('Profile picture download error', error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }
  }

  Future<void> getUserData() async {
    final usernameExists = await secureStorage.containsKey(key: 'user');
    final id = await secureStorage.read(key: "userId");

    if (usernameExists) {
      var storedUserName = await secureStorage.read(key: 'user');
      var storedLastName = await secureStorage.read(key: 'lastname');
      setState(() {
        userName = storedUserName!;
        lastName = storedLastName!;
      });
      logger.i("User data loaded from cache");
      return;
    }

    final jwt = await secureStorage.read(key: 'token');
    if (jwt == null || id == null) return;

    try {
      final response = await _userController.getUserById(int.parse(id));

      if (response.statusCode == 200) {
        final Map<String, dynamic>? data = _decodeMapPayload(response.data);
        if (data == null) {
          logger.e('User payload is not JSON map.');
          return;
        }
        setState(() {
          userName = data['firstName'];
          lastName = data['lastName'];
        });
        secureStorage.write(key: 'user', value: data['firstName']);
        secureStorage.write(key: 'lastname', value: data['lastName']);
      }
    } catch (error) {
      Sentry.captureException(error);
    }
  }

  Future<void> pickProfileImage() async {
    if (_isLoading) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        profileImagePath = pickedFile.path;
      });
      await secureStorage.write(key: 'profileImage', value: pickedFile.path);
      var userId = await secureStorage.read(key: 'userId');
      final cacheKey = 'profilePic_$userId';
      await DefaultCacheManager().removeFile('profilePic_$userId');
      await DefaultCacheManager()
          .putFile(cacheKey, await File(profileImagePath!).readAsBytes());

      await _withLoader(() async {
        await UploadProfilePic();
      });
    }
  }

  Future<void> UploadProfilePic() async {
    final id = await secureStorage.read(key: "userId");
    if (id == null) return;

    final String photoBase64 =
        base64Encode(File(profileImagePath!).readAsBytesSync());
    final String format = profileImagePath!.split('.').last;
    try {
      final value = await _userController.uploadProfilePhoto(
        userId: int.parse(id),
        photoBase64: photoBase64,
        format: format,
      );
      if (value.statusCode == 200) {
        _showMessage(t('Profile picture uploaded'), context);
        logger.i("Profile picture uploaded");
      } else {
        _showMessage(t('Profile picture upload failed'), context);
        logger.e(
            "Profile picture upload failed with status code ${value.statusCode}");
      }
    } catch (e, st) {
      logger.e('Profile picture upload error', error: e, stackTrace: st);
      Sentry.captureException(e, stackTrace: st);
    }
  }

  Future<void> logout(BuildContext context, {bool popUp = true}) async {
    if (popUp) {
      showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(t('logout.title')),
              content: Text(t('logout.message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(t('logout.cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    if (_isLoading) return;
                    Navigator.of(context).pop(); // close dialog first
                    await _withLoader(() async {
                      unawaited(TrackingConsentManager.captureEvent('logout',
                          properties: {'method': 'manual'}));
                      unawaited(TrackingConsentManager.resetIdentity());
                      await GoogleSignInService.signOut();
                      await secureStorage.deleteAll();
                      await strnadiFirebase.deleteToken();
                      if (!mounted) return;
                      Navigator.of(context).pushNamedAndRemoveUntil(
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
        unawaited(TrackingConsentManager.captureEvent('logout',
            properties: {'method': 'manual'}));
        unawaited(TrackingConsentManager.resetIdentity());
        await GoogleSignInService.signOut();
        await secureStorage.deleteAll();
        await strnadiFirebase.deleteToken();
        if (!mounted) return;
        Navigator.of(context)
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

  void _showMessage(String s, BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(s),
    ));
  }
}
