import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/passReset/changedPassword.dart';
import 'package:strnadi/auth/passReset/forgottenPassword.dart';
import 'package:strnadi/auth/passReset/newPassword.dart';
import 'package:strnadi/auth/passReset/password_reset_flow.dart';
import 'package:strnadi/auth/passReset/resetEmailSent.dart';
import 'package:strnadi/localization/localization.dart';

String _encodedJson(Map<String, Object?> value) {
  return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
}

String _resetToken({Object? subject = 'bird@example.test'}) {
  return '${_encodedJson(<String, Object?>{'alg': 'none'})}.'
      '${_encodedJson(<String, Object?>{'sub': subject})}.signature';
}

Future<void> _enterValidPassword(WidgetTester tester) async {
  final List<Finder> fields = <Finder>[
    find.byType(TextFormField).at(0),
    find.byType(TextFormField).at(1),
  ];
  await tester.enterText(fields[0], 'Strongpass1');
  await tester.enterText(fields[1], 'Strongpass1');
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await Localization.load('assets/lang/en.json');
  });

  group('passwordResetEmailFromToken', () {
    test('returns a trimmed string subject', () {
      expect(
        passwordResetEmailFromToken(
          _resetToken(subject: ' bird@example.test '),
        ),
        'bird@example.test',
      );
    });

    for (final ({String label, String token}) scenario
        in <({String label, String token})>[
      (label: 'empty token', token: ''),
      (label: 'whitespace token', token: '   '),
      (label: 'missing segments', token: 'not-a-jwt'),
      (label: 'invalid base64', token: '***.***.***'),
      (label: 'empty subject', token: _resetToken(subject: ' ')),
      (label: 'numeric subject', token: _resetToken(subject: 42)),
      (
        label: 'missing subject',
        token: '${_encodedJson(<String, Object?>{'alg': 'none'})}.'
            '${_encodedJson(<String, Object?>{})}.signature',
      ),
    ]) {
      test('rejects ${scenario.label}', () {
        expect(passwordResetEmailFromToken(scenario.token), isNull);
      });
    }
  });

  group('ForgottenPassword with mocked request boundary', () {
    testWidgets('rapid submits produce one request',
        (WidgetTester tester) async {
      final Completer<int?> response = Completer<int?>();
      int calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ForgottenPassword(
            requestPasswordReset: (String email) {
              calls += 1;
              expect(email, 'bird@example.test');
              return response.future;
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        ' bird@example.test ',
      );

      final Finder submit = find.byKey(const Key('forgotten-password-submit'));
      await tester.tap(submit);
      await tester.tap(submit);
      expect(calls, 1);

      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      response.complete(500);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('late response after disposal has no UI side effects',
        (WidgetTester tester) async {
      final Completer<int?> response = Completer<int?>();

      await tester.pumpWidget(
        MaterialApp(
          home: ForgottenPassword(
            requestPasswordReset: (_) => response.future,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'bird@example.test',
      );
      await tester.tap(find.byKey(const Key('forgotten-password-submit')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      response.complete(200);
      await tester.pump();

      expect(find.byType(ResetEmailSent), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('success replaces the request screen',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgottenPassword(
            requestPasswordReset: (_) async => 200,
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'bird@example.test',
      );
      await tester.tap(find.byKey(const Key('forgotten-password-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ForgottenPassword), findsNothing);
      expect(find.byType(ResetEmailSent), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mock request exception is handled while mounted',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ForgottenPassword(
            requestPasswordReset: (_) async {
              throw StateError('mock API failure');
            },
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextFormField),
        'bird@example.test',
      );
      await tester.tap(find.byKey(const Key('forgotten-password-submit')));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Error sending the request. Check your connection.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ChangePassword with mocked submit boundary', () {
    testWidgets('malformed link never invokes the submit boundary',
        (WidgetTester tester) async {
      int calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePassword(
            jwt: 'malformed',
            submitPasswordReset: ({
              required String email,
              required String token,
              required String password,
            }) async {
              calls += 1;
              return 200;
            },
          ),
        ),
      );
      await _enterValidPassword(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pump();

      expect(calls, 0);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('This password reset link is invalid or has expired.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid submits produce one reset request',
        (WidgetTester tester) async {
      final Completer<int?> response = Completer<int?>();
      int calls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePassword(
            jwt: _resetToken(),
            submitPasswordReset: ({
              required String email,
              required String token,
              required String password,
            }) {
              calls += 1;
              expect(email, 'bird@example.test');
              expect(password, 'Strongpass1');
              return response.future;
            },
          ),
        ),
      );
      await _enterValidPassword(tester);

      final Finder submit = find.byKey(const Key('change-password-submit'));
      await tester.tap(submit);
      await tester.tap(submit);
      expect(calls, 1);

      await tester.pump();
      expect(tester.widget<ElevatedButton>(submit).onPressed, isNull);

      response.complete(400);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('late reset result after disposal does not navigate',
        (WidgetTester tester) async {
      final Completer<int?> response = Completer<int?>();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangePassword(
            jwt: _resetToken(),
            submitPasswordReset: ({
              required String email,
              required String token,
              required String password,
            }) =>
                response.future,
          ),
        ),
      );
      await _enterValidPassword(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      response.complete(200);
      await tester.pump();

      expect(find.byType(PasswordChangedScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('successful mocked reset replaces the form',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangePassword(
            jwt: _resetToken(),
            submitPasswordReset: ({
              required String email,
              required String token,
              required String password,
            }) async =>
                200,
          ),
        ),
      );
      await _enterValidPassword(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePassword), findsNothing);
      expect(find.byType(PasswordChangedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mock submit exception shows a connection error',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChangePassword(
            jwt: _resetToken(),
            submitPasswordReset: ({
              required String email,
              required String token,
              required String password,
            }) async {
              throw StateError('mock API failure');
            },
          ),
        ),
      );
      await _enterValidPassword(tester);
      await tester.tap(find.byKey(const Key('change-password-submit')));
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          'The password could not be changed because the server could not be reached.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  test('password-reset safety tests cannot use a real API or database', () {
    for (final String path in <String>[
      'test/auth/password_reset_safety_test.dart',
      'test/PostRecordingForm/image_upload_safety_test.dart',
    ]) {
      final String source = File(path).readAsStringSync();
      expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
      expect(source, isNot(contains(<String>['open', 'Database('].join())));
      expect(
        source,
        isNot(contains(<String>['DatabaseNew', 'database'].join('.'))),
      );
    }
  });
}
