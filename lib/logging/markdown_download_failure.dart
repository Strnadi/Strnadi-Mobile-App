import 'dart:async';
import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:strnadi/logging/api_diagnostics.dart';
import 'package:strnadi/logging/app_logger.dart';

/// Records a failed candidate without changing the caller's fallback behavior.
/// The cache manager exposes HTTP status errors separately from local storage
/// errors; retain that distinction for both diagnostics and Sentry policy.
void logMarkdownDownloadFailure({
  required AppLogger logger,
  required Uri candidate,
  required Object error,
  required StackTrace stackTrace,
}) {
  if (error is HttpExceptionWithStatus) {
    logger.api(
      ApiDiagnostics.fromResponse(
        method: 'GET',
        uri: error.uri ?? candidate,
        statusCode: error.statusCode,
      ),
      error: error,
      stackTrace: stackTrace,
      failure: AppFailureRegistry.lookup(error, stackTrace),
    );
    return;
  }

  logger.w(
    'Markdown download candidate failed',
    reason: error is FileSystemException
        ? 'Unable to store or read the cached Markdown attachment'
        : 'Attachment candidate was unavailable; trying the next URI',
    error: error,
    stackTrace: stackTrace,
    expected:
        error is SocketException ||
        error is TimeoutException ||
        error is http.RequestAbortedException,
    context: {'endpoint': ApiDiagnostics.sanitizedEndpoint(candidate)},
  );
}
