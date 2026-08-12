import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String repositorySource;
  late String settingsSource;
  late String accessSource;

  setUpAll(() {
    repositorySource =
        File('lib/database/src/database_repository.dart').readAsStringSync();
    settingsSource =
        File('lib/user/settingsPages/appSettings.dart').readAsStringSync();
    accessSource =
        File('lib/database/recording_cache_access.dart').readAsStringSync();
  });

  test('settings list is scoped to exact activated owner and environment', () {
    final String body = _methodBody(
      repositorySource,
      'static Future<List<Recording>> '
      'getDownloadedRecordingsForCurrentUser() async',
    );

    expect(
      body,
      contains('listDownloadedRecordingCacheForActivatedOwner<Recording>'),
    );
    expect(body, contains('AND env = ? AND userId = ?'));
    expect(
      body,
      contains("LOWER(TRIM(COALESCE(mail, ''))) = ?"),
    );
    expect(body, contains('owner.environment'));
    expect(body, contains('owner.userId'));
    expect(body, contains('owner.normalizedEmail'));
    expect(body, isNot(contains('across environments')));
  });

  test('guest list does not touch persistence and stale reads fail closed', () {
    expect(
      accessSource,
      contains('if (session == null) return <T>[];'),
    );
    expect(
      accessSource,
      contains('final List<T> entries = await loadOwnedEntries(owner);'),
    );
    final int loadIndex = accessSource.indexOf('await loadOwnedEntries(owner)');
    final int finalGuardIndex = accessSource.indexOf(
      'await _requireSessionCurrent(sessions, session);',
      loadIndex,
    );
    expect(finalGuardIndex, greaterThan(loadIndex));
  });

  test('settings uses owner-scoped deletion entry point', () {
    expect(
      settingsSource,
      contains('deleteDownloadedRecordingFromCurrentUserCache'),
    );
    expect(
      settingsSource,
      isNot(contains(
        'await DatabaseNew.deleteRecordingFromCache(item.recording.id!)',
      )),
    );
  });

  test('settings deletion query repeats exact owner cache scope', () {
    final String body = _methodBody(
      repositorySource,
      'static Future<void> '
      'deleteDownloadedRecordingFromCurrentUserCache(',
    );

    expect(body, contains('deleteDownloadedRecordingCacheForActivatedOwner'));
    expect(body, contains('cacheOwner: owner'));
    expect(body, contains('requireDownloadedCache: true'));
    expect(body, contains('requirePinnedSessionCurrent'));

    final String claimBody = _sourceBetween(
      repositorySource,
      'static Future<_RecordingDeletionClaim> _claimRecordingDeletion(',
      'static Future<void> _deleteClaimedRecordingLocally(',
    );
    expect(claimBody, contains('id = ? AND env = ? AND userId = ?'));
    expect(
      claimBody,
      contains("LOWER(TRIM(COALESCE(mail, ''))) = ?"),
    );
    expect(claimBody, contains('AND downloaded = 1'));
    expect(claimBody, contains('await requirePinnedSessionCurrent();'));
  });

  test('internal unscoped cache deletion remains separate from settings', () {
    final String internalBody = _methodBody(
      repositorySource,
      'static Future<void> deleteRecordingFromCache(int id) async',
    );
    expect(internalBody, contains('environment: null'));
    expect(internalBody, contains('requireRemoteSession: false'));
    expect(
      repositorySource,
      contains('User-facing Settings must'),
    );
  });

  test('settings async loads guard state commits after awaits', () {
    final String loadSettings = _methodBody(
      settingsSource,
      'Future<void> _loadSettings() async',
    );
    expect(loadSettings, contains('if (!mounted) return;'));
    expect(
      loadSettings.indexOf('if (!mounted) return;'),
      greaterThan(loadSettings.indexOf('getLocalRecordingsMax()')),
    );
    expect(
      loadSettings.indexOf('setState(() {'),
      greaterThan(loadSettings.indexOf('if (!mounted) return;')),
    );

    final String loadLanguage = _methodBody(
      settingsSource,
      'Future<void> _loadLanguage() async',
    );
    expect(loadLanguage, contains('if (!mounted) return;'));
    expect(
      loadLanguage.indexOf('setState(() {'),
      greaterThan(loadLanguage.indexOf('if (!mounted) return;')),
    );
  });

  test('language selection awaits loading before mounted-safe state update',
      () {
    expect(
      settingsSource,
      contains(
        "await Localization.load('assets/lang/\$newValue.json');\n"
        '          if (!mounted) return;\n'
        '          setState(() {',
      ),
    );
    expect(
      settingsSource,
      isNot(contains(
        "Localization.load('assets/lang/\$newValue.json').then",
      )),
    );
  });
}

String _sourceBetween(String source, String startMarker, String endMarker) {
  final int start = source.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  final int end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, greaterThan(start), reason: 'Missing $endMarker');
  return source.substring(start, end);
}

String _methodBody(String source, String signature) {
  final int start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
  final int openBrace = source.indexOf('{', start);
  expect(openBrace, greaterThan(start));

  var depth = 0;
  for (var index = openBrace; index < source.length; index++) {
    final String char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace, index + 1);
      }
    }
  }
  fail('Unterminated method $signature');
}
