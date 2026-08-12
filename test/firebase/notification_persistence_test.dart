import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/firebase/notification_persistence.dart';

void main() {
  group('notificationPersistenceValues (pure; no SQLite)', () {
    test('normalizes a notification into SQLite-supported values', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Title',
        notificationBody: 'Body',
        messageType: '7',
        data: const <String, dynamic>{},
        sentTime: DateTime.parse('2026-07-18T12:30:00+02:00'),
        ownerUserId: '42',
        environment: 'prod',
      );

      expect(values, <String, Object>{
        'title': 'Title',
        'body': 'Body',
        'receivedAt': '2026-07-18T10:30:00.000Z',
        'type': 7,
        'read': 0,
        'ownerUserId': '42',
        'env': 'prod',
      });
      expect(
        values.values.whereType<DateTime>(),
        isEmpty,
        reason: 'sqflite does not accept DateTime values directly.',
      );
    });

    test('notification title and body win over data fallbacks', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Native title',
        notificationBody: 'Native body',
        messageType: 1,
        data: const <String, dynamic>{
          'title': 'Data title',
          'body': 'Data body',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
      );

      expect(values['title'], 'Native title');
      expect(values['body'], 'Native body');
    });

    test('uses generic data title and body when notification is absent', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: null,
        notificationBody: null,
        messageType: null,
        data: const <String, dynamic>{
          'title': 'Data title',
          'body': 'Data body',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
      );

      expect(values['title'], 'Data title');
      expect(values['body'], 'Data body');
      expect(values['type'], 0);
    });

    test('uses a deterministic localized fallback order', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: ' ',
        notificationBody: '',
        messageType: 'gcm',
        data: const <String, dynamic>{
          'titleCs': 'Český název',
          'titleDe': 'Deutscher Titel',
          'bodyCs': 'Český text',
          'bodyDe': 'Deutscher Text',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
      );

      expect(values['title'], 'Český název');
      expect(values['body'], 'Český text');
      expect(values['type'], 0);
    });

    test('uses the current Czech locale for data-only notification history',
        () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: null,
        notificationBody: null,
        messageType: 0,
        data: const <String, dynamic>{
          'titleEn': 'English title',
          'titleCs': 'Český název',
          'titleDe': 'Deutscher Titel',
          'bodyEn': 'English body',
          'bodyCs': 'Český text',
          'bodyDe': 'Deutscher Text',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
        preferredLanguageCode: ' cs ',
      );

      expect(values['title'], 'Český název');
      expect(values['body'], 'Český text');
    });

    test('uses the current German locale for data-only notification history',
        () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: null,
        notificationBody: null,
        messageType: 0,
        data: const <String, dynamic>{
          'titleEn': 'English title',
          'titleDe': 'Deutscher Titel',
          'bodyEn': 'English body',
          'bodyDe': 'Deutscher Text',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
        preferredLanguageCode: 'DE',
      );

      expect(values['title'], 'Deutscher Titel');
      expect(values['body'], 'Deutscher Text');
    });

    test('native notification text still wins over locale data', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Native title',
        notificationBody: 'Native body',
        messageType: 0,
        data: const <String, dynamic>{
          'titleCs': 'Český název',
          'bodyCs': 'Český text',
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
        preferredLanguageCode: 'cs',
      );

      expect(values['title'], 'Native title');
      expect(values['body'], 'Native body');
    });

    test('normalizes the provider message id used for scoped deduplication',
        () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Title',
        notificationBody: 'Body',
        messageType: 0,
        data: const <String, dynamic>{},
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
        providerMessageId: ' provider-message-1 ',
      );

      expect(values['providerMessageId'], 'provider-message-1');
    });

    test('omits missing provider ids so unrelated pushes are not collapsed',
        () {
      for (final Object? id in <Object?>[null, '', ' \n ']) {
        final Map<String, Object> values = notificationPersistenceValues(
          notificationTitle: 'Title',
          notificationBody: 'Body',
          messageType: 0,
          data: const <String, dynamic>{},
          sentTime: DateTime.utc(2026),
          ownerUserId: '42',
          environment: 'prod',
          providerMessageId: id,
        );

        expect(values, isNot(contains('providerMessageId')));
      }
    });

    test('supplies non-null defaults required by the schema', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: null,
        notificationBody: null,
        messageType: null,
        data: const <String, dynamic>{},
        sentTime: null,
        ownerUserId: '42',
        environment: 'prod',
        now: () => DateTime.utc(2026, 7, 18, 1, 2, 3),
      );

      expect(values['title'], 'Strnadi');
      expect(values['body'], '');
      expect(values['receivedAt'], '2026-07-18T01:02:03.000Z');
      expect(values['type'], 0);
      expect(values['read'], 0);
    });

    test('accepts integral numeric message types', () {
      for (final Object type in <Object>[3, 4.0, '5']) {
        final Map<String, Object> values = notificationPersistenceValues(
          notificationTitle: 'Title',
          notificationBody: 'Body',
          messageType: type,
          data: const <String, dynamic>{},
          sentTime: DateTime.utc(2026),
          ownerUserId: '42',
          environment: 'prod',
        );

        expect(values['type'],
            <Object>[3, 4, 5][<Object>[3, 4.0, '5'].indexOf(type)]);
      }
    });

    test('rejects fractional, non-numeric, and non-finite message types', () {
      for (final Object type in <Object>[
        1.5,
        'push',
        double.nan,
        double.infinity
      ]) {
        final Map<String, Object> values = notificationPersistenceValues(
          notificationTitle: 'Title',
          notificationBody: 'Body',
          messageType: type,
          data: const <String, dynamic>{},
          sentTime: DateTime.utc(2026),
          ownerUserId: '42',
          environment: 'prod',
        );

        expect(values['type'], 0);
      }
    });

    test('does not persist unrelated or sensitive data-map fields', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Title',
        notificationBody: 'Body',
        messageType: 0,
        data: const <String, dynamic>{
          'token': 'secret-token',
          'userEmail': 'person@example.test',
          'customPayload': <String, Object>{'private': true},
        },
        sentTime: DateTime.utc(2026),
        ownerUserId: '42',
        environment: 'prod',
      );

      expect(values.toString(), isNot(contains('secret-token')));
      expect(values.toString(), isNot(contains('person@example.test')));
      expect(values.keys, <String>{
        'title',
        'body',
        'receivedAt',
        'type',
        'read',
        'ownerUserId',
        'env',
      });
    });

    test('normalizes owner and environment scope', () {
      final Map<String, Object> values = notificationPersistenceValues(
        notificationTitle: 'Title',
        notificationBody: 'Body',
        messageType: 0,
        data: const <String, dynamic>{},
        sentTime: DateTime.utc(2026),
        ownerUserId: ' 42 ',
        environment: ' dev ',
      );

      expect(values['ownerUserId'], '42');
      expect(values['env'], 'dev');
    });

    test('rejects an invalid owner instead of creating an unscoped row', () {
      for (final String owner in <String>['', ' ', '0', '-1', 'guest']) {
        expect(
          () => notificationPersistenceValues(
            notificationTitle: 'Title',
            notificationBody: 'Body',
            messageType: 0,
            data: const <String, dynamic>{},
            sentTime: DateTime.utc(2026),
            ownerUserId: owner,
            environment: 'prod',
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects an empty environment instead of creating an unscoped row',
        () {
      expect(
        () => notificationPersistenceValues(
          notificationTitle: 'Title',
          notificationBody: 'Body',
          messageType: 0,
          data: const <String, dynamic>{},
          sentTime: DateTime.utc(2026),
          ownerUserId: '42',
          environment: ' ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('notificationRetentionDeletePlan (pure; no SQLite)', () {
    test('keeps only the newest bounded rows for one exact account and env',
        () {
      final NotificationRetentionDeletePlan plan =
          notificationRetentionDeletePlan(
        ownerUserId: ' 42 ',
        environment: ' dev ',
      );

      expect(
        plan.where,
        contains('ownerUserId = ? AND env = ? AND id NOT IN'),
      );
      expect(
        plan.where,
        contains('WHERE ownerUserId = ? AND env = ?'),
      );
      expect(
        plan.where,
        contains('ORDER BY receivedAt DESC, id DESC LIMIT ?'),
      );
      expect(
        plan.whereArgs,
        <Object?>[
          '42',
          'dev',
          '42',
          'dev',
          notificationHistoryRetentionLimit,
        ],
      );
    });

    test('supports an explicit smaller test retention window', () {
      final NotificationRetentionDeletePlan plan =
          notificationRetentionDeletePlan(
        ownerUserId: '7',
        environment: 'prod',
        limit: 3,
      );

      expect(plan.whereArgs.last, 3);
    });

    test('rejects unscoped or unbounded pruning plans', () {
      for (final String owner in <String>['', '0', '-1', 'guest']) {
        expect(
          () => notificationRetentionDeletePlan(
            ownerUserId: owner,
            environment: 'prod',
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => notificationRetentionDeletePlan(
          ownerUserId: '42',
          environment: ' ',
        ),
        throwsArgumentError,
      );
      expect(
        () => notificationRetentionDeletePlan(
          ownerUserId: '42',
          environment: 'prod',
          limit: 0,
        ),
        throwsRangeError,
      );
    });
  });
}
