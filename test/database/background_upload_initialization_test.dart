import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/background_upload_initialization.dart';

void main() {
  test('notification failure does not prevent localization or upload startup',
      () async {
    final List<String> calls = <String>[];
    final List<String> failures = <String>[];

    await initializeBackgroundUploadRuntime(
      initializeEssentialConfiguration: () async {
        calls.add('configuration');
      },
      initializeNotifications: () async {
        calls.add('notifications');
        throw StateError('mock notification plugin unavailable');
      },
      initializeLocalization: () async {
        calls.add('localization');
      },
      onAncillaryFailure: (String step, Object error, StackTrace stackTrace) {
        failures.add('$step:$error');
      },
    );

    expect(
      calls,
      <String>['configuration', 'notifications', 'localization'],
    );
    expect(failures, <String>[
      'notifications:Bad state: mock notification plugin unavailable',
    ]);
  });

  test('localization failure remains ancillary', () async {
    final List<String> calls = <String>[];

    await initializeBackgroundUploadRuntime(
      initializeEssentialConfiguration: () async {
        calls.add('configuration');
      },
      initializeNotifications: () async {
        calls.add('notifications');
      },
      initializeLocalization: () async {
        calls.add('localization');
        throw StateError('mock localization asset unavailable');
      },
    );

    expect(
      calls,
      <String>['configuration', 'notifications', 'localization'],
    );
  });

  test('configuration failure fails closed before ancillary setup', () async {
    final List<String> calls = <String>[];

    await expectLater(
      initializeBackgroundUploadRuntime(
        initializeEssentialConfiguration: () async {
          calls.add('configuration');
          throw StateError('mock missing backend configuration');
        },
        initializeNotifications: () async {
          calls.add('notifications');
        },
        initializeLocalization: () async {
          calls.add('localization');
        },
      ),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          'mock missing backend configuration',
        ),
      ),
    );

    expect(calls, <String>['configuration']);
  });

  test('a broken diagnostic reporter cannot suppress upload startup', () async {
    final List<String> calls = <String>[];

    await initializeBackgroundUploadRuntime(
      initializeEssentialConfiguration: () async {
        calls.add('configuration');
      },
      initializeNotifications: () async {
        calls.add('notifications');
        throw StateError('mock plugin failure');
      },
      initializeLocalization: () async {
        calls.add('localization');
      },
      onAncillaryFailure: (_, __, ___) {
        throw StateError('mock logger failure');
      },
    );

    expect(
      calls,
      <String>['configuration', 'notifications', 'localization'],
    );
  });
}
