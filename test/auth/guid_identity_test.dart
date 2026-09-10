import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/auth/activated_auth_session.dart';
import 'package:strnadi/auth/user_identity.dart';
import 'package:strnadi/database/Models/recording.dart';
import 'package:strnadi/database/draft_persistence_reconciliation.dart';
import 'package:strnadi/database/recording_upload_service.dart';

const guid = '01a08608-44b7-7aba-8d0c-542148b30bf2';

class MemoryStore implements AuthSessionKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test(
      'GUID normalization preserves numeric identities and rejects malformed values',
      () {
    expect(parseUserId(guid.toUpperCase()), guid);
    expect(parseUserId('42'), 42);
    expect(parseUserId(guid), isNot(42));
    for (final value in [
      null,
      '',
      0,
      -1,
      1.5,
      'person@example.test',
      'bad-id'
    ]) {
      expect(parseUserId(value), isNull);
    }
  });

  test('GUID activation survives renewal but not a project switch or logout',
      () async {
    final store = MemoryStore();
    var scope = 'preprod|project-a';
    final manager = ActivatedAuthSessionManager(
        store: store, subjectDecoder: (_) => guid, scopeProvider: () => scope);
    final transition = await manager.beginTokenTransition('project-token');
    final first = await manager.activate(transition, guid, verified: true);
    expect((await manager.capture())!.userId, guid);
    await manager.replaceCredential(first, 'renewed-project-token');
    final renewed = (await manager.capture())!;
    expect(renewed.sessionId, first.sessionId);
    expect(renewed.accessToken, 'renewed-project-token');
    scope = 'preprod|project-b';
    expect(await manager.capture(), isNull);
    scope = 'preprod|project-a';
    await manager.invalidate();
    expect(await manager.capture(), isNull);
    await expectLater(manager.replaceCredential(renewed, 'late-token'),
        throwsA(isA<ActivatedAuthSessionException>()));
  });

  test('GUID owner matches only its own durable draft, never a legacy owner',
      () {
    const snapshot = RecordingOwnerSnapshot.authenticated(
        accessToken: 'project-token',
        userId: guid,
        accountEmail: guid,
        logicalSessionId: 'login-a',
        environment: 'preprod|project-a',
        backendHost: 'preprod-api.strnadi.cz');
    bool matches(Object id, String env) => recordingOwnerBindingMatchesSnapshot(
        snapshot: snapshot,
        persistedUserId: id,
        persistedEmail: guid,
        persistedEnvironment: env);
    expect(matches(guid, snapshot.environment), isTrue);
    expect(matches(42, snapshot.environment), isFalse);
    expect(matches(guid, 'preprod'), isFalse);
    expect(matches(guid, 'preprod|project-b'), isFalse);
  });

  test('GUID recordings round-trip without touching SQLite', () {
    final json = <String, dynamic>{
      'id': 7,
      'userId': guid,
      'name': 'Bird',
      'createdAt': '2026-09-09',
      'env': 'preprod|project-a',
      'byApp': 1,
      'estimatedBirdsCount': 1,
      'sent': 0,
      'downloaded': 0,
      'sending': 0,
    };
    final recording = Recording.fromJson(json);
    expect(recording.userId, guid);
    expect(recording.toJson()['userId'], guid);
    const session = RecordingUploadSession(
        userId: guid,
        accessToken: 'project-token',
        logicalSessionId: 'login-a',
        environment: 'preprod|project-a',
        backendHost: 'preprod-api.strnadi.cz',
        accountEmail: guid);
    validateRecordingUploadSession(session);
    validateRecordingSessionBinding(recording, session);
    recording.userId = 42;
    expect(() => validateRecordingSessionBinding(recording, session),
        throwsA(isA<RecordingUploadSessionChangedException>()));
  });
}
