import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/administration/administration_login.dart';
import 'package:strnadi/auth/administration/pkce_attempt.dart';
import 'package:strnadi/localization/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final sdkRoot = Platform.environment['FLUTTER_ROOT'];
    if (sdkRoot != null) {
      final bytes = File(
        '$sdkRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      ).readAsBytesSync();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await Localization.load('assets/lang/en.json');
  });
  testWidgets(
    'opens automatically once and ignores completion after disposal',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      final screen = AdministrationLogin(
        signIn: () {
          calls++;
          return pending.future;
        },
      );
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
      expect(calls, 1);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(theme: ThemeData.dark(), home: screen),
      );
      await tester.pump();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('browser sign-in layout and cancellation are retryable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AdministrationLogin(
          signIn: () async {
            calls++;
            throw const OAuthFailure(OAuthFailureKind.cancelled);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/administration_login.png'),
    );
    expect(find.byType(TextField), findsNothing);
    expect(calls, 1);
    expect(
      find.text(t('auth.administration.errors.cancelled')),
      findsOneWidget,
    );
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
