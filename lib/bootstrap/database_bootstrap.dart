enum DatabaseBootstrapPhase {
  openDatabase,
  runPostMigrationBackfills,
  enforceRecordingLimit,
  reconcileInterruptedUploads,
}

typedef DatabaseBootstrapStep = Future<void> Function();

class DatabaseBootstrapFailure implements Exception {
  const DatabaseBootstrapFailure({
    required this.phase,
    required this.cause,
    required this.stackTrace,
  });

  final DatabaseBootstrapPhase phase;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'Database bootstrap failed during ${phase.name}: $cause';
}

Future<void> runDatabaseBootstrap({
  required DatabaseBootstrapStep openDatabase,
  required DatabaseBootstrapStep runPostMigrationBackfills,
  required DatabaseBootstrapStep enforceRecordingLimit,
  required DatabaseBootstrapStep reconcileInterruptedUploads,
}) async {
  final steps = <(DatabaseBootstrapPhase, DatabaseBootstrapStep)>[
    (DatabaseBootstrapPhase.openDatabase, openDatabase),
    (
      DatabaseBootstrapPhase.runPostMigrationBackfills,
      runPostMigrationBackfills,
    ),
    (
      DatabaseBootstrapPhase.enforceRecordingLimit,
      enforceRecordingLimit,
    ),
    (
      DatabaseBootstrapPhase.reconcileInterruptedUploads,
      reconcileInterruptedUploads,
    ),
  ];

  for (final (phase, step) in steps) {
    try {
      await step();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        DatabaseBootstrapFailure(
          phase: phase,
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }
}
