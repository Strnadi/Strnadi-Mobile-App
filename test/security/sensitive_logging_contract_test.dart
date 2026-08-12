import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sensitive logging contract (source only; no API or DB)', () {
    test('reset links are redacted before logging', () {
      final String source =
          File('lib/deep_link_handler.dart').readAsStringSync();

      expect(source, contains('LogRedactor.redactUri(uri)'));
      expect(source, isNot(contains(r"Received deep link: $uri")));
    });

    test('map credentials and recording details are not logged', () {
      final String list =
          File('lib/localRecordings/recList.dart').readAsStringSync();
      final String item =
          File('lib/localRecordings/recListItem.dart').readAsStringSync();
      final String form =
          File('lib/PostRecordingForm/RecordingForm.dart').readAsStringSync();
      final String map = File('lib/map/RecordingPage.dart').readAsStringSync();
      final String part =
          File('lib/database/Models/recordingPart.dart').readAsStringSync();

      for (final String source in <String>[list, item, form, map]) {
        expect(source, isNot(contains('reverse geocode url:')));
      }
      expect(form, isNot(contains('Reverse geocode result:')));
      expect(list, isNot(contains('All parts:')));
      expect(list, isNot(contains(r'${part.toJson()}')));
      expect(part, isNot(contains(r'gpsLatitudeStart: ${')));
      expect(part, isNot(contains(r'path: ${unready.path}')));
    });

    test('authentication response bodies are never written to logs', () {
      for (final String path in <String>[
        'lib/auth/unverifiedEmail.dart',
        'lib/auth/registeration/emailSent.dart',
        'lib/auth/passReset/newPassword.dart',
        'lib/auth/passReset/forgottenPassword.dart',
      ]) {
        final String source = File(path).readAsStringSync();
        expect(
          source,
          isNot(contains(r'${response.data}')),
          reason: '$path must not log authentication response bodies.',
        );
      }
    });

    test('profile and upload payloads are summarized rather than logged', () {
      final String profile =
          File('lib/user/settingsPages/userInfo.dart').readAsStringSync();
      final String achievements =
          File('lib/user/settingsPages/achievementsPage.dart')
              .readAsStringSync();
      final String background =
          File('lib/callback_dispatcher.dart').readAsStringSync();
      final String repository =
          File('lib/database/src/database_repository.dart').readAsStringSync();
      final String repositoryApi =
          File('lib/database/src/database_repository_api.dart')
              .readAsStringSync();
      final String recording =
          File('lib/database/Models/recording.dart').readAsStringSync();

      expect(profile, isNot(contains(r'Fetched user: $responseData')));
      expect(profile, isNot(contains('logger.i(jsonEncode(updatedData))')));
      expect(achievements, isNot(contains(r"logger.i('$token')")));
      expect(achievements, isNot(contains('logger.i(parsed)')));
      expect(background, isNot(contains(r'Dialect body: $body')));
      expect(repository, isNot(contains(r'dialect: ${dialect.toJson()}')));
      expect(
        repositoryApi,
        isNot(contains('Sending recording with body:')),
      );
      expect(
        recording,
        isNot(contains('Generated BE JSON for Recording:')),
      );
      expect(
        repository,
        isNot(contains(r'path: ${recording.path}')),
      );
    });
  });
}
