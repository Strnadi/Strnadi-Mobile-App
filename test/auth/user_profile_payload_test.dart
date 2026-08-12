import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/user_profile_payload.dart';

void main() {
  group('cached user profile parsing (no API or DB)', () {
    test('accepts typed maps and JSON strings', () {
      for (final Object payload in <Object>[
        <String, Object?>{
          'firstName': 'Ada',
          'lastName': 'Bird',
          'nickname': 'Swift',
          'role': 'user',
        },
        '{"firstName":"Ada","lastName":"Bird",'
            '"nickname":null,"role":"user"}',
      ]) {
        final CachedUserProfile? result = parseCachedUserProfile(payload);
        expect(result, isNotNull);
        expect(result!.firstName, 'Ada');
        expect(result.lastName, 'Bird');
      }
    });

    test('rejects status-page text, malformed JSON, arrays, and missing names',
        () {
      for (final Object? payload in <Object?>[
        null,
        'Internal Server Error',
        '{"firstName":',
        <Object?>[],
        <String, Object?>{'firstName': 'Ada'},
        <String, Object?>{
          'firstName': 7,
          'lastName': 'Bird',
        },
        <String, Object?>{
          'firstName': 'Ada',
          'lastName': 'Bird',
          'nickname': 7,
        },
      ]) {
        expect(parseCachedUserProfile(payload), isNull);
      }
    });
  });

  test('startup restoration awaits its loader and validates profile payload',
      () {
    final String source = File('lib/auth/authorizator.dart').readAsStringSync();
    final int start = source.indexOf('Future<void> checkLoggedIn()');
    final int end = source.indexOf('void _showMessage', start);
    final String restoration = source.substring(start, end);

    expect(restoration, contains('await _withLoader(() async'));
    expect(restoration, contains('parseCachedUserProfile(response.data)'));
    expect(restoration, contains('if (profile == null)'));
    expect(restoration, contains('catch (error, stackTrace)'));
    expect(restoration, isNot(contains('JwtDecoder.decode(token)')));
  });
}
