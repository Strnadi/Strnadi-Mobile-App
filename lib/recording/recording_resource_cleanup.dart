Future<void> shutdownRuntimeThenDisposeRecorder({
  required Future<void> Function() shutdownRuntime,
  required Future<void> Function() disposeRecorder,
}) async {
  try {
    await shutdownRuntime();
  } finally {
    await disposeRecorder();
  }
}
