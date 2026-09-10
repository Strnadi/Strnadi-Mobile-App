import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/security/secure_storage_recovery.dart';

void main() {
  final decryptFailure = PlatformException(
    code: 'Exception encountered',
    message: 'javax.crypto.BadPaddingException: BAD_DECRYPT',
  );

  test('healthy credentials and preferences are untouched', () async {
    final deleted = <String>[];
    expect(
        await recoverUndecryptableCredentials(
          read: (key) async => 'readable',
          delete: (key) async => deleted.add(key),
        ),
        isFalse);
    expect(deleted, isEmpty);
  });

  for (final corruptKey in ['token', 'role', 'language']) {
    test(
        'repairs $corruptKey while preserving recordings and readable settings',
        () async {
      final values = <String, String>{
        'token': 'old-token',
        'userId': '42',
        'verified': 'true',
        'activatedAuthSession': 'old-session',
        'pendingAuthTransition': 'pending',
        'role': 'admin',
        'firstName': 'Old',
        'lastName': 'User',
        'nick': 'Old',
        'language': 'cs',
        'fcmTokenBinding': 'old-account-device-binding',
        'authSessionGeneration': '12',
        'recording-owner': '42',
        'recording-path': 'logical://audio.wav',
        'recording-backend-id': '900',
      };
      final deleted = <String>[];
      expect(
          await recoverUndecryptableCredentials(
            read: (key) async {
              if (key == corruptKey) throw decryptFailure;
              return values[key];
            },
            delete: (key) async {
              deleted.add(key);
              values.remove(key);
            },
          ),
          isTrue);
      expect(deleted.first, 'activatedAuthSession');
      expect(values.keys, isNot(contains('token')));
      expect(values.keys, isNot(contains('userId')));
      expect(values.keys, isNot(contains('role')));
      expect(values['fcmTokenBinding'], 'old-account-device-binding');
      expect(values['authSessionGeneration'], '12');
      expect(values['recording-owner'], '42');
      expect(values['recording-path'], 'logical://audio.wav');
      expect(values['recording-backend-id'], '900');
      expect(values['language'], corruptKey == 'language' ? isNull : 'cs');
      expect(
          await recoverUndecryptableCredentials(
            read: (key) async => values[key],
            delete: (key) async => fail('Already repaired'),
          ),
          isFalse);
    });
  }

  test('non-decryption platform errors never trigger credential deletion',
      () async {
    final unavailable =
        PlatformException(code: '-34018', message: 'Missing entitlement');
    final deleted = <String>[];
    await expectLater(
        recoverUndecryptableCredentials(
          read: (key) async {
            if (key == 'token') throw decryptFailure;
            if (key == 'role') throw unavailable;
            return null;
          },
          delete: (key) async => deleted.add(key),
        ),
        throwsA(same(unavailable)));
    expect(deleted, isEmpty);
  });

  test('partial cleanup removes activation before failing closed', () async {
    final deleted = <String>[];
    final failure = StateError('Mock storage is unavailable');
    await expectLater(
        recoverUndecryptableCredentials(
          read: (key) async => throw decryptFailure,
          delete: (key) async {
            if (key == 'token') throw failure;
            deleted.add(key);
          },
        ),
        throwsA(same(failure)));
    expect(deleted, ['activatedAuthSession', 'pendingAuthTransition']);
  });
}
