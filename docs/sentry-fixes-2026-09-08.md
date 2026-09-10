# Sentry fixes — 8 September 2026

Scope: the 43 mobile issues left open by the preceding review of `delta-strnadi/strnadi`. Changes are in the working tree on `release/2.1.0`; they have not been committed, deployed, or submitted to the stores. Existing unrelated changes were preserved.

**Verified Sentry status:** 9 newly resolved, 34 unresolved remain. Including the 25 resolved in the preceding review, 34 of the original 68 are now resolved.

## Implemented and regression tested

| Reported issues | Change | Verification |
| --- | --- | --- |
| NQ, P5, 10B | Login uses the validated profile parser. Missing/null optional metadata clears the old cache value; malformed profiles cannot assign null to a non-nullable String or retain an old role. | Fake secure-storage writer covers null/missing/wrong-type fields and replacement of previous metadata. |
| ZC, QR, XD | Recording location subscriptions handle stream errors. Repeated failures show one message until updates resume; audio remains under the recorder's control. Pause runs before permission requests, so revoked GPS permission cannot block stopping a segment. | Fake location stream covers errors, subsequent positions and cancellation. Existing location, permission and recording tests pass; permission-order wiring has a supplementary contract check. |
| 104 | Apple user cancellation returns normally before exchanging credentials with the backend. Other authorization failures still propagate. | Fake Apple requests cover success, cancellation and actual service failure. |
| 105 | An incomplete-upload lookup canceled by an account/environment change exits quietly and releases the prompt lock. Unexpected inspection failures remain reported. | Widget tests inject the lookup and failure reporter; no API or database is opened. A fresh lookup succeeds after cancellation. |
| ZQ | Policy/review/authentication deferral has an explicit retryable type. The upload adapter retains persisted identifiers, and the background worker requests a later retry without a false success/failure notification. | Fake upload service tests cover policy deferral and lease release. Worker regression checks preserved recording state, no dialect upload or error notice, resource cleanup, and a subsequent successful retry. This change covers the reported background upload path. |

These nine issue groups were marked resolved in Sentry and each status was verified by a subsequent API read. Resolution is based on the source fix; it is not a claim that affected devices are running this checkout.

## Additional changes awaiting device validation

| Issues | Change and remaining check |
| --- | --- |
| W9, W8, 10A, XY, WT, ZV, W1, WV, W2, ZZ, W4 | Android startup probes known secure-storage values before UI/services start. Only BadPadding/BAD_DECRYPT errors trigger recovery: authentication markers are invalidated first, unreadable known values removed, and readable preferences/device binding retained. No SQLite or audio deletion occurs. Backup/transfer rules exclude the two device-bound encrypted preference files. Fake-store tests cover preservation, repeated startup, non-decryption errors, and interrupted cleanup. Still requires restored/corrupted-install testing on Android; kept open. |
| 107 | Android Markdown downloads are staged in a dedicated cache directory and opened through a non-exported FileProvider with temporary read permission and a content URI. The provider cannot expose recordings outside that directory. Missing viewers/download failures fall back to the original URL. Dart fallback tests, isolated Java compilation and XML/reference validation pass. Full packaged-app/open-in-viewer testing remains; kept open. |
| 101 | Added an explicit app-prefixed keychain access group using the configured product bundle identifier. Entitlement plist validates. A signed device build must confirm provisioning and successful keychain reads; the old -34018 event alone does not prove which signing condition caused it. Kept open. |
| Z3, Y0 | The logical pause now owns all late native recorder events until resume commits the next segment. A late RECORD cannot expose Pause again after that segment's metadata was finalized. Regression tests cover late RECORD/STOP sequences and release on resume. The current discard path already bypasses pause/finalization. Original on-device pause/discard reproduction is still missing; kept open. |

Credential recovery may require signing in again. It does not reassign an existing recording to the next signed-in account.

## Still requires diagnosis outside these fixes

| Issues | Missing evidence / next check |
| --- | --- |
| 109, VP, X0, ZW, ZB, WR | Native signals/ANRs lack a verified causal code change. Reproduce on the affected platform and obtain symbolicated native stacks/thread traces for the matching release. |
| 106, WS, XK, X6, X4, XM, YX, ZS | Recorded HTTP 504, DNS, timeout and reset failures require endpoint/network verification in the affected environment. Client error handling cannot establish that the server or device network was repaired. |
| X1 | Firebase installation authentication requires the affected app signing/Firebase configuration and a device token-registration check. Existing mocked coordinator recovery does not establish that Firebase accepts the installation. |
| 102, 103 | The retained development events contain RenderFlex overflow amounts but no originating application widget/frame. Obtain a reproducible screen, locale, width and text scale before choosing a layout change. |
| ZR, Z2 | The current start flow already handles unavailable GPS without starting audio, and location resolution tests pass. Confirm GPS-disabled start/resume behavior on-device and recovery after enabling the service. |

## Validation

- Focused auth/security/recording/location/upload/database/bootstrap suite: **799 passed**.
- Full suite: **1,334 passed, 2 failed** in untouched areas: `test/localization/localization_contract_test.dart` rejects the dynamic translation key in the existing `lib/map/map_cluster_picker.dart`; `test/widgets/recording_note_card_test.dart` has a 117-pixel (0.24%) golden mismatch. No golden baselines were regenerated.
- After the final pause-state changes: **79 recording tests passed**.
- Targeted Dart analysis: **no errors or warnings**; three existing informational notices (two filenames and `withOpacity`). Full analysis also reports existing map warnings.
- Android `MainActivity.java` compiles in isolation against cached Android/Flutter/AndroidX/Play dependencies. Provider path restrictions, XML references, and entitlement plist validate. This does not replace manifest merging or device execution.
- Full Android Gradle validation is blocked before app compilation: repository wrapper **8.7**, installed Flutter minimum **8.14**. No toolchain versions were changed for this incident patch.
- `git diff --check` passes. All automated API/database boundaries were mocked.

## Device QA before release

1. Android: restore a test installation with invalid encrypted credentials. Confirm a sign-in is possible, language survives when readable, and existing recording files, backend IDs and account/environment ownership remain unchanged. Repeat after restarting the app.
2. Record, disable GPS/revoke location access, pause, enable GPS, resume and finish. Confirm usable audio, retained segments, and no stale native callback changing the paused controls. Repeat discard and interrupted finalization.
3. Open PDF/audio Markdown attachments on Android with and without a compatible viewer. Confirm a content URI and a temporary read grant; test protected-download fallback without exposing credentials.
4. Use a signed iOS build to read/write the keychain, restart, restore the session, and cancel Apple sign-in. Confirm cancellation makes no backend exchange and leaves the login screen usable.
5. Disable uploads by network policy, trigger a queued send, then re-enable uploads. Confirm no failure notification during deferral, one eventual upload, unchanged backend IDs and no duplicate recordings.
