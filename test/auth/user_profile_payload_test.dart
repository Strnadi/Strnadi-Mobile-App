import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/user_profile_payload.dart';

void main() {
  test('caches nullable metadata without retaining a previous role or nickname',
      () async {
    final values = <String, String?>{'nick': 'Old', 'role': 'admin'};
    await cacheUserProfileMetadata(
      {'firstName': 'Ada', 'lastName': 'Bird', 'nickname': null, 'role': null},
      write: (key, value) async => values[key] = value,
    );
    expect(values, {
      'firstName': 'Ada',
      'lastName': 'Bird',
      'nick': null,
      'role': null,
    });
  });

  test(
      'null, missing and malformed profile fields cannot crash metadata caching',
      () async {
    for (final payload in <Object?>[
      null,
      {'firstName': null, 'lastName': 'Bird'},
      {'firstName': 'Ada', 'lastName': null},
      {'firstName': 'Ada'},
      {'firstName': 7, 'lastName': 'Bird'},
      'Invalid JSON',
    ]) {
      final values = <String, String?>{'role': 'admin'};
      await cacheUserProfileMetadata(
        payload,
        write: (key, value) async => values[key] = value,
      );
      expect(values, {
        'firstName': null,
        'lastName': null,
        'nick': null,
        'role': null,
      });
    }
  });

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
