/// In-memory telemetry boundary. No account identifiers or platform reads.
class TelemetrySession {
  static final foreground = TelemetrySession();

  int _generation = 0;
  int get generation => _generation;
  DateTime get startedAt => _startedAt;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  void reset() {
    _generation++;
    // Sentry serializes timestamps at millisecond precision.
    _startedAt = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    );
  }
}
