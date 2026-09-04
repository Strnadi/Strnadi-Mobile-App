import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

List<String> _sqlColumns(String source) {
  return source
      .split(',')
      .map((column) => column.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((column) => column.isNotEmpty)
      .map((column) => column.split(' ').first)
      .toList(growable: false);
}

void main() {
  late String migrations;
  late String repository;
  late String repositoryApi;
  late String uploadScheduling;
  late String recordingsController;
  late String recordingPartsController;
  late String recordingForm;
  late String incompleteUploadPrompt;
  late String uploadIntegrationHelpers;
  late String callback;
  late String backgroundTask;

  setUpAll(() {
    migrations = _read('lib/database/src/database_migrations.dart');
    repository = _read('lib/database/src/database_repository.dart');
    repositoryApi = _read('lib/database/src/database_repository_api.dart');
    uploadScheduling = _read('lib/database/recording_upload_scheduling.dart');
    recordingsController =
        _read('lib/api/controllers/recordings_controller.dart');
    recordingPartsController =
        _read('lib/api/controllers/recording_parts_controller.dart');
    recordingForm = _read('lib/PostRecordingForm/RecordingForm.dart');
    incompleteUploadPrompt =
        _read('lib/localRecordings/incomplete_upload_prompt.dart');
    uploadIntegrationHelpers =
        _read('lib/localRecordings/upload_integration_helpers.dart');
    callback = _read('lib/callback_dispatcher.dart');
    backgroundTask =
        _read('lib/database/background_recording_upload_task.dart');
  });

  group('v15 static migration contract (no SQLite)', () {
    for (final (newTable, oldTable) in <(String, String)>[
      ('recordings_v15', 'recordings'),
      ('recordingParts_v15', 'recordingParts'),
      ('Dialects_v15', 'Dialects'),
      ('FilteredRecordingParts_v15', 'FilteredRecordingParts'),
      ('DetectedDialects_v15', 'DetectedDialects'),
    ]) {
      test('$newTable INSERT and SELECT columns stay aligned', () {
        final RegExpMatch? match = RegExp(
          'INSERT INTO $newTable\\s*\\((.*?)\\)\\s*'
          'SELECT\\s*(.*?)\\s*FROM $oldTable',
          dotAll: true,
        ).firstMatch(migrations);

        expect(match, isNotNull,
            reason: 'Migration copy statement is missing.');
        expect(_sqlColumns(match!.group(1)!), _sqlColumns(match.group(2)!));
      });
    }

    test('request-freeze columns exist before the table rebuild', () {
      final int upgrade = repository.indexOf('if (oldVersion <= 14)');
      final int partMarker = repository.indexOf(
          "'recordingParts',\n          'uploadAttempted'", upgrade);
      final int dialectMarker = repository.indexOf(
          "'Dialects',\n          'uploadAttempted'", upgrade);
      final int rebuild = repository.indexOf(
          '_rebuildUploadTablesForScopedBackendIds(db)', upgrade);

      expect(upgrade, greaterThanOrEqualTo(0));
      expect(partMarker, greaterThan(upgrade));
      expect(dialectMarker, greaterThan(upgrade));
      expect(rebuild, greaterThan(partMarker));
      expect(rebuild, greaterThan(dialectMarker));
    });

    test('existing remote children are frozen before v15 key reuse', () {
      final int upgrade = repository.indexOf('if (oldVersion <= 14)');
      final int rebuild = repository.indexOf(
          '_rebuildUploadTablesForScopedBackendIds(db)', upgrade);
      final int partBackfill = repository.indexOf(
        'UPDATE recordingParts SET uploadAttempted = 1',
        upgrade,
      );
      final int dialectBackfill = repository.indexOf(
        'UPDATE Dialects SET uploadAttempted = 1',
        upgrade,
      );

      expect(partBackfill, greaterThan(upgrade));
      expect(dialectBackfill, greaterThan(upgrade));
      expect(partBackfill, lessThan(rebuild));
      expect(dialectBackfill, lessThan(rebuild));
    });

    test('legacy remote children regain backend parent links before rebuild',
        () {
      final int rebuild =
          migrations.indexOf('Future<void> _rebuildUploadTablesForScoped');
      final int createTables =
          migrations.indexOf('CREATE TABLE recordings_v15', rebuild);
      final String repair = migrations.substring(rebuild, createTables);

      final int partReverse =
          repair.indexOf('UPDATE recordingParts SET backendRecordingId');
      final int dialectReverse =
          repair.indexOf('UPDATE Dialects SET recordingBEID');
      final int partForward =
          repair.indexOf('UPDATE recordingParts SET recordingId');
      final int dialectForward =
          repair.indexOf('UPDATE Dialects SET recordingId');

      expect(partReverse, greaterThanOrEqualTo(0));
      expect(dialectReverse, greaterThan(partReverse));
      expect(partForward, greaterThan(dialectReverse));
      expect(dialectForward, greaterThan(partForward));
      expect(
        repair,
        contains('r.id = recordingParts.recordingId AND r.BEId IS NOT NULL'),
      );
      expect(
        repair,
        contains('r.id = Dialects.recordingId AND r.BEId IS NOT NULL'),
      );
      expect(
        repair,
        contains('backendRecordingId IS NULL AND recordingId IS NOT NULL'),
      );
      expect(repair, contains("'AND BEId IS NOT NULL AND EXISTS ('"));
      expect(
        repair,
        contains('recordingBEID IS NULL AND recordingId IS NOT NULL'),
      );
      expect(repair, contains("'AND BEID IS NOT NULL AND EXISTS ('"));
    });

    test('backend ids are unique only within their owning aggregate', () {
      expect(migrations, isNot(contains('BEId INTEGER UNIQUE')));
      expect(migrations, isNot(contains('BEID INTEGER UNIQUE')));
      expect(repository, isNot(contains('BEId INTEGER UNIQUE')));
      expect(repository, isNot(contains('BEID INTEGER UNIQUE')));

      for (final index in <String>[
        'ON recordings(env, BEId)',
        'ON recordingParts(recordingId, BEId)',
        'ON Dialects(recordingId, BEID)',
        'ON FilteredRecordingParts(recordingLocalId, BEId)',
        'ON DetectedDialects(filteredPartLocalId, BEId)',
      ]) {
        expect(migrations, contains(index));
      }
    });
  });

  group('v16 capture-review migration contract (no SQLite)', () {
    test('new and upgraded databases default existing rows to reviewed', () {
      expect(repository, contains("openDatabase('soundNew.db', version: 17"));
      expect(
        RegExp('captureReviewed INTEGER NOT NULL DEFAULT 1')
            .allMatches('$repository\n$migrations')
            .length,
        greaterThanOrEqualTo(2),
      );
      final int upgrade = repository.indexOf('if (oldVersion <= 15)');
      final int end = repository.indexOf('});', upgrade);
      final String v16Upgrade = repository.substring(upgrade, end);
      expect(upgrade, greaterThanOrEqualTo(0));
      expect(v16Upgrade, contains("'captureReviewed'"));
      expect(v16Upgrade, contains('INTEGER NOT NULL DEFAULT 1'));
      expect(
        v16Upgrade,
        contains('UPDATE recordings SET captureReviewed = 1'),
      );
    });
  });

  group('repository concurrency and ownership contracts', () {
    test('only stale deletion leases are eligible for deletion takeover', () {
      final int claimStart =
          repository.indexOf('static Future<_RecordingDeletionClaim>');
      final int cleanupStart = repository
          .indexOf('static Future<void> _deleteClaimedRecordingLocally');
      final String claim = repository.substring(claimStart, cleanupStart);

      expect(claim, contains('uploadLease LIKE ?'));
      expect(claim, contains("'delete:%'"));
      expect(claim, contains('uploadLeaseUpdatedAt < ?'));
      expect(claim, isNot(contains('uploadLease NOT LIKE ?')));
    });

    test('a deletion claim is verified before any dependent row is removed',
        () {
      final int cleanupStart = repository
          .indexOf('static Future<void> _deleteClaimedRecordingLocally');
      final int releaseStart =
          repository.indexOf('static Future<void> _releaseDeletionClaim');
      final String cleanup = repository.substring(cleanupStart, releaseStart);

      final int ownershipCheck =
          cleanup.indexOf('WHERE id = ? AND uploadLease = ?');
      final int firstChildDelete =
          cleanup.indexOf('DELETE FROM DetectedDialects');
      expect(ownershipCheck, greaterThanOrEqualTo(0));
      expect(firstChildDelete, greaterThan(ownershipCheck));
    });

    test('guest listing and account adoption remain environment scoped', () {
      expect(repository, contains('env = ? AND userId IS NULL'));
      expect(
        repository,
        contains('UPDATE recordings SET mail = ?, userId = ?'),
      );
      expect(
        repository,
        contains('WHERE env = ? AND userId IS NULL'),
      );
    });

    test('filtered backend identities are keyed by recording and part id', () {
      expect(
        repository,
        contains('Map<(int, int), int> frpBeToLocal'),
      );
      expect(
        repository,
        contains('frpBeToLocal[(recordingLocalId, frp.BEId!)]'),
      );
      expect(
        repository,
        contains('frpBeToLocal[(recordingLocalId, filteredPartBackendId)]'),
      );
    });

    test('request fields stay frozen while durable remote cache paths can move',
        () {
      expect(
        repository,
        isNot(contains(
          'COALESCE(uploadAttempted, 0) = 0 OR BEId IS NOT NULL',
        )),
      );
      expect(
        repository,
        isNot(contains(
          'COALESCE(uploadAttempted, 0) = 0 OR BEID IS NOT NULL',
        )),
      );
      expect(
        repository,
        contains(
          'BEId IS NOT NULL AND COALESCE(sent, 0) = 1',
        ),
      );
      expect(
        repository,
        contains('recordingPartCacheUpdateFields(recordingPart)'),
      );
    });

    test('dialect rows are loaded only after the workflow lease is held', () {
      final int operation = callback
          .indexOf('operation: (RecordingWorkflowLeaseContext context)');
      final int load =
          callback.indexOf('DatabaseNew.getDialectsByRecordingId(recordingId)');
      expect(operation, greaterThanOrEqualTo(0));
      expect(load, greaterThan(operation));
    });

    test(
        'dialect request is validated, durably marked, and session-renewed '
        'before every POST', () {
      final int validation =
          callback.indexOf('validateDialectUploadRequest(body)');
      final int attempt =
          callback.indexOf('runDialectUploadAttempt<Response<dynamic>>');
      final int freeze = callback.indexOf(
        'DatabaseNew.markDialectAttemptedWithWorkflowLease',
        validation,
      );
      final int renew = callback.indexOf('renew: context.renew', freeze);
      final int post = callback.indexOf('return _postDialect', renew);
      final int beforePost = callback.indexOf('beforePost: beforePost', post);

      expect(validation, greaterThanOrEqualTo(0));
      expect(attempt, greaterThan(validation));
      expect(freeze, greaterThan(validation));
      expect(renew, greaterThan(freeze));
      expect(post, greaterThan(freeze));
      expect(beforePost, greaterThan(post));
    });

    test('health endpoint registration cannot veto the durable upload lease',
        () {
      final int registration =
          backgroundTask.indexOf('healthStarted = await startHealth');
      final int upload =
          backgroundTask.indexOf('await uploadRecording(recording)');
      final String gate = backgroundTask.substring(registration, upload);

      expect(registration, greaterThanOrEqualTo(0));
      expect(upload, greaterThan(registration));
      expect(gate, contains('catch (error, stackTrace)'));
      expect(gate, contains("'health registration'"));
      expect(
        callback,
        contains('_backgroundUploadHealthServer.start(recordingId)'),
      );
    });

    test('notification failure cannot replace the upload task result', () {
      final int notifyStart = callback
          .indexOf('Future<void> _notify(String title, String message)');
      final int handlerStart = callback.indexOf(
        'Future<bool> _handleSendRecordingTask',
        notifyStart,
      );
      final String notify = callback.substring(notifyStart, handlerStart);

      expect(notifyStart, greaterThanOrEqualTo(0));
      expect(handlerStart, greaterThan(notifyStart));
      expect(notify, contains('try {'));
      expect(notify, contains('catch (error, stackTrace)'));
      expect(notify, contains('must not turn a completed'));
    });

    test('orphan part retry never bypasses aggregate upload validation', () {
      final int retryStart =
          repository.indexOf('static Future<void> _resendUnsentPartRows');
      final int dialectStart = repository.indexOf('// Dialects', retryStart);
      final String retry = repository.substring(retryStart, dialectStart);

      expect(retry, contains('quarantining orphan part'));
      expect(retry, contains('missing local recording'));
      expect(retry, contains('sendRecordingNew(recording'));
      expect(retry, contains('rawRecordingId.isFinite'));
      expect(
        retry,
        contains('rawRecordingId == rawRecordingId.truncateToDouble()'),
      );
      expect(retry, isNot(contains('sendRecordingPartNew(')));
      expect(retry, isNot(contains('sendRecordingPart(')));
    });

    test('legacy upload entry points delegate to the aggregate service', () {
      final int oldRecording =
          repositoryApi.indexOf('Future<void> _sendRecording(');
      final int aggregateRecording =
          repositoryApi.indexOf('Future<void> _sendRecordingNew(');
      final String recordingCompatibility =
          repositoryApi.substring(oldRecording, aggregateRecording);
      expect(recordingCompatibility, contains('_sendRecordingNew('));
      expect(
        recordingCompatibility,
        isNot(contains('_recordingsApi.createRecording')),
      );

      final int oldPart =
          repositoryApi.indexOf('Future<void> _sendRecordingPart(');
      final int updateRecording =
          repositoryApi.indexOf('Future<void> _updateRecordingBE(');
      final String partCompatibility =
          repositoryApi.substring(oldPart, updateRecording);
      expect(partCompatibility, contains('_sendRecordingNew(recording'));
      expect(partCompatibility, contains('getRecordingFromDbById'));
      expect(
        partCompatibility,
        isNot(contains('uploadRecordingPartJson')),
      );
      expect(
        partCompatibility,
        isNot(contains('uploadRecordingPartMultipart')),
      );
    });

    test('upload release clears only CAS-owned transient lease state', () {
      final int release =
          repositoryApi.indexOf('Future<void> releaseRecording(');
      final int backendApi =
          repositoryApi.indexOf('class _BackendRecordingUploadApi', release);
      final String releaseBody = repositoryApi.substring(release, backendApi);

      expect(release, greaterThanOrEqualTo(0));
      expect(backendApi, greaterThan(release));
      expect(
        releaseBody,
        contains(
          'SET sending = 0, uploadLease = NULL, uploadLeaseUpdatedAt = NULL',
        ),
      );
      expect(releaseBody, contains('WHERE id = ? AND uploadLease = ?'));
      expect(
        releaseBody,
        contains(
          'UPDATE recordingParts SET sending = 0 WHERE recordingId = ?',
        ),
      );
      expect(releaseBody, isNot(contains('recording.toJson()')));
      expect(releaseBody, isNot(contains('Recording? recording')));
    });

    test('upload lease acquisition clears orphaned child sending flags', () {
      final int acquire =
          repositoryApi.indexOf('Future<bool> tryAcquireRecording(');
      final int renew =
          repositoryApi.indexOf('Future<void> renewRecording(', acquire);
      final String acquireBody = repositoryApi.substring(acquire, renew);

      final int parentClaim = acquireBody.indexOf('UPDATE recordings');
      final int claimCheck = acquireBody.indexOf('if (changed != 1)');
      final int childReset = acquireBody.indexOf(
        'UPDATE recordingParts SET sending = 0 WHERE recordingId = ?',
      );
      expect(parentClaim, greaterThanOrEqualTo(0));
      expect(claimCheck, greaterThan(parentClaim));
      expect(childReset, greaterThan(claimCheck));
      expect(acquireBody, contains('db.transaction<bool>'));
      expect(
        acquireBody,
        isNot(contains('captureReviewed = 1')),
      );
      expect(acquireBody, isNot(contains('COALESCE(captureReviewed, 1)')));
      expect(
        File('lib/database/recording_upload_service.dart').readAsStringSync(),
        contains('if (!recording.captureReviewed)'),
      );
    });

    test('unreviewed captures cannot be scheduled or backend-discovered', () {
      final int schedule =
          repository.indexOf('static Future<void> sendRecordingBackground');
      final int sendCompatibility =
          repository.indexOf('static Future<void> sendRecording(', schedule);
      final String scheduling =
          repository.substring(schedule, sendCompatibility);
      final int ownerQuery =
          repository.indexOf('_getRecordingsForOwnerSnapshot(');
      final int incompleteDiscovery =
          repository.indexOf('findIncompleteUploads({', ownerQuery);
      final String discoveryScope =
          repository.substring(ownerQuery, incompleteDiscovery);

      expect(scheduling, contains("'captureReviewed'"));
      expect(scheduling, contains('scheduleReviewedRecordingUpload('));
      expect(
        uploadScheduling,
        contains('must be reviewed before scheduling upload'),
      );
      expect(
        discoveryScope,
        contains('captureReviewed = 1'),
      );
      expect(discoveryScope, isNot(contains('COALESCE(captureReviewed, 1)')));
    });

    test('draft insertion pins one explicit owner and environment snapshot',
        () {
      final int insert =
          repository.indexOf('static Future<int> insertRecordingDraft');
      final int reconcile = repository.indexOf(
        'static Future<PersistedDraftIdentity?>',
        insert,
      );
      final String draftInsert = repository.substring(insert, reconcile);

      expect(draftInsert, contains('_captureRecordingOwnerSnapshot()'));
      expect(draftInsert, contains('..env = ownerSnapshot.environment'));
      expect(
        draftInsert,
        contains("..mail = ownerSnapshot.isGuest ? ''"),
      );
      expect(draftInsert, contains('..userId ='));
      expect(draftInsert, contains('ownerSnapshot.isGuest ? null'));
      expect(
        RegExp('_requireRecordingOwnerSnapshotCurrent\\(ownerSnapshot\\)')
            .allMatches(draftInsert)
            .length,
        greaterThanOrEqualTo(2),
      );
      final int beforeTransaction =
          draftInsert.indexOf('_requireRecordingOwnerSnapshotCurrent');
      final int transaction = draftInsert.indexOf('db.transaction<int>');
      final int afterTransaction = draftInsert.lastIndexOf(
        '_requireRecordingOwnerSnapshotCurrent',
      );
      expect(beforeTransaction, lessThan(transaction));
      expect(afterTransaction, greaterThan(transaction));
      expect(draftInsert, isNot(contains('enforceMaxRecordings')));
      expect(draftInsert, isNot(contains("storage.read(key: 'token')")));
    });

    test('ambiguous draft persistence keeps source media fail closed', () {
      final int insert =
          repository.indexOf('static Future<int> insertRecordingDraft');
      final int reconcile = repository.indexOf(
        'static Future<PersistedDraftIdentity?>',
        insert,
      );
      final String draftInsert = repository.substring(insert, reconcile);

      expect(
        draftInsert,
        contains('RecordingDraftCommitState.definitelyAbsent'),
      );
      expect(
        draftInsert,
        contains('RecordingDraftCommitState.mayHaveCommitted'),
      );
      expect(draftInsert, contains('ownerSnapshot,'));
      final String reconciliation = repository.substring(reconcile);
      expect(
        reconciliation,
        contains("'mail',\n        'userId',\n        'env'"),
      );
      expect(
        reconciliation,
        contains('ownerSnapshot: ownerSnapshot'),
      );
      expect(
        recordingForm,
        contains('bool _draftPersistenceMayHaveCommitted = false'),
      );
      expect(
        recordingForm,
        contains('error is RecordingDraftPersistenceException'),
      );
      expect(
        recordingForm,
        contains('_draftPersistenceMayHaveCommitted = true'),
      );
      expect(
        recordingForm,
        contains('canDeleteUnpersistedDraftFiles('),
      );
      expect(
        recordingForm,
        contains(
          'persistenceMayHaveCommitted: '
          '_draftPersistenceMayHaveCommitted',
        ),
      );
    });

    test('saved draft updates pin owner, environment, and durable identity',
        () {
      final int update =
          repository.indexOf('static Future<void> updateRecordingDraft');
      final int fetchFinished =
          repository.indexOf('static Future<void> onFetchFinished', update);
      final String draftUpdate = repository.substring(update, fetchFinished);

      expect(draftUpdate, contains('_captureRecordingOwnerSnapshot()'));
      expect(
        RegExp('recordingOwnerBindingMatchesSnapshot\\(')
            .allMatches(draftUpdate)
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(
        RegExp('_requireRecordingOwnerSnapshotCurrent\\(ownerSnapshot\\)')
            .allMatches(draftUpdate)
            .length,
        greaterThanOrEqualTo(6),
      );
      final int firstSessionCheck =
          draftUpdate.indexOf('_requireRecordingOwnerSnapshotCurrent');
      final int openDatabase = draftUpdate.indexOf('final Database db');
      final int transaction = draftUpdate.indexOf('db.transaction<void>');
      final int metadataMutation = draftUpdate.indexOf('await txn.update');
      final int finalSessionCheck =
          draftUpdate.lastIndexOf('_requireRecordingOwnerSnapshotCurrent');
      expect(firstSessionCheck, lessThan(openDatabase));
      expect(transaction, greaterThan(openDatabase));
      expect(metadataMutation, greaterThan(transaction));
      expect(finalSessionCheck, greaterThan(metadataMutation));

      expect(draftUpdate, contains('where: \'id = ? AND uploadKey = ?\''));
      expect(
        draftUpdate,
        contains('id = ? AND uploadKey = ? AND \$ownerPredicate'),
      );
      expect(draftUpdate, contains('env = ? AND userId IS NULL'));
      expect(draftUpdate, contains('env = ? AND userId = ?'));
      expect(draftUpdate, contains('LOWER(TRIM(mail)) = LOWER(?)'));
      expect(draftUpdate, contains('recordingMetadataUpdateFields(recording)'));
      expect(draftUpdate, contains("..['captureReviewed'] = 1"));
      expect(draftUpdate, contains('recording.captureReviewed = true'));
      expect(
        draftUpdate,
        contains('COALESCE(parentUploadAttempted, 0) = 0'),
      );
      expect(draftUpdate, contains('uploadLease IS NULL'));
      expect(
        draftUpdate,
        contains('BEID IS NOT NULL OR COALESCE(uploadAttempted, 0) = 1'),
      );
      expect(
        draftUpdate,
        contains('BEId IS NOT NULL OR backendRecordingId IS NOT NULL'),
      );
      expect(draftUpdate, contains('OR COALESCE(sent, 0) = 1'));
      expect(
        draftUpdate,
        contains('AND COALESCE(uploadAttempted, 0) = 0 AND EXISTS ('),
      );
    });

    test('incomplete-upload discovery uses one pinned local/backend session',
        () {
      final int find = repository.indexOf('findIncompleteUploads({');
      final int resend =
          repository.indexOf('resendMissingPartsForRecording', find);
      final String discovery = repository.substring(find, resend);
      final int fetch =
          repository.indexOf('_fetchIncompleteRecordingsFromBE(', resend);
      final int nextMethod = repository.indexOf(
        '/// Checks whether *all* parts',
        fetch,
      );
      final String backendCheck = repository.substring(fetch, nextMethod);

      expect(discovery, contains('_captureRecordingOwnerSnapshot()'));
      expect(
        discovery,
        contains('_getRecordingsForOwnerSnapshot('),
      );
      expect(
        discovery,
        contains('_fetchIncompleteRecordingsFromBE(ownerSnapshot)'),
      );
      expect(
        RegExp('_requireRecordingOwnerSnapshotCurrent\\(ownerSnapshot\\)')
            .allMatches(discovery)
            .length,
        greaterThanOrEqualTo(4),
      );
      expect(
        backendCheck,
        contains('accessToken: ownerSnapshot.accessToken'),
      );
      expect(backendCheck, contains('host: ownerSnapshot.backendHost'));
      expect(
        backendCheck,
        contains('response.statusCode != 200 && response.statusCode != 204'),
      );
      expect(
        backendCheck,
        contains('backendIncompleteUploadSnapshotFromResponse('),
      );
      expect(
        backendCheck,
        contains('on RecordingUploadSessionChangedException'),
      );

      final int controllerFetch = recordingsController
          .indexOf('Future<Response<dynamic>> fetchIncompleteRecordings');
      final int controllerById = recordingsController.indexOf(
        'Future<Response<dynamic>> fetchRecordingById',
        controllerFetch,
      );
      final String request =
          recordingsController.substring(controllerFetch, controllerById);
      expect(request, contains('host: host'));
      expect(request, contains("'Authorization': 'Bearer \$accessToken'"));
      expect(request, contains('followRedirects: false'));
      expect(request, contains('maxRedirects: 0'));
    });

    test('delayed incomplete retry revalidates discovery identity before DB',
        () {
      final int retry = repository.indexOf(
        'static Future<void> _resendMissingPartsForRecording',
      );
      final int count =
          repository.indexOf('static int _countResendableMissingParts', retry);
      final String retryBody = repository.substring(retry, count);

      final int firstSessionCheck =
          retryBody.indexOf('_requireRecordingOwnerSnapshotCurrent');
      final int openDatabase = retryBody.indexOf('final Database db');
      final int mutation = retryBody.indexOf('await txn.update');
      final int lastSessionCheck =
          retryBody.lastIndexOf('_requireRecordingOwnerSnapshotCurrent');
      expect(firstSessionCheck, greaterThanOrEqualTo(0));
      expect(firstSessionCheck, lessThan(openDatabase));
      expect(mutation, greaterThan(openDatabase));
      expect(lastSessionCheck, greaterThan(mutation));
      expect(retryBody, contains('r.uploadKey = ?'));
      expect(retryBody, contains('r.env = ?'));
      expect(retryBody, contains('r.mail = ?'));
      expect(retryBody, contains('(r.userId IS NULL OR r.userId = ?)'));
      expect(retryBody, contains('r.BEId = ?'));
      expect(retryBody, contains('r.id = recordingParts.recordingId'));
      expect(retryBody, isNot(contains("'BEId': null")));
      expect(
        incompleteUploadPrompt,
        contains('return issue.resendMissingParts()'),
      );
    });

    test('sensitive recording calls expose expected 4xx statuses to callers',
        () {
      String methodBody(String name, String nextName) {
        final int start = recordingsController.indexOf(
          'Future<Response<dynamic>> $name',
        );
        final int end = recordingsController.indexOf(
          'Future<Response<dynamic>> $nextName',
          start,
        );
        expect(start, greaterThanOrEqualTo(0));
        expect(end, greaterThan(start));
        return recordingsController.substring(start, end);
      }

      final String update = methodBody('updateRecording', 'deleteRecording');
      final String delete =
          methodBody('deleteRecording', 'fetchRecordingsForUser');
      final String fetchById =
          methodBody('fetchRecordingById', 'fetchRecordingPartSummary');
      for (final String request in <String>[update, delete, fetchById]) {
        expect(
          request,
          contains(
            'validateStatus: (int? status) => '
            'status != null && status < 500',
          ),
        );
        expect(request, contains('followRedirects: false'));
        expect(request, contains('maxRedirects: 0'));
      }
    });

    test('upload reconciliation never clears deletion leases', () {
      final int reconciliation =
          repository.indexOf('static Future<void> checkSendingRecordings');
      final int clearer =
          repository.indexOf('static Future<bool> _clearObservedUploadLease');
      final String scan = repository.substring(reconciliation, clearer);
      final String clear = repository.substring(clearer);

      expect(scan, contains('_isDeletionLease(recording.uploadLease)'));
      expect(
        scan.indexOf('_isDeletionLease(recording.uploadLease)'),
        lessThan(scan.indexOf("final String portName = '/upload/rec/")),
      );
      expect(clear, contains('_isDeletionLease(lease)'));
      expect(
        clear,
        contains(
          'LOWER(TRIM(COALESCE(uploadLease, ?))) NOT LIKE ?',
        ),
      );
      expect(clear, contains("'delete:%'"));
    });

    test('metadata PATCH is bound to a captured recording session', () {
      final int update =
          repositoryApi.indexOf('Future<void> _updateRecordingBE(');
      final int fetch =
          repositoryApi.indexOf('Future<void> _fetchRecordingsFromBE(');
      final String metadataUpdate = repositoryApi.substring(update, fetch);

      expect(
        metadataUpdate,
        contains('runWithRecordingWorkflowLease<void>'),
      );
      expect(metadataUpdate, contains('await context.renew()'));
      expect(
        metadataUpdate,
        contains('accessToken: context.session.accessToken'),
      );
      expect(
        metadataUpdate,
        contains('host: context.session.backendHost'),
      );
      expect(metadataUpdate, contains("'name': persisted.name"));
      expect(metadataUpdate, isNot(contains('FlutterSecureStorage')));
      expect(metadataUpdate, isNot(contains('Config.host')));

      final int controllerUpdate = recordingsController
          .indexOf('Future<Response<dynamic>> updateRecording');
      final int controllerDelete = recordingsController
          .indexOf('Future<Response<dynamic>> deleteRecording');
      final String patch =
          recordingsController.substring(controllerUpdate, controllerDelete);
      expect(patch, contains("host: host"));
      expect(patch, contains("'Authorization': 'Bearer \$accessToken'"));
      expect(patch, contains('followRedirects: false'));
      expect(patch, contains('maxRedirects: 0'));
    });

    test('backend integer aliases never truncate fractional values', () {
      final int parser = uploadIntegrationHelpers.indexOf('int? _coerceInt(');
      final int nextDeclaration = uploadIntegrationHelpers.indexOf(
        'Future<BestEffortBatchResult',
        parser,
      );
      final String readInt =
          uploadIntegrationHelpers.substring(parser, nextDeclaration);

      expect(readInt, contains('value.isFinite'));
      expect(readInt, contains('value == value.truncateToDouble()'));
      expect(
          readInt, isNot(contains('if (value is num) return value.toInt()')));
    });

    test('recording fetch uses one captured session through acceptance', () {
      final int fetch =
          repositoryApi.indexOf('Future<void> _fetchRecordingsFromBE(');
      final int filtered = repositoryApi.indexOf(
        'Future<void> _fetchFilteredPartsForRecordingsFromBE(',
      );
      final String recordingFetch = repositoryApi.substring(fetch, filtered);

      expect(recordingFetch, contains('sessionProvider.capture()'));
      expect(
        recordingFetch,
        contains('accessToken: session.accessToken'),
      );
      expect(recordingFetch, contains('host: session.backendHost'));
      expect(
        recordingFetch,
        contains('_requireRecordingSessionCurrent(sessionProvider, session)'),
      );
      expect(
        recordingFetch,
        contains('environment: session.environment'),
      );
      expect(
        recordingFetch,
        contains('DatabaseNew._fetchedRecordingSession = session'),
      );
      expect(
        recordingFetch,
        contains('_getRecordingsForCapturedSession(session)'),
      );
      final int requestCall =
          recordingFetch.indexOf('_recordingsApi.fetchRecordingsForUser');
      final int responseSessionCheck = recordingFetch.indexOf(
        '_requireRecordingSessionCurrent(sessionProvider, session)',
        requestCall,
      );
      final int snapshotAssignment =
          recordingFetch.indexOf('DatabaseNew.fetchedRecordings = recordings');
      expect(responseSessionCheck, greaterThan(requestCall));
      expect(snapshotAssignment, greaterThan(responseSessionCheck));

      final int controllerFetch = recordingsController
          .indexOf('Future<Response<dynamic>> fetchRecordingsForUser');
      final int generalFetch = recordingsController.indexOf(
        'Future<Response<dynamic>> fetchRecordings(',
        controllerFetch,
      );
      final String request =
          recordingsController.substring(controllerFetch, generalFetch);
      expect(request, contains('host: host'));
      expect(request, contains("'Authorization': 'Bearer \$accessToken'"));
      expect(request, contains('followRedirects: false'));
    });

    test('single-record fetch persists only a validated captured session', () {
      final int fetch =
          repositoryApi.indexOf('Future<int?> _fetchRecordingFromBE(');
      final String singleFetch = repositoryApi.substring(fetch);

      expect(singleFetch, contains('sessionProvider.capture()'));
      expect(
        singleFetch,
        contains('accessToken: session.accessToken'),
      );
      expect(singleFetch, contains('host: session.backendHost'));
      expect(
        singleFetch,
        contains('environment: session.environment'),
      );
      expect(singleFetch, contains('capturedSession: session'));
      expect(
        singleFetch,
        contains('capturedEnvironment: session.environment'),
      );
      expect(
        singleFetch,
        contains('recordingBelongsToCapturedAccount('),
      );
      expect(
        singleFetch,
        isNot(contains(
          'responseOwnerId == null || responseOwnerId == capturedUserId',
        )),
      );
      expect(
        singleFetch,
        contains('if (responseRecordingId != id)'),
      );

      final int request =
          singleFetch.indexOf('_recordingsApi.fetchRecordingById');
      final int acceptedSession = singleFetch.indexOf(
        '_requireRecordingSessionCurrent(sessionProvider, session)',
        request,
      );
      final int status = singleFetch.indexOf(
        'if (response.statusCode != 200)',
        request,
      );
      final int decode = singleFetch.indexOf('jsonDecode(', request);
      final int persist =
          singleFetch.indexOf('DatabaseNew.insertRecording(', request);
      expect(acceptedSession, greaterThan(request));
      expect(status, greaterThan(acceptedSession));
      expect(decode, greaterThan(status));
      expect(persist, greaterThan(decode));

      final int controllerFetch = recordingsController
          .indexOf('Future<Response<dynamic>> fetchRecordingById');
      final int summary = recordingsController.indexOf(
        'Future<Response<dynamic>> fetchRecordingPartSummary',
        controllerFetch,
      );
      final String requestContract =
          recordingsController.substring(controllerFetch, summary);
      expect(requestContract, contains('host: host'));
      expect(
        requestContract,
        contains("'Authorization': 'Bearer \$accessToken'"),
      );
      expect(requestContract, contains('followRedirects: false'));
      expect(requestContract, contains('maxRedirects: 0'));
    });

    test('captured insertion preserves explicit unowned backend records', () {
      final int insert =
          repository.indexOf('static Future<int> insertRecording(');
      final int all = repository.indexOf(
        'static Future<List<Map<String, dynamic>>> getAllRecordings',
        insert,
      );
      final String insertion = repository.substring(insert, all);

      expect(insertion, contains('recordingBelongsToCapturedAccount('));
      expect(insertion, contains("final String desiredMail ="));
      expect(insertion, contains("final int? desiredUserId ="));
      expect(insertion, contains("'mail': desiredMail"));
      expect(insertion, contains("'userId': desiredUserId"));
      expect(
        insertion,
        isNot(contains('recording.userId == null ||')),
      );
    });

    test('sync does not repeat missing-recording cache deletion', () {
      final int sync =
          repository.indexOf('static Future<void> syncRecordings()');
      final int listing =
          repository.indexOf('static Future<List<Recording>> getRecordings()');
      final String syncBody = repository.substring(sync, listing);

      expect(syncBody, isNot(contains('deleteRecordingFromCache')));
      expect(syncBody, isNot(contains('missing on backend, during sync')));
    });

    test('part reconciliation uses validated parent details, not a fake route',
        () {
      final int adapter = repositoryApi.indexOf(
        'Future<bool> recordingPartExists(',
      );
      final int nextMethod = repositoryApi.indexOf(
        'void _requireSuccess(',
        adapter,
      );
      final String reconciliation =
          repositoryApi.substring(adapter, nextMethod);

      expect(adapter, greaterThanOrEqualTo(0));
      expect(nextMethod, greaterThan(adapter));
      expect(
        reconciliation,
        contains('_recordingsApi.fetchRecordingById('),
      );
      expect(reconciliation, contains('includeParts: true'));
      expect(reconciliation, contains('accessToken: session.accessToken'));
      expect(reconciliation, contains('host: session.backendHost'));
      expect(
        reconciliation,
        contains('recordingPayloadConfirmsPartExists('),
      );
      expect(reconciliation, contains('status == 204'));
      expect(
        reconciliation,
        isNot(contains('_recordingPartsApi.fetchPart(')),
      );
    });

    test('legacy part recovery points to the real sound route securely', () {
      final int fetch = recordingPartsController
          .indexOf('Future<Response<dynamic>> fetchPart');
      final int download = recordingPartsController.indexOf(
        'Future<Response<List<int>>> downloadPartSound',
        fetch,
      );
      final String reconciliation =
          recordingPartsController.substring(fetch, download);

      expect(fetch, greaterThanOrEqualTo(0));
      expect(download, greaterThan(fetch));
      expect(
        reconciliation,
        contains("'/recordings/part/\$backendPartId/sound'"),
      );
      expect(reconciliation, isNot(contains('\$backendRecordingId/')));
      expect(
        reconciliation,
        contains("'Authorization': 'Bearer \$accessToken'"),
      );
      expect(reconciliation, contains('followRedirects: false'));
      expect(reconciliation, contains('maxRedirects: 0'));
      expect(
        reconciliation,
        contains('validateStatus: (status) => status != null && status < 500'),
      );
    });
  });
}
