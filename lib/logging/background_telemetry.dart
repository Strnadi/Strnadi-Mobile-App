import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:strnadi/logging/telemetry_session.dart';
import 'package:strnadi/logging/app_logger.dart';
import 'package:strnadi/logging/sentry_log_sink.dart';
import 'package:strnadi/logging/telemetry_consent.dart';

class BackgroundTelemetrySession {
  const BackgroundTelemetrySession({required this.sink, required this.close});
  final AppLogSink sink;
  final Future<void> Function() close;
}

/// Owns a Dart-only hub per callback, including callbacks running in the main
/// isolate. It never initializes or closes the foreground/native Sentry SDK.
Future<T> runWithBackgroundTelemetry<T>({
  required String operation,
  required Future<T> Function() action,
  TelemetryConsent? consent,
  Future<BackgroundTelemetrySession> Function()? createSession,
  Future<PackageInfo> Function()? readPackageInfo,
  Duration metadataTimeout = const Duration(seconds: 2),
  Duration drainTimeout = const Duration(seconds: 2),
}) async {
  final currentConsent = consent ?? TelemetryConsent.instance;
  BackgroundTelemetrySession? session;
  try {
    if (await currentConsent.isAuthorized()) {
      session =
          await (createSession ??
              () => _createSession(
                currentConsent,
                readPackageInfo: readPackageInfo,
                metadataTimeout: metadataTimeout,
              ))();
    }
  } catch (_) {
    // Telemetry is ancillary; initialization must not block the callback.
  }
  return AppLogger.runWithTelemetry(session?.sink, () async {
    final logger = AppLogger(scope: 'background');
    try {
      return await action();
    } catch (error, stackTrace) {
      logger.e(
        'Background callback failed.',
        error: error,
        stackTrace: stackTrace,
        context: {'operation': operation},
      );
      rethrow;
    } finally {
      try {
        await AppLogger.flush(timeout: drainTimeout);
      } catch (_) {
        // Preserve the task's result or original error on drain timeout.
      }
      if (session != null) {
        try {
          await session.close().timeout(drainTimeout);
        } catch (_) {
          // A transport shutdown failure cannot change retry behavior.
        }
      }
    }
  });
}

Future<BackgroundTelemetrySession> _createSession(
  TelemetryConsent consent, {
  Future<PackageInfo> Function()? readPackageInfo,
  required Duration metadataTimeout,
}) async {
  final options = SentryOptions()
    ..dsn = appSentryDsn
    ..environment = kDebugMode ? 'development' : 'production'
    ..debug = false;
  try {
    final info = await (readPackageInfo ?? PackageInfo.fromPlatform)().timeout(
      metadataTimeout,
    );
    String clean(String value) =>
        value.replaceAll(RegExp(r'[/\\\t\r\n]'), '_').replaceAll('\u0000', '');
    final name = clean(
      info.packageName.isEmpty ? info.appName : info.packageName,
    );
    options.release =
        name +
        (info.version.isEmpty ? '' : '@${clean(info.version)}') +
        (info.buildNumber.isEmpty ? '' : '+${clean(info.buildNumber)}');
    if (info.buildNumber.isNotEmpty) options.dist = clean(info.buildNumber);
  } catch (_) {
    // Reporting remains useful if release metadata cannot be read headlessly.
  }
  final hub = Hub(options);
  final sink = SentryLogSink(
    hub: hub,
    session: TelemetrySession(),
    isAuthorized: consent.isAuthorized,
  );
  sink.configureOptions(options);
  return BackgroundTelemetrySession(sink: sink, close: hub.close);
}
