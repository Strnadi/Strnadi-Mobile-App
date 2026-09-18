import 'package:flutter/foundation.dart';

/// Access tokens obtained by the browser sign-in flow, for local debugging.
void logDebugBrowserToken({required String kind, required String token}) {
  if (!kDebugMode) return;

  debugPrint('[Auth] Browser sign-in $kind access token: $token');
}

/// Explicit local debug diagnostics; never route raw credentials to AppLogger.
void logDebugAuthorization({
  required String method,
  required Uri uri,
  required String? authorization,
}) {
  if (!kDebugMode || authorization == null || authorization.isEmpty) return;

  debugPrint(
    '[Auth] $method ${uri.origin}${uri.path} '
    'Authorization: $authorization',
  );
}
