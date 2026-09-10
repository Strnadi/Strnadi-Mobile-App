# APP-4: Automatic upload of offline recordings

Reviewed recordings are registered with the background scheduler before the form
checks connectivity for its confirmation message. Android work requires a network
connection; the upload service still enforces the current data preference and
activated account/environment on every attempt.

At app startup, resume, and connectivity changes, pending reviewed recordings for
the exact activated owner/environment are scheduled again. This also recovers
recordings left unscheduled by the old offline form. Overlapping scans are
coalesced, and individual scheduling failures do not stop the remaining queue.
Unreviewed drafts, active uploads, completed recordings, and recordings with a
previous backend upload attempt remain in their existing recovery flows.

The installed iOS Workmanager implementation executes one-off work immediately;
it does not provide Android's durable connectivity wait. The foreground/resume
retry covers that gap when the app runs again. Upload while iOS is suspended or
terminated is not guaranteed by this change.

## Automated validation

Tests use fake scheduling, API, session, and database boundaries. They cover
queueing while offline or blocked by network policy, registration failure,
reconnect recovery, session/environment changes, duplicate events, and exclusion
of draft/active/ambiguous uploads. Existing worker and upload-service regressions
cover deferred retries, retained identifiers, leases, and session isolation.

## Device QA (not yet performed)

1. On Android and iOS, sign in and complete several recordings in airplane mode.
   Confirm the saved/queued message and retained recordings.
2. Restore allowed connectivity with the app open. Confirm every queued recording
   uploads without tapping Send, once each.
3. Repeat with Wi-Fi-only enabled and mobile data available; uploads must wait
   for Wi-Fi. Repeat after closing and reopening the app.
4. Switch accounts/environments before reconnecting. Confirm old-scope recordings
   do not upload through the new session; switch back and reopen the app.
5. Interrupt an upload. Confirm persisted backend identifiers/local audio remain
   available and that the existing recovery flow does not create duplicates.
6. Verify Android background network scheduling and separately assess iOS
   suspension/resume behavior on physical devices.
