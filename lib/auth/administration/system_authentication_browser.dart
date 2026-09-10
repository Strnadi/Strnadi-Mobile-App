import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'pkce_attempt.dart';

/// Android browser Auth Tabs/Custom Tabs and iOS ASWebAuthenticationSession.
/// Browser/platform error descriptions may contain URLs, so discard them.
Future<String> openSystemAuthenticationBrowser(Uri authorizeUri) async {
  try {
    return await FlutterWebAuth2.authenticate(
      url: authorizeUri.toString(),
      callbackUrlScheme: 'com.delta.strnadi',
      options: const FlutterWebAuth2Options(
        useWebview: false,
        // Login and logout must share the browser cookie session.
        preferEphemeral: false,
      ),
    );
  } on PlatformException catch (error) {
    throw OAuthFailure(error.code == 'CANCELED'
        ? OAuthFailureKind.cancelled
        : OAuthFailureKind.server);
  } catch (_) {
    throw const OAuthFailure(OAuthFailureKind.server);
  }
}
