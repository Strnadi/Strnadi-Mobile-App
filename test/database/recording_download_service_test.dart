import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strnadi/database/recording_download_service.dart';
import 'package:strnadi/database/recording_upload_service.dart';
import 'package:strnadi/exceptions.dart';

void main() {
  group('RecordingDownloadService explicit identity', () {
    test('local-id lookup cannot collide with the same backend id', () async {
      final _FakeStore store = _FakeStore()
        ..localTargets[7] = _target(localId: 7, backendId: 99)
        ..backendTargets[7] = _target(localId: 3, backendId: 7)
        ..partsByLocalId[7] = <RecordingDownloadPart>[
          _part(localId: 701, backendId: 991, parentLocalId: 7, parentBeId: 99),
        ]
        ..partsByLocalId[3] = <RecordingDownloadPart>[
          _part(localId: 301, backendId: 71, parentLocalId: 3, parentBeId: 7),
        ];
      final _FakeApi api = _FakeApi();
      final RecordingDownloadService service = _service(store: store, api: api);

      expect(await service.downloadByLocalId(7), 7);

      expect(store.localLookups, <int>[7]);
      expect(store.backendLookups, isEmpty);
      expect(api.backendRecordingIds, <int>[99]);
      expect(store.commits.single.target.localId, 7);
    });

    test('backend-id lookup cannot collide with the same local id', () async {
      final _FakeStore store = _FakeStore()
        ..localTargets[7] = _target(localId: 7, backendId: 99)
        ..backendTargets[7] = _target(localId: 3, backendId: 7)
        ..partsByLocalId[3] = <RecordingDownloadPart>[
          _part(localId: 301, backendId: 71, parentLocalId: 3, parentBeId: 7),
        ];
      final _FakeApi api = _FakeApi();
      final RecordingDownloadService service = _service(store: store, api: api);

      expect(await service.downloadByBackendId(7), 3);

      expect(store.backendLookups, <int>[7]);
      expect(store.localLookups, isEmpty);
      expect(api.backendRecordingIds, <int>[7]);
      expect(store.commits.single.target.localId, 3);
    });

    test('invalid ids fail before session, API, file, or DB work', () async {
      final _FakeStore store = _FakeStore();
      final _FakeApi api = _FakeApi();
      final _FakeSessions sessions = _FakeSessions();
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        sessions: sessions,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(0),
        throwsA(isA<FetchException>()),
      );
      await expectLater(
        service.downloadByBackendId(-1),
        throwsA(isA<FetchException>()),
      );
      expect(sessions.captureCalls, 0);
      expect(api.calls, 0);
      expect(files.reserved, isEmpty);
      expect(store.commits, isEmpty);
    });
  });

  group('RecordingDownloadService session pinning', () {
    test('one verified logical session is reused for every boundary', () async {
      final _FakeStore store = _threePartStore();
      final _FakeApi api = _FakeApi();
      final _FakeSessions sessions = _FakeSessions();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        sessions: sessions,
      );

      await service.downloadByLocalId(10);

      expect(sessions.captureCalls, 1);
      expect(sessions.currentChecks, greaterThanOrEqualTo(10));
      expect(store.sessions, isNotEmpty);
      expect(api.sessions, hasLength(3));
      expect(
        <RecordingUploadSession>{...store.sessions, ...api.sessions},
        <RecordingUploadSession>{sessions.session!},
      );
      expect(api.sessions.first.accessToken, 'captured-token');
      expect(api.sessions.first.backendHost, 'api.example.test');
      expect(api.sessions.first.logicalSessionId, 'logical-session');
    });

    test('missing verified session fails closed before lookup', () async {
      final _FakeStore store = _threePartStore();
      final _FakeSessions sessions = _FakeSessions()..session = null;
      final RecordingDownloadService service = _service(
        store: store,
        sessions: sessions,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<FetchException>()),
      );

      expect(sessions.captureCalls, 1);
      expect(store.localLookups, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('session change after lookup fails before API or files', () async {
      final _FakeStore store = _threePartStore();
      final _FakeSessions sessions = _FakeSessions()..flipAtCurrentCheck = 2;
      final _FakeApi api = _FakeApi();
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        sessions: sessions,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(api.calls, 0);
      expect(files.reserved, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('session change after an API response leaves no staged file',
        () async {
      final _FakeStore store = _threePartStore();
      final _FakeSessions sessions = _FakeSessions();
      final _FakeApi api = _FakeApi()
        ..onDownload = (_) {
          sessions.current = false;
        };
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        sessions: sessions,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(api.calls, 1);
      expect(files.reserved, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('session change before commit deletes every staged file', () async {
      final _FakeStore store = _threePartStore();
      final _FakeSessions sessions = _FakeSessions();
      final _FakeFiles files = _FakeFiles()
        ..onConcatenate = () {
          sessions.current = false;
        };
      final RecordingDownloadService service = _service(
        store: store,
        sessions: sessions,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(files.reserved, hasLength(4));
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
      expect(store.commits, isEmpty);
    });
  });

  group('RecordingDownloadService staged failure cleanup', () {
    for (final int failedIndex in <int>[0, 1, 2]) {
      test('cleans staged files when part ${failedIndex + 1} API fails',
          () async {
        final _FakeStore store = _threePartStore();
        final _FakeApi api = _FakeApi()..failAtCall = failedIndex;
        final _FakeFiles files = _FakeFiles();
        final RecordingDownloadService service = _service(
          store: store,
          api: api,
          files: files,
        );

        await expectLater(
          service.downloadByLocalId(10),
          throwsA(isA<FetchException>()),
        );

        expect(api.calls, failedIndex + 1);
        expect(files.reserved, hasLength(failedIndex));
        expect(files.active, isEmpty);
        expect(store.commits, isEmpty);
      });
    }

    test('cancellation between parts cleans completed part staging', () async {
      final _FakeStore store = _threePartStore();
      final CancelToken cancelToken = CancelToken();
      final _FakeApi api = _FakeApi()
        ..onDownload = (int index) {
          if (index == 1) cancelToken.cancel('test cancellation');
        };
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10, cancelToken: cancelToken),
        throwsA(
          isA<DioException>().having(
            (DioException error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );

      expect(api.calls, 2);
      expect(files.reserved, hasLength(1));
      expect(files.active, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('cancellation after concatenation cleans parts and parent', () async {
      final _FakeStore store = _threePartStore();
      final CancelToken cancelToken = CancelToken();
      final _FakeFiles files = _FakeFiles()
        ..onConcatenate = () {
          cancelToken.cancel('cancel after concat');
        };
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10, cancelToken: cancelToken),
        throwsA(isA<DioException>()),
      );

      expect(files.reserved, hasLength(4));
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
      expect(store.commits, isEmpty);
    });

    test('part-file write failure cleans the failed path and earlier paths',
        () async {
      final _FakeStore store = _threePartStore();
      final _FakeFiles files = _FakeFiles()..failWriteAtCall = 1;
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<FileSystemException>()),
      );

      expect(files.reserved, hasLength(2));
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
      expect(store.commits, isEmpty);
    });

    test('concatenation failure cleans all part and parent staging', () async {
      final _FakeStore store = _threePartStore();
      final _FakeFiles files = _FakeFiles()..failConcatenate = true;
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<FormatException>()),
      );

      expect(files.reserved, hasLength(4));
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
      expect(store.commits, isEmpty);
    });

    test('pre-commit DB exception cleans every staged file', () async {
      final _FakeStore store = _threePartStore()
        ..commitError = StateError('transaction rolled back');
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<StateError>()),
      );

      expect(store.commits, hasLength(1));
      expect(store.reconciliationCalls, 1);
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
    });

    test('commit-then-throw reconciles success and retains every staged file',
        () async {
      final _FakeStore store = _threePartStore()..commitThenThrow = true;
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      expect(await service.downloadByLocalId(10), 10);

      expect(store.commits, hasLength(1));
      expect(store.reconciliationCalls, 1);
      expect(files.active.toSet(), files.reserved.toSet());
      expect(files.deleted, isEmpty);
    });

    test('reconciliation failure retains possibly committed staged files',
        () async {
      final _FakeStore store = _threePartStore()
        ..commitError = StateError('commit acknowledgement lost')
        ..reconciliationError = StateError('database unavailable');
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingDownloadCommitStateUnknownException>()),
      );

      expect(store.reconciliationCalls, 1);
      expect(files.active.toSet(), files.reserved.toSet());
      expect(files.deleted, isEmpty);
    });

    test('inconclusive reconciliation retains possibly committed staged files',
        () async {
      final _FakeStore store = _threePartStore()
        ..commitError = StateError('commit acknowledgement lost')
        ..reconciliationState = RecordingDownloadCommitState.unknown;
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingDownloadCommitStateUnknownException>()),
      );

      expect(store.reconciliationCalls, 1);
      expect(files.active.toSet(), files.reserved.toSet());
      expect(files.deleted, isEmpty);
    });

    test(
        'session change during acknowledged commit is surfaced without cleanup',
        () async {
      final _FakeStore store = _threePartStore();
      final _FakeSessions sessions = _FakeSessions();
      store.onCommit = () {
        sessions.current = false;
      };
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        sessions: sessions,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<RecordingUploadSessionChangedException>()),
      );

      expect(store.commits, hasLength(1));
      expect(store.reconciliationCalls, 0);
      expect(files.active.toSet(), files.reserved.toSet());
      expect(files.deleted, isEmpty);
    });

    test('unacknowledged DB commit cleans every staged file', () async {
      final _FakeStore store = _threePartStore()..acknowledgeCommit = false;
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<StateError>()),
      );

      expect(store.commits, hasLength(1));
      expect(files.active, isEmpty);
      expect(files.deleted.toSet(), files.reserved.toSet());
    });

    test('cleanup failure does not replace the original API failure', () async {
      final _FakeStore store = _threePartStore();
      final _FakeApi api = _FakeApi()..failAtCall = 2;
      final _FakeFiles files = _FakeFiles()..failDeletes = true;
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(
          isA<FetchException>().having(
            (FetchException error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      expect(files.deleteAttempts, 2);
      expect(store.commits, isEmpty);
    });
  });

  group('RecordingDownloadService validation and success', () {
    test('part-count mismatch fails before API and staging', () async {
      final _FakeStore store = _threePartStore();
      store.localTargets[10] = _target(
        localId: 10,
        backendId: 900,
        expectedPartCount: 4,
      );
      final _FakeApi api = _FakeApi();
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(
          isA<FetchException>().having(
            (FetchException error) => error.statusCode,
            'statusCode',
            409,
          ),
        ),
      );

      expect(api.calls, 0);
      expect(files.reserved, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('stale downloaded path is ignored and replaced by a full download',
        () async {
      final _FakeStore store = _threePartStore();
      store.localTargets[10] = _target(
        localId: 10,
        backendId: 900,
        expectedPartCount: 3,
        downloaded: true,
        path: 'stale://missing.wav',
      );
      final _FakeApi api = _FakeApi();
      final _FakeFiles files = _FakeFiles();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      expect(await service.downloadByLocalId(10), 10);

      expect(files.readabilityChecks, <String>['stale://missing.wav']);
      expect(api.calls, 3);
      expect(store.commits, hasLength(1));
      expect(store.commits.single.target.path, 'stale://missing.wav');
      expect(files.deleted, isEmpty);
    });

    test('mismatched part parent fails before API and staging', () async {
      final _FakeStore store = _threePartStore();
      store.partsByLocalId[10]![1] = _part(
        localId: 102,
        backendId: 902,
        parentLocalId: 999,
        parentBeId: 900,
      );
      final _FakeApi api = _FakeApi();
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
      );

      await expectLater(
        service.downloadByLocalId(10),
        throwsA(isA<FetchException>()),
      );

      expect(api.calls, 0);
      expect(store.commits, isEmpty);
    });

    test('already downloaded target returns without API, files, or commit',
        () async {
      final _FakeStore store = _threePartStore();
      store.localTargets[10] = _target(
        localId: 10,
        backendId: 900,
        expectedPartCount: 3,
        downloaded: true,
        path: 'owned://recording.wav',
      );
      final _FakeApi api = _FakeApi();
      final _FakeFiles files = _FakeFiles()
        ..readablePaths.add('owned://recording.wav');
      final List<double> progress = <double>[];
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      expect(
        await service.downloadByLocalId(10, onProgress: progress.add),
        10,
      );

      expect(progress, <double>[1]);
      expect(api.calls, 0);
      expect(files.reserved, isEmpty);
      expect(store.commits, isEmpty);
    });

    test('success commits every path once and retains all staged files',
        () async {
      final _FakeStore store = _threePartStore();
      final _FakeFiles files = _FakeFiles();
      final List<double> progress = <double>[];
      final RecordingDownloadService service = _service(
        store: store,
        files: files,
      );

      expect(
        await service.downloadByLocalId(10, onProgress: progress.add),
        10,
      );

      expect(store.commits, hasLength(1));
      final RecordingDownloadCommit commit = store.commits.single;
      expect(commit.target.localId, 10);
      expect(commit.target.backendId, 900);
      expect(commit.parts, hasLength(3));
      expect(
        commit.parts.map((RecordingDownloadedPart part) => part.localId),
        <int>[101, 102, 103],
      );
      expect(
        commit.parts.map((RecordingDownloadedPart part) => part.backendId),
        <int>[901, 902, 903],
      );
      expect(commit.recordingPath, files.reserved.last);
      expect(files.active.toSet(), files.reserved.toSet());
      expect(files.deleted, isEmpty);
      expect(progress.first, 0);
      expect(progress.last, 1);
      expect(
        progress.every((double value) => value >= 0 && value <= 1),
        isTrue,
      );
    });

    test('progress callback exceptions cannot abort a successful commit',
        () async {
      final _FakeStore store = _threePartStore();
      final _FakeApi api = _FakeApi()..emitProgress = true;
      final _FakeFiles files = _FakeFiles();
      int callbacks = 0;
      final RecordingDownloadService service = _service(
        store: store,
        api: api,
        files: files,
      );

      final int localId = await service.downloadByLocalId(
        10,
        onProgress: (_) {
          callbacks++;
          throw StateError('broken UI callback');
        },
      );

      expect(localId, 10);
      expect(callbacks, greaterThan(3));
      expect(store.commits, hasLength(1));
      expect(files.deleted, isEmpty);
    });
  });
}

RecordingDownloadService _service({
  required _FakeStore store,
  _FakeApi? api,
  _FakeSessions? sessions,
  _FakeFiles? files,
}) {
  return RecordingDownloadService(
    store: store,
    api: api ?? _FakeApi(),
    sessions: sessions ?? _FakeSessions(),
    files: files ?? _FakeFiles(),
  );
}

_FakeStore _threePartStore() {
  return _FakeStore()
    ..localTargets[10] =
        _target(localId: 10, backendId: 900, expectedPartCount: 3)
    ..backendTargets[900] =
        _target(localId: 10, backendId: 900, expectedPartCount: 3)
    ..partsByLocalId[10] = <RecordingDownloadPart>[
      _part(
        localId: 101,
        backendId: 901,
        parentLocalId: 10,
        parentBeId: 900,
      ),
      _part(
        localId: 102,
        backendId: 902,
        parentLocalId: 10,
        parentBeId: 900,
      ),
      _part(
        localId: 103,
        backendId: 903,
        parentLocalId: 10,
        parentBeId: 900,
      ),
    ];
}

RecordingDownloadTarget _target({
  required int localId,
  required int backendId,
  int? expectedPartCount = 1,
  bool downloaded = false,
  String? path,
}) {
  return RecordingDownloadTarget(
    localId: localId,
    backendId: backendId,
    environment: 'prod',
    ownerUserId: 42,
    ownerEmail: 'owner@example.test',
    expectedPartCount: expectedPartCount,
    downloaded: downloaded,
    path: path,
  );
}

RecordingDownloadPart _part({
  required int localId,
  required int backendId,
  required int parentLocalId,
  required int parentBeId,
}) {
  return RecordingDownloadPart(
    localId: localId,
    backendId: backendId,
    localRecordingId: parentLocalId,
    backendRecordingId: parentBeId,
    previousPath: null,
    previousByteLength: null,
  );
}

RecordingUploadSession _session() {
  return const RecordingUploadSession(
    userId: '42',
    accessToken: 'captured-token',
    logicalSessionId: 'logical-session',
    environment: 'prod',
    backendHost: 'api.example.test',
    accountEmail: 'owner@example.test',
  );
}

class _FakeSessions implements RecordingUploadSessionProvider {
  RecordingUploadSession? session = _session();
  bool current = true;
  int? flipAtCurrentCheck;
  int captureCalls = 0;
  int currentChecks = 0;

  @override
  Future<RecordingUploadSession?> capture() async {
    captureCalls++;
    return session;
  }

  @override
  Future<bool> isCurrent(RecordingUploadSession captured) async {
    currentChecks++;
    if (flipAtCurrentCheck != null && currentChecks >= flipAtCurrentCheck!) {
      current = false;
    }
    return current && identical(captured, session);
  }
}

class _FakeStore implements RecordingDownloadStore {
  final Map<int, RecordingDownloadTarget> localTargets =
      <int, RecordingDownloadTarget>{};
  final Map<int, RecordingDownloadTarget> backendTargets =
      <int, RecordingDownloadTarget>{};
  final Map<int, List<RecordingDownloadPart>> partsByLocalId =
      <int, List<RecordingDownloadPart>>{};
  final List<int> localLookups = <int>[];
  final List<int> backendLookups = <int>[];
  final List<RecordingUploadSession> sessions = <RecordingUploadSession>[];
  final List<RecordingDownloadCommit> commits = <RecordingDownloadCommit>[];
  bool acknowledgeCommit = true;
  Object? commitError;
  bool commitThenThrow = false;
  RecordingDownloadCommitState reconciliationState =
      RecordingDownloadCommitState.absent;
  Object? reconciliationError;
  void Function()? onCommit;
  int reconciliationCalls = 0;

  @override
  Future<RecordingDownloadTarget?> findByLocalId(
    int localId,
    RecordingUploadSession session,
  ) async {
    localLookups.add(localId);
    sessions.add(session);
    return localTargets[localId];
  }

  @override
  Future<RecordingDownloadTarget?> findByBackendId(
    int backendId,
    RecordingUploadSession session,
  ) async {
    backendLookups.add(backendId);
    sessions.add(session);
    return backendTargets[backendId];
  }

  @override
  Future<List<RecordingDownloadPart>> loadParts(
    RecordingDownloadTarget target,
    RecordingUploadSession session,
  ) async {
    sessions.add(session);
    return List<RecordingDownloadPart>.from(
      partsByLocalId[target.localId] ?? const <RecordingDownloadPart>[],
    );
  }

  @override
  Future<bool> commitDownload(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  ) async {
    sessions.add(session);
    commits.add(commit);
    onCommit?.call();
    if (commitThenThrow) {
      reconciliationState = RecordingDownloadCommitState.committed;
      throw StateError('mocked lost commit acknowledgement');
    }
    if (commitError case final Object error) throw error;
    return acknowledgeCommit;
  }

  @override
  Future<RecordingDownloadCommitState> reconcileDownloadCommit(
    RecordingDownloadCommit commit,
    RecordingUploadSession session,
  ) async {
    sessions.add(session);
    reconciliationCalls++;
    if (reconciliationError case final Object error) throw error;
    return reconciliationState;
  }
}

class _FakeApi implements RecordingDownloadApi {
  int calls = 0;
  int? failAtCall;
  bool emitProgress = false;
  void Function(int index)? onDownload;
  final List<int> backendRecordingIds = <int>[];
  final List<int> backendPartIds = <int>[];
  final List<RecordingUploadSession> sessions = <RecordingUploadSession>[];

  @override
  Future<List<int>> downloadPart({
    required int backendRecordingId,
    required int backendPartId,
    required RecordingUploadSession session,
    CancelToken? cancelToken,
    RecordingPartDownloadProgress? onProgress,
  }) async {
    final int index = calls++;
    backendRecordingIds.add(backendRecordingId);
    backendPartIds.add(backendPartId);
    sessions.add(session);
    onDownload?.call(index);
    if (failAtCall == index) {
      throw FetchException('mocked part failure', 503);
    }
    if (emitProgress) {
      onProgress?.call(1, 4);
      onProgress?.call(4, 4);
    }
    return <int>[index, backendPartId & 0xff];
  }
}

class _FakeFiles implements RecordingDownloadFiles {
  final List<String> reserved = <String>[];
  final Set<String> active = <String>{};
  final List<String> deleted = <String>[];
  int writeCalls = 0;
  int? failWriteAtCall;
  bool failConcatenate = false;
  bool failDeletes = false;
  int deleteAttempts = 0;
  void Function()? onConcatenate;
  final Set<String> readablePaths = <String>{};
  final List<String> readabilityChecks = <String>[];

  @override
  Future<bool> isReadable(String path) async {
    readabilityChecks.add(path);
    return readablePaths.contains(path);
  }

  @override
  Future<String> reservePath({
    required int localRecordingId,
    required int backendRecordingId,
    int? backendPartId,
  }) async {
    final String path = backendPartId == null
        ? 'stage://recording-${reserved.length}.wav'
        : 'stage://part-$backendPartId-${reserved.length}.wav';
    reserved.add(path);
    active.add(path);
    return path;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final int index = writeCalls++;
    if (!active.contains(path)) {
      throw StateError('Writing an unreserved path.');
    }
    if (failWriteAtCall == index) {
      throw FileSystemException('mocked write failure', path);
    }
  }

  @override
  Future<void> concatenate(
    List<String> partPaths,
    String outputPath,
  ) async {
    onConcatenate?.call();
    if (failConcatenate) {
      throw const FormatException('mocked concat failure');
    }
    if (!active.contains(outputPath) ||
        partPaths.any((String path) => !active.contains(path))) {
      throw StateError('Concatenation received an unstaged path.');
    }
  }

  @override
  Future<void> deleteIfExists(String path) async {
    deleteAttempts++;
    active.remove(path);
    deleted.add(path);
    if (failDeletes) {
      throw FileSystemException('mocked cleanup failure', path);
    }
  }
}
