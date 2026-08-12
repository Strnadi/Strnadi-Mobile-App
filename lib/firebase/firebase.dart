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
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/config/config.dart';
import 'package:strnadi/database/databaseNew.dart';
import 'package:strnadi/firebase/device_session_registration.dart';
import 'package:strnadi/firebase/firebase_runtime_initialization.dart';
import 'package:strnadi/firebase/foreground_notification_delivery.dart';
import 'package:strnadi/firebase/local_notifications.dart';
import 'package:strnadi/api/controllers/device_controller.dart';
import '../firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:logger/logger.dart';
import 'dart:io';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:strnadi/deviceInfo/deviceInfo.dart';
import 'package:strnadi/firebase/device_token_lifecycle.dart';

final logger = Logger();
const DeviceController _deviceController = DeviceController();
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
const String _deviceTokenBindingKey = 'fcmTokenBinding';
const String _legacyDeviceTokenKey = 'fcmToken';
Future<void>? _firebaseInitialization;
Future<void>? _messagingInitialization;

Future<void> initFirebase() {
  return _firebaseInitialization ??= initializeFirebaseCoreRuntime(
    initializeApp: () async {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    },
    registerBackgroundHandler: () {
      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );
    },
  );
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  RemoteNotification? notification = message.notification;

  if (notification != null) {
    await showLocalNotification(
      notification.title ?? '',
      notification.body,
      id: notification.hashCode,
    );
  }
}

Future<void> _showLocalNotificationFromData(Map<String, dynamic> data) async {
  await showLocalNotificationFromData(data);
}

Future<DeviceInfo> getDeviceInfo() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String platform;
  String deviceModel;

  if (Platform.isAndroid) {
    platform = "Android";
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    deviceModel = androidInfo.model; // e.g., "Pixel 5"
  } else if (Platform.isIOS) {
    platform = "ios";
    IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
    deviceModel = iosInfo.utsname.machine; // e.g., "iPhone14,2"
  } else {
    platform = "Unknown";
    deviceModel = "Unknown";
  }

  return DeviceInfo(platform: platform, deviceModel: deviceModel);
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  // Initialize Firebase if necessary.
  await Firebase.initializeApp();
  await initLocalNotifications();
  try {
    await Config.loadHostEnvironment();
  } catch (error, stackTrace) {
    // Notification persistence will fail closed while the environment is
    // unknown, but displaying the push must remain functional.
    logger.w(
      'Could not load the notification cache environment.',
      error: error,
      stackTrace: stackTrace,
    );
  }
  logger.i("Handling a background message: ${message.messageId}");
  if (message.data.isNotEmpty) {
    final hasLocalizedKeys = message.data.containsKey('titleEn') ||
        message.data.containsKey('bodyEn') ||
        message.data.containsKey('titleDe') ||
        message.data.containsKey('bodyDe') ||
        message.data.containsKey('titleCs') ||
        message.data.containsKey('bodyCs');
    if (hasLocalizedKeys) {
      await _showLocalNotificationFromData(message.data);
    }
  }
  // Persist both native-notification and localized data-only messages.
  await DatabaseNew.insertNotification(message);
}

Future<DeviceRegistrationScope?> _captureVerifiedDeviceScope() async {
  try {
    final ActivatedAuthSessionSnapshot? session =
        await activatedAuthSessions.capture();
    if (session == null || !session.verified) return null;
    final int? userId = int.tryParse(session.userId.trim());
    if (userId == null || userId <= 0 || !Config.isHostEnvironmentLoaded) {
      return null;
    }
    return DeviceRegistrationScope(
      sessionId: session.sessionId,
      accessToken: session.accessToken,
      userId: userId,
      subject: session.subject,
      environment: Config.hostEnvironment.name,
      apiHost: Config.host,
    );
  } catch (_) {
    return null;
  }
}

Future<bool> _isDeviceScopeCurrent(DeviceRegistrationScope scope) async {
  try {
    final ActivatedAuthSessionSnapshot? current =
        await activatedAuthSessions.capture();
    return current != null &&
        current.verified &&
        current.sessionId == scope.sessionId &&
        current.accessToken == scope.accessToken &&
        current.userId == scope.userId.toString() &&
        current.subject == scope.subject &&
        Config.isHostEnvironmentLoaded &&
        Config.hostEnvironment.name == scope.environment &&
        Config.host == scope.apiHost;
  } catch (_) {
    return false;
  }
}

