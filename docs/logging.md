# Application logging

Use `AppLogger` from `package:strnadi/logging/app_logger.dart`. It owns console
output and Sentry reporting, including release builds and background callbacks.

```dart
final logger = AppLogger(scope: 'recording.upload');

try {
  await sendRecording();
} catch (error, stackTrace) {
  logger.e(
    'Recording upload failed.',
    reason: 'Unable to finish the recording upload',
    error: error,
    stackTrace: stackTrace,
  );
  rethrow;
}
```

Always pass the caught error and stack separately. Use a meaningful operation
message/reason; a missing stack is replaced with a stack explicitly labeled as
the logging location. For a known local policy outcome, pass `expected: true`.
Unexpected errors logged at warning level remain reportable.

## API failures

Shared Dio clients and the observing HTTP client record method, endpoint,
status, duration, backend reason/code/message, and request/correlation IDs.
Error-body inspection is bounded to 64 KiB and diagnostic fields to 200
characters. Successful binary responses are not inspected. URLs omit query
values; full request/response bodies and credentials are not logged.
For recording/dialect parsing, log structural counts or the payload type. Do
not interpolate response bodies or model lists into messages, even at trace
level: console diagnostics must also exclude recording contents.

When translating a response into a domain exception, retain its occurrence:

```dart
throw UploadException(
  'Recording upload failed.',
  response.statusCode ?? 500,
  logFailure: apiFailureForResult(response),
);
```

The exception's existing status contract is preserved. Logged HTTP status always
comes from an actual response. The shared occurrence prevents an outer catch or
Flutter's automatic error handler from producing another Sentry event or turning
an expected rejection into an unexpected failure.

## Sentry and background execution

- Unexpected application errors and API 5xx responses produce events.
- Expected 4xx responses, cancellation, and offline/retry outcomes produce
  breadcrumbs. API successes and other info/warning/error records are also
  breadcrumbs.
- Routine trace/debug records stay in the console. Sentry skips them
  synchronously before any consent platform reads or pending delivery work;
  records carrying a failure still pass through. Every forwarded record and
  outgoing event retains its current consent check, including background tasks.
- Foreground startup retains the existing consent and sampling configuration.
- Background callbacks use a task-owned Dart hub, including when Workmanager
  runs them in the main isolate. They never replace or close native Sentry.
- Background consent requires a stored authorization and, on iOS, a fresh ATT
  status check. No consent dialog or analytics initialization is triggered.
- Task completion drains pending logs for up to two seconds; telemetry failure
  never changes the upload's return value or retry policy.

## Validation

Behavior tests in `test/logging` inject sinks, transports, storage, and platform
calls. The full `flutter test --coverage` suite also covers recording recovery,
session isolation, redirects, and mocked uploads/downloads.

Device QA remains separate: on Android and iOS, verify foreground and scheduled
background delivery with consent granted; confirm no delivery when denied or
revoked. Use controlled API 401/422/500 responses and a local failure to verify
reasons, stacks, one event per unexpected occurrence, and successful background
retry behavior. Mocked tests do not establish native SDK or OS scheduling behavior.
