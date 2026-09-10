import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:strnadi/auth/apple_sign_in_cancellation.dart';

void main() {
  test('successful Apple request returns the credential', () async {
    final credential = Object();
    expect(await requestAppleSignIn(() async => credential), same(credential));
  });
  test('canceling the native sign-in returns without a login failure',
      () async {
    expect(
        await requestAppleSignIn<Object>(() async {
          throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'Canceled',
          );
        }),
        isNull);
  });
  test('Apple service errors remain visible to the caller', () async {
    const failure = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.failed,
      message: 'Service failed',
    );
    await expectLater(requestAppleSignIn<Object>(() async => throw failure),
        throwsA(same(failure)));
  });
}
