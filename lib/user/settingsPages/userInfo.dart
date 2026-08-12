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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strnadi/api/controllers/user_controller.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/localization/localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:strnadi/auth/passReset/forgottenPassword.dart';
import 'package:strnadi/user/profile_account_safety.dart';
import 'package:strnadi/utils/async_single_flight.dart';

import '../../auth/google_sign_in_service.dart';
import '../../firebase/firebase.dart' as strnadiFirebase;

Logger logger = Logger();

class User {
  final String nickname;
  final String email;
  final String firstName;
  final String lastName;
  final int? postCode;
  final String? city;

  User({
    required this.nickname,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.postCode,
    required this.city,
  });

  factory User.fromProfile(UserProfileData profile) {
    return User(
      nickname: profile.nickname,
      email: profile.email,
      firstName: profile.firstName,
      lastName: profile.lastName,
      postCode: profile.postCode,
      city: profile.city,
    );
  }
}

class ProfileEditPage extends StatefulWidget {
  final FutureOr<void> Function() refreshUserCallback;

  const ProfileEditPage({Key? key, required this.refreshUserCallback})
      : super(key: key);

  @override
  _ProfileEditPageState createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const UserController _userController = UserController();
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  User? user;
  final AsyncSingleFlight _saveFlight = AsyncSingleFlight();
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isLoadingProfile = true;

  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _firstnameController = TextEditingController();
  final TextEditingController _lastnameController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _postCodeController = TextEditingController();

  Future<ActivatedAuthSessionSnapshot?> _captureVerifiedSession() async {
    final ActivatedAuthSessionSnapshot? session =
        await activatedAuthSessions.capture();
    final int? userId = int.tryParse(session?.userId ?? '');
    if (session == null || !session.verified || userId == null || userId <= 0) {
      return null;
    }
    return session;
  }

  Future<bool> _isCurrent(
    ActivatedAuthSessionSnapshot session,
    String host,
  ) async {
    return Config.host == host &&
        await activatedAuthSessions.isCurrent(session);
  }

  void _applyProfile(UserProfileData profile) {
    user = User.fromProfile(profile);
    _nicknameController.text = profile.nickname;
    _firstnameController.text = profile.firstName;
    _lastnameController.text = profile.lastName;
    _cityController.text = profile.city ?? '';
    _postCodeController.text = profile.postCode?.toString() ?? '';
    _emailController.text = profile.email;
  }

  Future<void> fetchUser() async {
    final ActivatedAuthSessionSnapshot? session =
        await _captureVerifiedSession();
    if (session == null) {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
        _showMessage(t('user.profile.dialogs.error.auth'));
      }
      return;
    }

