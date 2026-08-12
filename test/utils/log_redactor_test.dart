import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/utils/log_redactor.dart';

void main() {
  group('LogRedactor', () {
    test('redacts secrets recursively without mutating safe values', () {
      final Map<String, dynamic> redacted = LogRedactor.redactMap(
        <String, dynamic>{
          'Authorization': 'Bearer secret',
          'profile': <String, dynamic>{
            'accessToken': 'jwt',
            'displayName': 'Tester',
          },
          'items': <Map<String, String>>[
            <String, String>{'api_key': 'maps-secret', 'id': '7'},
          ],
        },
      );

      expect(redacted['Authorization'], LogRedactor.redacted);
      expect(
        (redacted['profile'] as Map<String, dynamic>)['accessToken'],
        LogRedactor.redacted,
      );
      expect(
        (redacted['profile'] as Map<String, dynamic>)['displayName'],
        'Tester',
      );
      expect(
        ((redacted['items'] as List<dynamic>).single
            as Map<String, dynamic>)['api_key'],
        LogRedactor.redacted,
      );
    });

    test('redacts reset tokens, JWT paths, and map query credentials', () {
      final Uri reset = LogRedactor.redactUri(
        Uri.parse(
          'https://example.test/ucet/obnova-hesla'
          '?token=header.payload.signature&safe=1',
        ),
      );
      final Uri map = LogRedactor.redactUri(
        Uri.parse('https://api.mapy.cz/v1/rgeocode?apikey=secret&lat=50'),
      );
      final Uri pathToken = LogRedactor.redactUri(
        Uri.parse(
          'https://example.test/token/'
          'header.payload.signature/reset-password',
        ),
      );

      expect(reset.queryParameters['token'], LogRedactor.redacted);
      expect(reset.queryParameters['safe'], '1');
      expect(map.queryParameters['apikey'], LogRedactor.redacted);
      expect(pathToken.pathSegments, contains(LogRedactor.redacted));
      expect(pathToken.toString(), isNot(contains('header.payload.signature')));
    });
  });
}