Future<void> _persistDeviceBinding(DeviceTokenBinding binding) async {
  // The legacy token remains available to older recording payload code. The
  // scoped marker is written last and is the only token trusted for refresh.
  await _secureStorage.write(
    key: _legacyDeviceTokenKey,
    value: binding.token,
  );
  await _secureStorage.write(
    key: _deviceTokenBindingKey,
    value: binding.encode(),
  );
}

Future<void> _clearDeviceBindingIfCurrent(
  DeviceTokenBinding binding,
) async {
  final String? encoded =
      await _secureStorage.read(key: _deviceTokenBindingKey);
  final DeviceTokenBinding? current = DeviceTokenBinding.decode(encoded);
  if (current?.encode() != binding.encode()) return;

  // Invalidate the ownership marker first. A torn deletion can leave only an
  // untrusted legacy compatibility token, which refresh never updates.
  await _secureStorage.delete(key: _deviceTokenBindingKey);
  final String? legacy = await _secureStorage.read(key: _legacyDeviceTokenKey);
  if (legacy?.trim() == binding.token) {
    await _secureStorage.delete(key: _legacyDeviceTokenKey);
  }
}

final DeviceTokenSessionCoordinator _deviceTokenSessions =
    DeviceTokenSessionCoordinator(
  captureScope: _captureVerifiedDeviceScope,
  isScopeCurrent: _isDeviceScopeCurrent,
  readBinding: () => _secureStorage.read(key: _deviceTokenBindingKey),
  getCurrentToken: FirebaseMessaging.instance.getToken,
  loadMetadata: () async {
    final DeviceInfo info = await getDeviceInfo();
    return DeviceRegistrationMetadata(
      platform: info.platform,
      model: info.deviceModel,
    );
  },
  registerRemote: (
    DeviceRegistrationScope scope,
    String token,
    DeviceRegistrationMetadata metadata,
  ) async {
    final response = await _deviceController.addDevice(
      <String, dynamic>{
        'fcmToken': token,
        'devicePlatform': metadata.platform,
        'deviceModel': metadata.model,
        'userId': scope.userId,
      },
      host: scope.apiHost,
      accessToken: scope.accessToken,
    );
    return response.statusCode;
  },
  updateRemote: (
    DeviceRegistrationScope scope,
    String oldToken,
    String newToken,
  ) async {
    final response = await _deviceController.updateDevice(
      <String, dynamic>{
        'newFCMToken': newToken,
        'oldFCMToken': oldToken,
      },
      host: scope.apiHost,
      accessToken: scope.accessToken,
    );
    return response.statusCode;
  },
  persistBinding: _persistDeviceBinding,
  clearBindingIfCurrent: _clearDeviceBindingIfCurrent,
);

void _logTokenSyncResult(DeviceTokenSyncResult result) {
  switch (result.status) {
    case DeviceTokenSyncStatus.unchanged:
      logger.i('Firebase device token is already synchronized.');
      return;
    case DeviceTokenSyncStatus.registered:
      logger.i('Firebase device token registered.');
      return;
    case DeviceTokenSyncStatus.updated:
      logger.i('Firebase device token updated.');
      return;
    case DeviceTokenSyncStatus.noVerifiedSession:
      logger.i('Skipping Firebase registration without a verified session.');
      return;
    case DeviceTokenSyncStatus.noCurrentToken:
      logger.w('Firebase did not provide a device token.');
      return;
    case DeviceTokenSyncStatus.sessionChangedBeforeRemote:
    case DeviceTokenSyncStatus.sessionChangedAfterRemote:
    case DeviceTokenSyncStatus.suppressedAfterCleanup:
      logger
          .i('Firebase token synchronization stopped after a session change.');
      return;
    case DeviceTokenSyncStatus.remoteRejected:
      logger.w(
        'Backend rejected Firebase token synchronization '
        '(${result.statusCode}).',
      );
      return;
    case DeviceTokenSyncStatus.remoteFailed:
    case DeviceTokenSyncStatus.persistenceFailed:
      logger.w(
        'Firebase token synchronization failed.',
        error: result.error,
      );
      return;
  }
}