    final String host = Config.host;
    try {
      final response = await _userController.getUserById(
        int.parse(session.userId),
        accessToken: session.accessToken,
        host: host,
      );
      final UserProfileData? profile = parseSuccessfulUserProfile(
        statusCode: response.statusCode,
        payload: response.data,
      );
      if (profile == null) {
        if (mounted && await _isCurrent(session, host)) {
          _showMessage(t('user.profile.dialogs.error.load'));
        }
        return;
      }
      if (!await _isCurrent(session, host) || !mounted) return;
      setState(() => _applyProfile(profile));
    } catch (_) {
      logger.w('User profile could not be loaded.');
      if (mounted && await _isCurrent(session, host)) {
        _showMessage(t('user.profile.dialogs.error.load'));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  Future<bool> _refreshUser(
    ActivatedAuthSessionSnapshot session,
    String host,
  ) async {
    final response = await _userController.getUserById(
      int.parse(session.userId),
      accessToken: session.accessToken,
      host: host,
    );
    final UserProfileData? profile = parseSuccessfulUserProfile(
      statusCode: response.statusCode,
      payload: response.data,
    );
    if (profile == null || !await _isCurrent(session, host)) return false;

    await _secureStorage.write(
      key: profileFirstNameStorageKey,
      value: profile.firstName,
    );
    await _secureStorage.write(
      key: profileLastNameStorageKey,
      value: profile.lastName,
    );
    await _secureStorage.write(
      key: profileNicknameStorageKey,
      value: profile.nickname,
    );
    if (profile.role != null) {
      await _secureStorage.write(
        key: profileRoleStorageKey,
        value: profile.role,
      );
    }
    if (!await _isCurrent(session, host)) return false;

    await widget.refreshUserCallback();
    if (!await _isCurrent(session, host) || !mounted) return false;
    setState(() => _applyProfile(profile));
    return true;
  }

  Future<void> updateUserData() {
    return _saveFlight.run(() async {
      if (mounted) setState(() => _isSaving = true);
      try {
        if (user == null) {
          _showMessage(t('user.profile.dialogs.error.load'));
          return;
        }
        final Map<String, dynamic>? updatedData = buildUserProfilePatch(
          nickname: _nicknameController.text,
          firstName: _firstnameController.text,
          lastName: _lastnameController.text,
          postCode: _postCodeController.text,
          city: _cityController.text,
        );
        if (updatedData == null) {
          _showMessage(t('user.profile.dialogs.error.update'));
          return;
        }

        final ActivatedAuthSessionSnapshot? session =
            await _captureVerifiedSession();
        if (session == null) {
          _showMessage(t('user.profile.dialogs.error.auth'));
          return;
        }
        final String host = Config.host;
        final response = await _userController.updateUserById(
          int.parse(session.userId),
          updatedData,
          accessToken: session.accessToken,
          host: host,
        );
        if (!await _isCurrent(session, host) || !mounted) return;
        if (response.statusCode != 200) {
          logger.w('User profile update was rejected.');
          _showMessage(t('user.profile.dialogs.error.update'));
          return;
        }

        final bool refreshed = await _refreshUser(session, host);
        if (!mounted || !await _isCurrent(session, host)) return;
        _showMessage(
          t(
            refreshed
                ? 'user.profile.dialogs.success.update'
                : 'user.profile.dialogs.error.update',
          ),
        );
      } catch (_) {
        logger.w('User profile update failed.');
        if (mounted) {
          _showMessage(t('user.profile.dialogs.error.update'));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    });
  }

  Future<void> confirmAndDeleteAccount() async {
    if (_isDeleting) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('user.profile.dialogs.deleteAccount.title')),
        content: Text(t('user.profile.dialogs.deleteAccount.message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('recListItem.dialogs.confirmDelete.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('recListItem.dialogs.confirmDelete.delete'),
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      final ActivatedAuthSessionSnapshot? session =
          await _captureVerifiedSession();
      if (session == null) {
        _showMessage(t('user.profile.dialogs.error.auth'));
        return;
      }
      final String host = Config.host;
      final response = await _userController.deleteUserById(
        int.parse(session.userId),
        accessToken: session.accessToken,
        host: host,
      );
      if (!mounted || !await _isCurrent(session, host)) return;

      if (response.statusCode == 200) {
        await logout();
      } else {
        _showMessage(t('user.profile.dialogs.deleteAccount.error'));
        logger.w('Account deletion was rejected.');
      }
    } catch (_) {
      logger.w('Account deletion failed.');
      if (mounted) {
        _showMessage(t('user.profile.dialogs.deleteAccount.error'));
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(fetchUser());
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _firstnameController.dispose();
    _lastnameController.dispose();
    _cityController.dispose();
    _emailController.dispose();
    _postCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('user.profile.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              onPressed: _isSaving || _isLoadingProfile
                  ? null
                  : () => unawaited(updateUserData()),
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      t('postRecordingForm.recordingForm.buttons.save'),
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(t("user.profile.title"),
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 20),
                      _buildTextField(t('user.profile.fields.firstName'),
                          _firstnameController),
                      _buildTextField(t('user.profile.fields.lastName'),
                          _lastnameController),
                      _buildTextField(t('user.profile.fields.nickname'),
                          _nicknameController),
                      _buildTextField(
                          t('user.profile.fields.email'), _emailController,
                          readOnly: true),
                      _buildTextField(
                          t('user.profile.fields.city'), _cityController),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: t('user.profile.fields.postCode'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0)),
                          ),
                          controller: _postCodeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(t('user.profile.buttons.changePassword')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ForgottenPassword()),
                      );
                    }, // Open password change
                  ),
                  ListTile(
                    title: Text(t('user.profile.buttons.deleteAccount'),
                        style: TextStyle(color: Colors.red)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _isDeleting
                        ? null
                        : () => unawaited(confirmAndDeleteAccount()),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTextField(String label, TextEditingController txt,
      {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextField(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.0)),
        ),
        controller: txt,
        readOnly: readOnly,
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('auth.buttons.ok')))
        ],
      ),
    );
  }

  Future<void> logout() async {
    FlutterSecureStorage secureStorage = FlutterSecureStorage();

    await strnadiFirebase.deleteToken();
    await activatedAuthSessions.clearAllPreservingGeneration(
      secureStorage.deleteAll,
    );
    await GoogleSignInService.signOut();

    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/authorizator', (route) => false);
  }
}
