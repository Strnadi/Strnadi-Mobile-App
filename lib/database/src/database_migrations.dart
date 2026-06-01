part of 'database_repository.dart';

Future<void> _ensureBaseTables(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS recordings(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
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
      totalSeconds REAL,
      partCount INTEGER,
      env STRING DEFAULT 'prod'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS recordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
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
      read INTEGER DEFAULT 0
    )
  ''');
  await _ensureDialectsTable(db);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS FilteredRecordingParts(
      id INTEGER PRIMARY KEY,
      BEId INTEGER UNIQUE,
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
      BEId INTEGER UNIQUE,
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

Future<void> _ensureDialectsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS Dialects (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      BEID INTEGER UNIQUE,
      recordingId INTEGER,
      recordingBEID INTEGER,
      userGuessDialect TEXT,
      adminDialect TEXT,
      startDate TEXT,
      endDate TEXT
    )
  ''');
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
