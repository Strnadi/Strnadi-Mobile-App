import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/administration/system_authentication_browser.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'oauth_session_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native browser receives system-session options and returns callback',
      () async {
    const channel = MethodChannel('flutter_web_auth_2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'authenticate') return null;
      final args = call.arguments as Map;
      expect(args['callbackUrlScheme'], 'com.delta.strnadi');
      expect(args['options']['useWebview'], false);
      expect(args['options']['preferEphemeral'], false);
      return 'com.delta.strnadi://auth/callback?code=c&state=s';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    expect(
        await openSystemAuthenticationBrowser(fixture.config.authorizeEndpoint),
        contains('callback?code=c'));
  });

  test('native cancellation becomes a safe localized failure', () async {
    const channel = MethodChannel('flutter_web_auth_2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'authenticate') return null;
      throw PlatformException(code: 'CANCELED', message: 'secret callback');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await expectLater(
        openSystemAuthenticationBrowser(fixture.config.authorizeEndpoint),
        fixture.fails(OAuthFailureKind.cancelled));
  });
}
