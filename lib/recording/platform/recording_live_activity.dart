import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

enum RecordingActivityAction { pause, resume, stop }

class RecordingLiveActivity {
  static const _channel = MethodChannel('com.delta.strnadi/recording-activity');

  static RecordingLiveActivity? _actionHandlerOwner;
  Future<void> Function(String, RecordingActivityAction)? _handler;

  /// Links bring the app forward before using the same serialized finish path.
  /// A stale link must never finish a different recording session.
  static Future<bool> handleFinishLink(Uri uri) async {
    if (uri.scheme != 'com.delta.strnadi' ||
        uri.host != 'recording' ||
        uri.path != '/finish') {
      return false;
    }
    final sessionID = uri.queryParameters['sessionID'];
    final owner = _actionHandlerOwner;
    if (sessionID == null || sessionID.isEmpty || owner == null) return true;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      final resumed = Completer<void>();
      final listener = AppLifecycleListener(
        onStateChange: (state) {
          if (state == AppLifecycleState.resumed && !resumed.isCompleted) {
            resumed.complete();
          }
        },
      );
      try {
        await resumed.future.timeout(const Duration(seconds: 15));
      } finally {
        listener.dispose();
      }
    }
    await owner._enqueue(sessionID, RecordingActivityAction.stop);
    return true;
  }

  Future<void> _enqueue(String sessionID, RecordingActivityAction action) {
    final operation = _actionOperations.then((_) async {
      final handler = _handler;
      if (!identical(_actionHandlerOwner, this) || handler == null) {
        throw PlatformException(code: 'RECORDING_NOT_AVAILABLE');
      }
      await handler(sessionID, action);
    });
    _actionOperations = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  Future<void> _actionOperations = Future<void>.value();

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<String?> start({required String sessionID}) async {
    if (!isSupportedPlatform) return null;

    return await _channel.invokeMethod<String>('start', {
      'sessionID': sessionID,
    });
  }

  Future<void> update({
    required String sessionID,
    required Duration elapsed,
    required DateTime? runningSince,
  }) async {
    if (!isSupportedPlatform) return;

    await _channel.invokeMethod<void>('update', {
      'sessionID': sessionID,
      'elapsedSeconds': elapsed.inMicroseconds / Duration.microsecondsPerSecond,
      'runningSinceMs': runningSince?.millisecondsSinceEpoch.toDouble(),
    });
  }

  Future<void> end({required String sessionID}) async {
    if (!isSupportedPlatform) return;

    await _channel.invokeMethod<void>('end', {'sessionID': sessionID});
  }

  void setActionHandler(
    Future<void> Function(String sessionID, RecordingActivityAction action)?
    handler,
  ) {
    if (!isSupportedPlatform) return;

    _handler = handler;
    if (handler == null) {
      if (identical(_actionHandlerOwner, this)) {
        _channel.setMethodCallHandler(null);
        _actionHandlerOwner = null;
      }
      return;
    }

    _actionHandlerOwner = this;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'performRecordingAction') {
        throw MissingPluginException(
          'Unknown recording activity method: ${call.method}',
        );
      }

      final arguments = call.arguments;
      if (arguments is! Map) {
        throw PlatformException(code: 'INVALID_ARGUMENTS');
      }

      final sessionID = arguments['sessionID'];
      final actionName = arguments['action'];

      if (sessionID is! String ||
          sessionID.trim().isEmpty ||
          !RecordingActivityAction.values.any(
            (action) => action.name == actionName,
          )) {
        throw PlatformException(code: 'INVALID_ARGUMENTS');
      }

      final action = RecordingActivityAction.values.byName(
        actionName as String,
      );

      // A resume can arrive while pause is still finalizing its segment.
      // Preserve command order rather than dropping that resume as busy.
      await _enqueue(sessionID, action);
      return null;
    });
  }
}
