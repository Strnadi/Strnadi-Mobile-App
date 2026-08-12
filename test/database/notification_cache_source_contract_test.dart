import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final String repository =
      File('lib/database/src/database_repository.dart').readAsStringSync();
  final String migrations =
      File('lib/database/src/database_migrations.dart').readAsStringSync();
  final String firebase = File('lib/firebase/firebase.dart').readAsStringSync();
  final String mainSource = File('lib/main.dart').readAsStringSync();

  group('notification schema v17 contract (source only; no SQLite)', () {
    test('fresh databases require owner, environment, and provider id columns',
        () {
      expect(repository, contains("openDatabase('soundNew.db', version: 17"));
      expect(
        RegExp(r'ownerUserId TEXT NOT NULL')
            .allMatches('$repository\n$migrations')
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        RegExp(r'env TEXT NOT NULL')
            .allMatches('$repository\n$migrations')
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        RegExp(r'providerMessageId TEXT')
            .allMatches('$repository\n$migrations')
            .length,
        greaterThanOrEqualTo(2),
      );
    });

    test('v16 migration adds nullable scope without guessing legacy owners',
        () {
      final int start = repository.indexOf('if (oldVersion <= 16)');
      final int end =
          repository.indexOf('await db.setVersion(newVersion);', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final String upgrade = repository.substring(start, end);

      expect(
        upgrade,
        contains(
          "await _ensureColumn(db, 'Notifications', 'ownerUserId', 'TEXT')",
        ),
      );
      expect(
        upgrade,
        contains("await _ensureColumn(db, 'Notifications', 'env', 'TEXT')"),
      );
      expect(upgrade, contains("'providerMessageId'"));
      expect(upgrade, contains('_createNotificationScopeIndex(db)'));
      expect(
        upgrade,
        isNot(contains('UPDATE Notifications SET')),
        reason: 'Legacy rows have no trustworthy account/environment owner.',
      );
    });

    test('the owner/environment/read lookup has a composite index', () {
      expect(
        migrations,
        contains(
          'ON Notifications(ownerUserId, env, read, receivedAt)',
        ),
      );
    });

    test('provider deduplication is unique only within owner and environment',
        () {
      expect(
        migrations,
        contains(
          'ON Notifications(ownerUserId, env, providerMessageId)',
        ),
      );
      expect(
        migrations,
        contains('WHERE providerMessageId IS NOT NULL'),
      );
    });
  });

  group('notification repository ownership contract (source only)', () {
    test('insert captures scope and compensates a stale-session write', () {
      final String method = _methodBetween(
        repository,
        'static Future<void> insertNotification',
        '// New helper method to insert a custom local notification.',
      );

      expect(method, contains('_notificationCacheIsolation()'));
      expect(method, contains('await isolation.persist('));
      expect(method, contains('ownerUserId: scope.ownerUserId'));
      expect(method, contains('environment: scope.environment'));
      expect(
        method,
        contains("where: 'id = ? AND ownerUserId = ? AND env = ?'"),
      );
      expect(
        method,
        isNot(contains("await db.insert('Notifications', values);\n")),
        reason: 'Persistence must be owned by the isolation coordinator.',
      );
    });

    test('insert deduplicates and prunes inside one scoped transaction', () {
      final String method = _methodBetween(
        repository,
        'static Future<void> insertNotification',
        '// New helper method to insert a custom local notification.',
      );

      expect(method, contains('providerMessageId: message.messageId'));
      expect(method, contains('db.transaction<int>'));
      expect(method, contains('ConflictAlgorithm.ignore'));
      expect(method, contains('notificationRetentionDeletePlan('));
      expect(method, contains('ownerUserId: scope.ownerUserId'));
      expect(method, contains('environment: scope.environment'));
      expect(
          method, contains("transaction.delete(\n            'Notifications'"));
      expect(method, contains('where: retention.where'));
      expect(method, contains('whereArgs: retention.whereArgs'));
    });

    test('list can only query the captured owner and environment', () {
      final String method = _methodBetween(
        repository,
        'static Future<List<NotificationItem>> getNotificationList',
        'static Future<int> getUnreadNotificationCount',
      );

      expect(method, contains('.readList<Map<String, Object?>>('));
      expect(method, contains("where: 'ownerUserId = ? AND env = ?'"));
      expect(
        method,
        contains(
          'whereArgs: <Object?>[scope.ownerUserId, scope.environment]',
        ),
      );
      expect(method, isNot(contains("db.query('Notifications');")));
    });

    test('unread count is scoped and session-revalidated', () {
      final String method = _methodBetween(
        repository,
        'static Future<int> getUnreadNotificationCount',
        'static Future<void> refreshUnreadNotificationCount',
      );

      expect(method, contains('_notificationCacheIsolation().readCount('));
      expect(
        method,
        contains('WHERE ownerUserId = ? AND env = ? AND read = 0'),
      );
      expect(method, isNot(contains('WHERE read = 0')));
    });

    test('mark-read never updates another account or environment', () {
      final String method = _methodBetween(
        repository,
        'static Future<void> markAllNotificationsAsRead',
        'static Future<void> deleteAllNotificationsForCurrentUser',
      );

      expect(method, contains('_notificationCacheIsolation().mutate('));
      expect(
        method,
        contains(
          "where: 'ownerUserId = ? AND env = ? AND read = 0'",
        ),
      );
      expect(method, isNot(contains("where: 'read = 0'")));
    });

    test('deletion removes only the captured account/environment rows', () {
      final String method = _methodBetween(
        repository,
        'static Future<void> deleteAllNotificationsForCurrentUser',
        'static Future<Recording?> getRecordingFromDbById',
      );

      expect(method, contains('_notificationCacheIsolation().mutate('));
      expect(method, contains("where: 'ownerUserId = ? AND env = ?'"));
      expect(
        method,
        contains(
          'whereArgs: <Object?>[scope.ownerUserId, scope.environment]',
        ),
      );
      expect(method, isNot(contains("db.delete('Notifications');")));
    });

    test('production scope requires loaded environment and activated session',
        () {
      final String factory = _methodBetween(
        repository,
        'static NotificationCacheIsolation _notificationCacheIsolation',
        '// Legacy in-memory hint retained',
      );

      expect(
        factory,
        contains('captureActivatedSession: activatedAuthSessions.capture'),
      );
      expect(
        factory,
        contains(
          'isActivatedSessionCurrent: activatedAuthSessions.isCurrent',
        ),
      );
      expect(factory, contains('Config.isHostEnvironmentLoaded'));
    });
  });

  group('background persistence contract (source only)', () {
    test('background isolate loads environment and awaits scoped persistence',
        () {
      final String handler = _methodBetween(
        firebase,
        'Future<void> _firebaseMessagingBackgroundHandler',
        'Future<void> addDevice',
      );

      expect(handler, contains('await Config.loadHostEnvironment()'));
      expect(
        handler.indexOf('await Config.loadHostEnvironment()'),
        lessThan(handler.indexOf('await DatabaseNew.insertNotification')),
      );
      expect(
        handler,
        contains('await DatabaseNew.insertNotification(message)'),
      );
    });

    test('environment switch refreshes the newly scoped unread badge', () {
      final String refreshBadge = _methodBetween(
        mainSource,
        'void refreshBadge()',
        '@override\n  Widget build',
      );

      expect(
        refreshBadge,
        contains(
          'unawaited(DatabaseNew.refreshUnreadNotificationCount())',
        ),
      );
    });
  });
}

String _methodBetween(String source, String startNeedle, String endNeedle) {
  final int start = source.indexOf(startNeedle);
  final int end = source.indexOf(endNeedle, start + startNeedle.length);
  expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
  expect(end, greaterThan(start), reason: endNeedle);
  return source.substring(start, end);
}
