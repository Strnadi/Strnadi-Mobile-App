import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/user/profile_account_safety.dart';

void main() {
  group('profile payload parsing', () {
    test('accepts map, JSON string, and UTF-8 byte payloads', () {
      const String json = '{"nickname":"bird","email":"bird@example.test",'
          '"firstName":"Ada","lastName":"Lovelace","postCode":"11000",'
          '"city":"Prague","role":"user"}';

      for (final Object payload in <Object>[
        <String, Object?>{
          'nickname': 'bird',
          'email': 'bird@example.test',
          'firstName': 'Ada',
          'lastName': 'Lovelace',
          'postCode': 11000,
          'city': 'Prague',
          'role': 'user',
        },
        json,
        json.codeUnits,
      ]) {
        final UserProfileData? profile = parseSuccessfulUserProfile(
          statusCode: 200,
          payload: payload,
        );
        expect(profile, isNotNull);
        expect(profile!.email, 'bird@example.test');
        expect(profile.postCode, 11000);
      }
    });

    test('checks status before decoding a malformed body', () {
      expect(
        parseSuccessfulUserProfile(statusCode: 503, payload: '{broken'),
        isNull,
      );
    });

    test('rejects malformed JSON, non-map data, and unsafe field types', () {
      for (final Object? payload in <Object?>[
        '{broken',
        <Object>[],
        <String, Object?>{'email': 123},
        <String, Object?>{'email': 'ok@example.test', 'postCode': 12.5},
        <String, Object?>{'email': 'ok@example.test', 'city': 42},
      ]) {
        expect(
          parseSuccessfulUserProfile(statusCode: 200, payload: payload),
          isNull,
        );
      }
    });
  });

  group('profile patch validation', () {
    test('trims values and parses postal codes without throwing', () {
      expect(
        buildUserProfilePatch(
          nickname: ' bird ',
          firstName: ' Ada ',
          lastName: ' ',
          postCode: ' 11000 ',
          city: ' Prague ',
        ),
        <String, Object?>{
          'nickname': 'bird',
          'firstName': 'Ada',
          'lastName': null,
          'postCode': 11000,
          'city': 'Prague',
        },
      );
    });

    test('rejects an invalid postal code instead of throwing FormatException',
        () {
      expect(
        buildUserProfilePatch(
          nickname: '',
          firstName: '',
          lastName: '',
          postCode: 'not-a-number',
          city: '',
        ),
        isNull,
      );
    });
  });

  group('profile photo cache identity', () {
    test('separates owners and environments', () {
      final String ownerOneProd = profilePhotoCacheKey(
        ownerUserId: '1',
        environment: 'prod',
      );
      final String ownerTwoProd = profilePhotoCacheKey(
        ownerUserId: '2',
        environment: 'prod',
      );
      final String ownerOneDev = profilePhotoCacheKey(
        ownerUserId: '1',
        environment: 'dev',
      );

      expect(<String>{ownerOneProd, ownerTwoProd, ownerOneDev}, hasLength(3));
      expect(ownerOneProd, contains('prod'));
      expect(ownerOneProd, contains('-1'));
    });

    test('rejects missing owners and environments', () {
      expect(
        () => profilePhotoCacheKey(ownerUserId: '', environment: 'prod'),
        throwsA(isA<ProfileAccountException>()),
      );
      expect(
        () => profilePhotoCacheKey(ownerUserId: '0', environment: 'prod'),
        throwsA(isA<ProfileAccountException>()),
      );
      expect(
        () => profilePhotoCacheKey(ownerUserId: '1', environment: ''),
        throwsA(isA<ProfileAccountException>()),
      );
    });

    test('normalizes safe image formats and rejects path-like extensions', () {
      expect(profilePhotoFormatFromPath('/mock/photo.PNG'), 'png');
      expect(profilePhotoFormatFromPath('/mock/photo'), 'jpg');
      expect(profilePhotoFormatFromPath('/mock/photo.bad/segment'), 'jpg');
    });
  });

  group('profile photo publication', () {
    const ProfilePhotoPublishCoordinator coordinator =
        ProfilePhotoPublishCoordinator();

    test('publishes only after backend acceptance and scoped cache commit',
        () async {
      final List<String> events = <String>[];

      final ProfilePhotoPublishOutcome outcome = await coordinator.publish(
        uploadCandidate: () async {
          events.add('upload');
          return 200;
        },
        isSessionCurrent: () async {
          events.add('session');
          return true;
        },
        commitScopedCache: () async {
          events.add('cache');
          return '/mock/scoped-cache/photo';
        },
        publishVisiblePath: (String cachedPath) async {
          events.add('visible:$cachedPath');
        },
      );

      expect(outcome, ProfilePhotoPublishOutcome.published);
      expect(events, <String>[
        'upload',
        'session',
        'cache',
        'session',
        'visible:/mock/scoped-cache/photo',
      ]);
    });

    test('upload rejection preserves the old cache and visible image',
        () async {
      int cacheWrites = 0;
      int visibleWrites = 0;

      final ProfilePhotoPublishOutcome outcome = await coordinator.publish(
        uploadCandidate: () async => 422,
        isSessionCurrent: () async => true,
        commitScopedCache: () async {
          cacheWrites++;
          return '/mock/new';
        },
        publishVisiblePath: (_) async {
          visibleWrites++;
        },
      );

      expect(outcome, ProfilePhotoPublishOutcome.uploadRejected);
      expect(cacheWrites, 0);
      expect(visibleWrites, 0);
    });

    test('transport failure preserves old state and propagates for UI handling',
        () async {
      int cacheWrites = 0;
      int visibleWrites = 0;
      final StateError failure = StateError('mock transport failure');

      await expectLater(
        coordinator.publish(
          uploadCandidate: () async => throw failure,
          isSessionCurrent: () async => true,
          commitScopedCache: () async {
            cacheWrites++;
            return '/mock/new';
          },
          publishVisiblePath: (_) async {
            visibleWrites++;
          },
        ),
        throwsA(same(failure)),
      );
      expect(cacheWrites, 0);
      expect(visibleWrites, 0);
    });

    test('session switch after upload never publishes the old account result',
        () async {
      int cacheWrites = 0;
      int visibleWrites = 0;

      final ProfilePhotoPublishOutcome outcome = await coordinator.publish(
        uploadCandidate: () async => 200,
        isSessionCurrent: () async => false,
        commitScopedCache: () async {
          cacheWrites++;
          return '/mock/new';
        },
        publishVisiblePath: (_) async {
          visibleWrites++;
        },
      );

      expect(outcome, ProfilePhotoPublishOutcome.sessionChanged);
      expect(cacheWrites, 0);
      expect(visibleWrites, 0);
    });

    test('session switch during cache commit does not alter visible state',
        () async {
      int checks = 0;
      int visibleWrites = 0;

      final ProfilePhotoPublishOutcome outcome = await coordinator.publish(
        uploadCandidate: () async => 200,
        isSessionCurrent: () async => ++checks == 1,
        commitScopedCache: () async => '/mock/old-account-cache',
        publishVisiblePath: (_) async {
          visibleWrites++;
        },
      );

      expect(outcome, ProfilePhotoPublishOutcome.sessionChanged);
      expect(visibleWrites, 0);
    });

    test('cache failure keeps the prior visible image', () async {
      int visibleWrites = 0;

      final ProfilePhotoPublishOutcome outcome = await coordinator.publish(
        uploadCandidate: () async => 200,
        isSessionCurrent: () async => true,
        commitScopedCache: () async => throw StateError('mock cache failure'),
        publishVisiblePath: (_) async {
          visibleWrites++;
        },
      );

      expect(outcome, ProfilePhotoPublishOutcome.cacheWriteFailed);
      expect(visibleWrites, 0);
    });

    test('oversized fake candidate is rejected before read or upload',
        () async {
      int reads = 0;
      int uploads = 0;

      await expectLater(
        coordinator.publishBoundedCandidate(
          candidateLength: () async => maxProfilePhotoBytes + 1,
          readCandidate: () async {
            reads++;
            return Uint8List(1);
          },
          uploadCandidate: (_) async {
            uploads++;
            return 200;
          },
          isSessionCurrent: () async => true,
          commitScopedCache: (_) async => '/mock/new',
          publishVisiblePath: (_) async {},
        ),
        throwsA(isA<ProfileAccountException>()),
      );

      expect(reads, 0);
      expect(uploads, 0);
    });

    test('candidate growth after stat is rejected before fake publisher',
        () async {
      int uploads = 0;

      await expectLater(
        coordinator.publishBoundedCandidate(
          maximumBytes: 4,
          candidateLength: () async => 3,
          readCandidate: () async => Uint8List(5),
          uploadCandidate: (_) async {
            uploads++;
            return 200;
          },
          isSessionCurrent: () async => true,
          commitScopedCache: (_) async => '/mock/new',
          publishVisiblePath: (_) async {},
        ),
        throwsA(isA<ProfileAccountException>()),
      );

      expect(uploads, 0);
    });

    test('bounded fake bytes are the exact bytes uploaded and cached',
        () async {
      final Uint8List candidate = Uint8List.fromList(<int>[1, 2, 3, 4]);
      Uint8List? uploaded;
      Uint8List? cached;

      final ProfilePhotoPublishOutcome outcome =
          await coordinator.publishBoundedCandidate(
        maximumBytes: 4,
        candidateLength: () async => candidate.length,
        readCandidate: () async => candidate,
        uploadCandidate: (Uint8List bytes) async {
          uploaded = bytes;
          return 200;
        },
        isSessionCurrent: () async => true,
        commitScopedCache: (Uint8List bytes) async {
          cached = bytes;
          return '/mock/new';
        },
        publishVisiblePath: (_) async {},
      );

      expect(outcome, ProfilePhotoPublishOutcome.published);
      expect(uploaded, same(candidate));
      expect(cached, same(candidate));
    });
  });

  test('profile tests cannot open a real API or database', () {
    final String source =
        File('test/user/profile_account_safety_test.dart').readAsStringSync();
    expect(source, isNot(contains(<String>['api', 'strnadi'].join('.'))));
    expect(source, isNot(contains(<String>['open', 'Database('].join())));
    expect(source, isNot(contains(<String>['Database', 'New'].join())));
    expect(source, isNot(contains(<String>['User', 'Controller'].join())));
  });
}
