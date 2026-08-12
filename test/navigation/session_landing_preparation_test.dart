import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/navigation/session_landing_preparation.dart';

void main() {
  group('session landing preparation (mocked session and DB)', () {
    test('guest session skips draft adoption', () async {
      final List<String> calls = <String>[];

      final bool ready = await prepareSessionLanding(
        captureActiveVerifiedSessionId: () async {
          calls.add('session');
          return null;
        },
        adoptGuestDrafts: () async {
          calls.add('adopt');
        },
      );

      expect(ready, isFalse);
      expect(calls, <String>['session']);
    });

    test('verified session awaits adoption before its final check', () async {
      final List<String> calls = <String>[];
      int sessionChecks = 0;

      final bool ready = await prepareSessionLanding(
        captureActiveVerifiedSessionId: () async {
          sessionChecks++;
          calls.add('session-$sessionChecks');
          return 'session-a';
        },
        adoptGuestDrafts: () async {
          calls.add('adopt');
        },
      );

      expect(ready, isTrue);
      expect(calls, <String>['session-1', 'adopt', 'session-2']);
    });

    test('does not complete while mocked DB adoption is pending', () async {
      final Completer<void> adoption = Completer<void>();
      final List<String> calls = <String>[];
      bool completed = false;

      final Future<bool> preparation = prepareSessionLanding(
        captureActiveVerifiedSessionId: () async {
          calls.add('session');
          return 'session-a';
        },
        adoptGuestDrafts: () {
          calls.add('adopt');
          return adoption.future;
        },
      )..whenComplete(() {
          completed = true;
        });

      await Future<void>.delayed(Duration.zero);
      expect(calls, <String>['session', 'adopt']);
      expect(completed, isFalse);

      adoption.complete();
      expect(await preparation, isTrue);
      expect(completed, isTrue);
      expect(calls, <String>['session', 'adopt', 'session']);
    });

    test('mocked DB failure propagates and prevents the final session check',
        () async {
      final StateError failure = StateError('mocked adoption failed');
      int sessionChecks = 0;

      await expectLater(
        prepareSessionLanding(
          captureActiveVerifiedSessionId: () async {
            sessionChecks++;
            return 'session-a';
          },
          adoptGuestDrafts: () async {
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );

      expect(sessionChecks, 1);
    });

    test('session loss during adoption fails closed', () async {
      final List<String?> sessions = <String?>['session-a', null];
      int sessionChecks = 0;
      int adoptions = 0;

      final bool ready = await prepareSessionLanding(
        captureActiveVerifiedSessionId: () async {
          final String? current = sessions[sessionChecks];
          sessionChecks++;
          return current;
        },
        adoptGuestDrafts: () async {
          adoptions++;
        },
      );

      expect(ready, isFalse);
      expect(sessionChecks, 2);
      expect(adoptions, 1);
    });

    test('account switch during adoption fails closed', () async {
      final List<String> sessions = <String>['session-a', 'session-b'];
      int sessionChecks = 0;

      final bool ready = await prepareSessionLanding(
        captureActiveVerifiedSessionId: () async {
          final String current = sessions[sessionChecks];
          sessionChecks++;
          return current;
        },
        adoptGuestDrafts: () async {},
      );

      expect(ready, isFalse);
      expect(sessionChecks, 2);
    });
  });
}
