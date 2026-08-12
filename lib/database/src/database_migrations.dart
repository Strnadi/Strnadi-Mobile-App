part of 'database_repository.dart';

Future<void> _ensureBaseTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS recordings(
      id INTEGER PRIMARY KEY,
      userId INTEGER,
      BEId INTEGER,
      mail TEXT,
      createdAt TEXT,
      estimatedBirdsCount INTEGER,
      device TEXT,
      byApp INTEGER,
      name TEXT,
      note TEXT,
      path TEXT,
      sent INTEGER,
      downloaded INTEGER,
      sending INTEGER,
      uploadKey TEXT UNIQUE,
      uploadLease TEXT,
      uploadLeaseUpdatedAt INTEGER,
      parentUploadAttempted INTEGER DEFAULT 0,
      uploadDeviceId TEXT,
      captureReviewed INTEGER NOT NULL DEFAULT 1,
      totalSeconds REAL,
      partCount INTEGER,
      env STRING DEFAULT 'prod'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS recordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      recordingId INTEGER,
      backendRecordingId INTEGER,
      startTime TEXT,
      endTime TEXT,
      gpsLatitudeStart REAL,
      gpsLatitudeEnd REAL,
      gpsLongitudeStart REAL,
      gpsLongitudeEnd REAL,
      length INTEGER,
      path TEXT,
      square TEXT,
      sent INTEGER,
      sending INTEGER DEFAULT 0,
      uploadAttempted INTEGER DEFAULT 0,
      uploadKey TEXT UNIQUE,
      FOREIGN KEY(recordingId) REFERENCES recordings(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS images(
      id INTEGER PRIMARY KEY,
      recordingId INTEGER,
      path TEXT,
      sent INTEGER,
      FOREIGN KEY(recordingId) REFERENCES recordings(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Notifications (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      receivedAt TEXT NOT NULL,
      type INTEGER NOT NULL,
      read INTEGER DEFAULT 0,
      ownerUserId TEXT NOT NULL,
      env TEXT NOT NULL,
      providerMessageId TEXT
    )
  ''');
  await _ensureDialectsTable(db);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS DetectedDialects(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      predictedDialectId INTEGER,
      predictedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
  ''');
}

Future<void> _backfillUploadKeys(Database db) async {
  final List<Map<String, Object?>> recordings = await db.query(
    'recordings',
    columns: <String>['id', 'uploadKey'],
    where: 'uploadKey IS NULL OR TRIM(uploadKey) = ?',
    whereArgs: const <Object?>[''],
  );
  for (final Map<String, Object?> row in recordings) {
    await db.update(
      'recordings',
      <String, Object?>{'uploadKey': _newUploadKey('recording')},
      where: 'id = ? AND (uploadKey IS NULL OR TRIM(uploadKey) = ?)',
      whereArgs: <Object?>[row['id'], ''],
    );
  }

  final List<Map<String, Object?>> parts = await db.query(
    'recordingParts',
    columns: <String>['id', 'uploadKey'],
    where: 'uploadKey IS NULL OR TRIM(uploadKey) = ?',
    whereArgs: const <Object?>[''],
  );
  for (final Map<String, Object?> row in parts) {
    await db.update(
      'recordingParts',
      <String, Object?>{'uploadKey': _newUploadKey('recording-part')},
      where: 'id = ? AND (uploadKey IS NULL OR TRIM(uploadKey) = ?)',
      whereArgs: <Object?>[row['id'], ''],
    );
  }

  if (await _columnExists(db, 'Dialects', 'uploadKey')) {
    final List<Map<String, Object?>> dialects = await db.query(
      'Dialects',
      columns: <String>['id', 'uploadKey'],
      where: 'uploadKey IS NULL OR TRIM(uploadKey) = ?',
      whereArgs: const <Object?>[''],
    );
    for (final Map<String, Object?> row in dialects) {
      await db.update(
        'Dialects',
        <String, Object?>{'uploadKey': _newUploadKey('dialect')},
        where: 'id = ? AND (uploadKey IS NULL OR TRIM(uploadKey) = ?)',
        whereArgs: <Object?>[row['id'], ''],
      );
    }
  }
}

Future<void> _ensureDialectsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Dialects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      BEID INTEGER,
      recordingId INTEGER,
      recordingBEID INTEGER,
      uploadKey TEXT UNIQUE,
      uploadAttempted INTEGER DEFAULT 0,
      userGuessDialect TEXT,
      adminDialect TEXT,
      startDate TEXT,
      endDate TEXT
    )
  ''');
}

Future<void> _createScopedBackendIdIndexes(Database db) async {
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_recordings_env_beid '
    'ON recordings(env, BEId) WHERE BEId IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_recording_parts_parent_beid '
    'ON recordingParts(recordingId, BEId) WHERE BEId IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_dialects_recording_beid '
    'ON Dialects(recordingId, BEID) WHERE BEID IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_filtered_parts_recording_beid '
    'ON FilteredRecordingParts(recordingLocalId, BEId) '
    'WHERE BEId IS NOT NULL',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_detected_dialects_part_beid '
    'ON DetectedDialects(filteredPartLocalId, BEId) '
    'WHERE BEId IS NOT NULL',
  );
}

Future<void> _createNotificationScopeIndex(Database db) async {
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_notifications_owner_env_read '
    'ON Notifications(ownerUserId, env, read, receivedAt)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS '
    'idx_notifications_owner_env_message '
    'ON Notifications(ownerUserId, env, providerMessageId) '
    'WHERE providerMessageId IS NOT NULL '
    "AND TRIM(providerMessageId) <> ''",
  );
}

Future<void> _rebuildUploadTablesForScopedBackendIds(Database db) async {
  // Older builds allowed backend children to be cached with only their
  // local parent id or only their backend parent id. Restore both directions
  // while backend ids are still globally unique in the pre-v15 schema. The
  // reverse links use the local parent primary key, so they cannot cross an
  // account or environment even when backend ids overlap across environments.
  await db.rawUpdate(
    'UPDATE recordingParts SET backendRecordingId = ('
    'SELECT r.BEId FROM recordings r '
    'WHERE r.id = recordingParts.recordingId AND r.BEId IS NOT NULL LIMIT 1'
    ') WHERE backendRecordingId IS NULL AND recordingId IS NOT NULL '
    'AND BEId IS NOT NULL AND EXISTS ('
    'SELECT 1 FROM recordings r '
    'WHERE r.id = recordingParts.recordingId AND r.BEId IS NOT NULL'
    ')',
  );
  await db.rawUpdate(
    'UPDATE Dialects SET recordingBEID = ('
    'SELECT r.BEId FROM recordings r '
    'WHERE r.id = Dialects.recordingId AND r.BEId IS NOT NULL LIMIT 1'
    ') WHERE recordingBEID IS NULL AND recordingId IS NOT NULL '
    'AND BEID IS NOT NULL AND EXISTS ('
    'SELECT 1 FROM recordings r '
    'WHERE r.id = Dialects.recordingId AND r.BEId IS NOT NULL'
    ')',
  );
  await db.rawUpdate(
    'UPDATE recordingParts SET recordingId = ('
    'SELECT r.id FROM recordings r '
    'WHERE r.BEId = recordingParts.backendRecordingId LIMIT 1'
    ') WHERE recordingId IS NULL AND BEId IS NOT NULL',
  );
  await db.rawUpdate(
    'UPDATE Dialects SET recordingId = ('
    'SELECT r.id FROM recordings r '
    'WHERE r.BEId = Dialects.recordingBEID LIMIT 1'
    ') WHERE recordingId IS NULL AND BEID IS NOT NULL',
  );
  await db.rawUpdate(
    'UPDATE FilteredRecordingParts SET recordingLocalId = ('
    'SELECT r.id FROM recordings r '
    'WHERE r.BEId = FilteredRecordingParts.recordingBEID LIMIT 1'
    ') WHERE recordingLocalId IS NULL AND BEId IS NOT NULL',
  );
  await db.rawUpdate(
    'UPDATE DetectedDialects SET filteredPartLocalId = ('
    'SELECT p.id FROM FilteredRecordingParts p '
    'WHERE p.BEId = DetectedDialects.filteredPartBEID LIMIT 1'
    ') WHERE filteredPartLocalId IS NULL AND BEId IS NOT NULL',
  );

  await db.execute('''
    CREATE TABLE recordings_v15(
      id INTEGER PRIMARY KEY,
      userId INTEGER,
      BEId INTEGER,
      mail TEXT,
      createdAt TEXT,
      estimatedBirdsCount INTEGER,
      device TEXT,
      byApp INTEGER,
      name TEXT,
      note TEXT,
      path TEXT,
      sent INTEGER,
      downloaded INTEGER,
      sending INTEGER,
      uploadKey TEXT UNIQUE,
      uploadLease TEXT,
      uploadLeaseUpdatedAt INTEGER,
      parentUploadAttempted INTEGER DEFAULT 0,
      uploadDeviceId TEXT,
      totalSeconds REAL,
      partCount INTEGER,
      env STRING DEFAULT 'prod'
    )
  ''');
  await db.execute('''
    INSERT INTO recordings_v15 (
      id, userId, BEId, mail, createdAt, estimatedBirdsCount, device, byApp,
      name, note, path, sent, downloaded, sending, uploadKey, uploadLease,
      uploadLeaseUpdatedAt, parentUploadAttempted, uploadDeviceId,
      totalSeconds, partCount, env
    )
    SELECT
      id, userId, BEId, mail, createdAt, estimatedBirdsCount, device, byApp,
      name, note, path, sent, downloaded, sending, uploadKey, uploadLease,
      uploadLeaseUpdatedAt, parentUploadAttempted, uploadDeviceId,
      totalSeconds, partCount, env
    FROM recordings
  ''');

  await db.execute('''
    CREATE TABLE recordingParts_v15(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      recordingId INTEGER,
      backendRecordingId INTEGER,
      startTime TEXT,
      endTime TEXT,
      gpsLatitudeStart REAL,
      gpsLatitudeEnd REAL,
      gpsLongitudeStart REAL,
      gpsLongitudeEnd REAL,
      length INTEGER,
      path TEXT,
      square TEXT,
      sent INTEGER,
      sending INTEGER DEFAULT 0,
      uploadAttempted INTEGER DEFAULT 0,
      uploadKey TEXT UNIQUE,
      FOREIGN KEY(recordingId) REFERENCES recordings(id)
    )
  ''');
  await db.execute('''
    INSERT INTO recordingParts_v15 (
      id, BEId, recordingId, backendRecordingId, startTime, endTime,
      gpsLatitudeStart, gpsLatitudeEnd, gpsLongitudeStart, gpsLongitudeEnd,
      length, path, square, sent, sending, uploadAttempted, uploadKey
    )
    SELECT
      id, BEId, recordingId, backendRecordingId, startTime, endTime,
      gpsLatitudeStart, gpsLatitudeEnd, gpsLongitudeStart, gpsLongitudeEnd,
      length, path, square, sent, sending, uploadAttempted, uploadKey
    FROM recordingParts
  ''');

  await db.execute('''
    CREATE TABLE Dialects_v15 (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      BEID INTEGER,
      recordingId INTEGER,
      recordingBEID INTEGER,
      uploadKey TEXT UNIQUE,
      uploadAttempted INTEGER DEFAULT 0,
      userGuessDialect TEXT,
      adminDialect TEXT,
      startDate TEXT,
      endDate TEXT
    )
  ''');
  await db.execute('''
    INSERT INTO Dialects_v15 (
      id, BEID, recordingId, recordingBEID, uploadKey, uploadAttempted,
      userGuessDialect, adminDialect, startDate, endDate
    )
    SELECT
      id, BEID, recordingId, recordingBEID, uploadKey, uploadAttempted,
      userGuessDialect, adminDialect, startDate, endDate
    FROM Dialects
  ''');

  await db.execute('''
    CREATE TABLE FilteredRecordingParts_v15(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      recordingLocalId INTEGER,
      recordingBEID INTEGER,
      startDate TEXT,
      endDate TEXT,
      state INTEGER,
      representant INTEGER,
      parentBEID INTEGER,
      parentLocalId INTEGER,
      FOREIGN KEY(recordingLocalId) REFERENCES recordings(id)
    )
  ''');
  await db.execute('''
    INSERT INTO FilteredRecordingParts_v15 (
      id, BEId, recordingLocalId, recordingBEID, startDate, endDate, state,
      representant, parentBEID, parentLocalId
    )
    SELECT
      id, BEId, recordingLocalId, recordingBEID, startDate, endDate, state,
      representant, parentBEID, parentLocalId
    FROM FilteredRecordingParts
  ''');

  await db.execute('''
    CREATE TABLE DetectedDialects_v15(
      id INTEGER PRIMARY KEY,
      BEId INTEGER,
      filteredPartLocalId INTEGER,
      filteredPartBEID INTEGER,
      userGuessDialectId INTEGER,
      userGuessDialect TEXT,
      confirmedDialectId INTEGER,
      confirmedDialect TEXT,
      predictedDialectId INTEGER,
      predictedDialect TEXT,
      FOREIGN KEY(filteredPartLocalId) REFERENCES FilteredRecordingParts(id)
    )
  ''');
  await db.execute('''
    INSERT INTO DetectedDialects_v15 (
      id, BEId, filteredPartLocalId, filteredPartBEID, userGuessDialectId,
      userGuessDialect, confirmedDialectId, confirmedDialect,
      predictedDialectId, predictedDialect
    )
    SELECT
      id, BEId, filteredPartLocalId, filteredPartBEID, userGuessDialectId,
      userGuessDialect, confirmedDialectId, confirmedDialect,
      predictedDialectId, predictedDialect
    FROM DetectedDialects
  ''');

  await db.execute('DROP TABLE DetectedDialects');
  await db.execute('DROP TABLE FilteredRecordingParts');
  await db.execute('DROP TABLE recordingParts');
  await db.execute('DROP TABLE Dialects');
  await db.execute('DROP TABLE recordings');
  await db.execute('ALTER TABLE recordings_v15 RENAME TO recordings');
  await db.execute(
    'ALTER TABLE recordingParts_v15 RENAME TO recordingParts',
  );
  await db.execute('ALTER TABLE Dialects_v15 RENAME TO Dialects');
  await db.execute(
    'ALTER TABLE FilteredRecordingParts_v15 RENAME TO FilteredRecordingParts',
  );
  await db.execute(
    'ALTER TABLE DetectedDialects_v15 RENAME TO DetectedDialects',
  );
  await _createScopedBackendIdIndexes(db);
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: const <String>['name'],
    where: 'type = ? AND name = ?',
    whereArgs: <Object?>['table', tableName],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<Set<String>> _columnNames(Database db, String tableName) async {
  if (!await _tableExists(db, tableName)) {
    return <String>{};
  }
  final rows = await db.rawQuery('PRAGMA table_info($tableName)');
  return rows.map((row) => row['name']).whereType<String>().toSet();
}

Future<bool> _columnExists(
  Database db,
  String tableName,
  String columnName,
) async {
  final columns = await _columnNames(db, tableName);
  return columns.contains(columnName);
}

Future<void> _ensureColumn(
  Database db,
  String tableName,
  String columnName,
  String ddl,
) async {
  if (await _columnExists(db, tableName, columnName)) return;
  await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $ddl;');
}

Future<void> _renameColumnIfExists(
  Database db,
  String tableName,
  String oldName,
  String newName,
) async {
  if (!await _columnExists(db, tableName, oldName) ||
      await _columnExists(db, tableName, newName)) {
    return;
  }
  await db
      .execute('ALTER TABLE $tableName RENAME COLUMN $oldName TO $newName;');
}

Future<void> _migrateLegacyDialectsTable(Database db) async {
  if (!await _tableExists(db, 'Dialects')) {
    await _ensureDialectsTable(db);
    return;
  }

  final columns = await _columnNames(db, 'Dialects');
  final hasCurrentShape = columns.containsAll(<String>{
    'id',
    'recordingId',
    'recordingBEID',
    'userGuessDialect',
    'adminDialect',
    'startDate',
    'endDate',
  });
  if (hasCurrentShape) {
    return;
  }

  final legacyTable =
      'Dialects_legacy_${DateTime.now().microsecondsSinceEpoch}';
  await db.execute('ALTER TABLE Dialects RENAME TO $legacyTable;');
  await _ensureDialectsTable(db);

  String expression(String preferred, {String fallback = 'NULL'}) {
    if (columns.contains(preferred)) return preferred;
    return fallback;
  }

  final beId =
      columns.contains('BEID') ? 'BEID' : expression('BEId', fallback: 'NULL');
  final recordingId = columns.contains('recordingId')
      ? 'recordingId'
      : expression('RecordingId', fallback: 'NULL');
  final userGuess = columns.contains('userGuessDialect')
      ? 'userGuessDialect'
      : columns.contains('dialectCode')
          ? 'dialectCode'
          : expression('dialect', fallback: 'NULL');
  final startDate = columns.contains('startDate')
      ? 'startDate'
      : expression('StartDate', fallback: 'NULL');
  final endDate = columns.contains('endDate')
      ? 'endDate'
      : expression('EndDate', fallback: 'NULL');

  await db.execute('''
    INSERT INTO Dialects (
      BEID,
      recordingId,
      recordingBEID,
      userGuessDialect,
      adminDialect,
      startDate,
      endDate
    )
    SELECT
      $beId,
      $recordingId,
      ${expression('recordingBEID')},
      $userGuess,
      ${expression('adminDialect')},
      $startDate,
      $endDate
    FROM $legacyTable;
  ''');
  await db.execute('DROP TABLE $legacyTable;');
}
