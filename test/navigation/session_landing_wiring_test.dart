import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('session landing wiring (source only; no API or DB)', () {
    test('navigation awaits adoption before choosing a route', () {
      final String source =
          File('lib/navigation/session_navigation.dart').readAsStringSync();
      final int method =
          source.indexOf('Future<void> navigateToSessionLanding');
      final int prepare =
          source.indexOf('await prepareSessionLanding(', method);
      final int sessionCapture =
          source.indexOf('captureActiveVerifiedSessionId:', prepare);
      final int adoption =
          source.indexOf('DatabaseNew.updateRecordingsMail', sessionCapture);
      final int mounted = source.indexOf('if (!context.mounted)', adoption);
      final int navigator = source.indexOf('Navigator.', mounted);

      expect(method, greaterThanOrEqualTo(0));
      expect(prepare, greaterThan(method));
      expect(sessionCapture, greaterThan(prepare));
      expect(adoption, greaterThan(sessionCapture));
      expect(mounted, greaterThan(adoption));
      expect(navigator, greaterThan(mounted));
    });

    test('verified authorizator routes use centralized awaited navigation', () {
      final String source =
          File('lib/auth/authorizator.dart').readAsStringSync();
      final int checkLoggedIn =
          source.indexOf('Future<void> checkLoggedIn() async');
      final int nextMethod = source.indexOf('void _showMessage', checkLoggedIn);
      final String restoration = source.substring(checkLoggedIn, nextMethod);

      expect(
        RegExp(r'await navigateToSessionLanding\(context\);')
            .allMatches(restoration),
        hasLength(2),
      );
      expect(restoration, isNot(contains('LiveRec(')));
    });

    test('only the explicit guest action directly enters LiveRec from auth',
        () {
      final RegExp liveRecorder = RegExp(r'(?:const\s+)?LiveRec\(');
      final Map<String, int> directRecorderRoutes = <String, int>{};
      for (final File file in Directory('lib/auth')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))) {
        final int count =
            liveRecorder.allMatches(file.readAsStringSync()).length;
        if (count > 0) directRecorderRoutes[file.path] = count;
      }

      expect(
        directRecorderRoutes,
        <String, int>{'lib/auth/authorizator.dart': 1},
      );
      final String authorizator =
          File('lib/auth/authorizator.dart').readAsStringSync();
      final RegExpMatch directGuestRoute =
          liveRecorder.firstMatch(authorizator)!;
      final int guestAction = authorizator.indexOf('continue_as_guest');
      expect(guestAction, greaterThanOrEqualTo(0));
      expect(directGuestRoute.start, lessThan(guestAction));
    });

    test('LiveRec no longer races navigation with fire-and-forget adoption',
        () {
      final String source =
          File('lib/recording/streamRec.dart').readAsStringSync();
      final int initState = source.indexOf('void initState()');
      final int nextMethod = source.indexOf('Future<void> _loadGuestStatus');
      final String initialization = source.substring(initState, nextMethod);

      expect(initialization, isNot(contains('updateRecordingsMail')));
    });
  });
}