Future<void> addDevice() async {
  final DeviceTokenSyncResult result = await _deviceTokenSessions.synchronize();
  _logTokenSyncResult(result);
}

Future<void> updateDevice(String? oldToken, String? newToken) async {
  final DeviceTokenRefreshAction action = resolveDeviceTokenRefreshAction(
    storedToken: oldToken,
    currentToken: newToken,
  );
  switch (action) {
    case DeviceTokenRefreshAction.none:
      return;
    case DeviceTokenRefreshAction.remove:
      await deleteToken();
      return;
    case DeviceTokenRefreshAction.register:
    case DeviceTokenRefreshAction.update:
      final DeviceTokenSyncResult result =
          await _deviceTokenSessions.synchronize(
        currentTokenOverride: newToken,
      );
      _logTokenSyncResult(result);
      return;
  }
}

Future<void> deleteToken() async {
  final DeviceSessionCleanupResult result =
      await _deviceTokenSessions.cleanUpCurrentSession(
    deleteRemote: (
      DeviceRegistrationScope scope,
      DeviceTokenBinding binding,
    ) async {
      final response = await _deviceController.deleteDeviceToken(
        binding.token,
        host: binding.apiHost,
        accessToken: scope.accessToken,
      );
      return response.statusCode;
    },
    invalidateFirebaseToken: FirebaseMessaging.instance.deleteToken,
    clearUnboundLocalToken: () async {
      await _secureStorage.delete(key: _deviceTokenBindingKey);
      await _secureStorage.delete(key: _legacyDeviceTokenKey);
    },
  );

  if (result.remoteAttempted && !result.remoteDeleted) {
    logger.w('The backend could not confirm Firebase token deletion.');
  }
  if (!result.firebaseTokenInvalidated) {
    logger.w('The local Firebase messaging token could not be invalidated.');
  }
  if (!result.bindingCleared) {
    logger.w('The stored Firebase device-token binding could not be deleted.');
  }
  if (result.fullyCleaned) {
    logger.i('Firebase device token cleanup completed.');
  }
}

Future<void> refreshToken() async {
  final DeviceTokenSyncResult result = await _deviceTokenSessions.synchronize();
  _logTokenSyncResult(result);
}

Future<void> _handleTokenRefresh(String newToken) async {
  final DeviceTokenSyncResult result = await _deviceTokenSessions.synchronize(
    currentTokenOverride: newToken,
  );
  _logTokenSyncResult(result);
}

Future<void> _displayForegroundMessage(RemoteMessage message) async {
  if (message.notification != null) {
    await _showLocalNotification(message);
  } else if (message.data.isNotEmpty) {
    await _showLocalNotificationFromData(message.data);
  }
}

Future<void> _handleForegroundMessage(RemoteMessage message) async {
  final ForegroundNotificationDeliveryResult result =
      await deliverForegroundNotification(
    display: () => _displayForegroundMessage(message),
    persist: () => DatabaseNew.insertNotification(message),
  );
  if (!result.displayed) {
    logger.w(
      'Foreground notification presentation failed.',
      error: result.displayError,
    );
  }
  if (!result.persisted) {
    logger.w(
      'Foreground notification persistence failed.',
      error: result.persistenceError,
    );
  }
}

Future<void> initFirebaseMessaging() {
  return _messagingInitialization ??= _initializeFirebaseMessaging();
}

Future<void> _initializeFirebaseMessaging() async {
  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permissions (required for iOS).
  final NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  logger.i("User granted permission: ${settings.authorizationStatus}");

  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  await refreshToken();

  // Listen for token refresh.
  messaging.onTokenRefresh.listen((String newToken) {
    logger.i("Firebase token refreshed");
    unawaited(_handleTokenRefresh(newToken));
  });

  // Listen for foreground messages.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    logger.i("Received a foreground message: ${message.messageId}");
    unawaited(_handleForegroundMessage(message));
  });

  // Listen for when the app is opened from a terminated or background state via a notification.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    logger.i("Notification caused app to open: ${message.messageId}");
    // Handle navigation or state update if needed.
  });
}
