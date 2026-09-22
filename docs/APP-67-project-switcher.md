# APP-67 project switching

The project selector is in the profile menu for Administration sessions (currently
preprod). Legacy prod/dev authentication does not provide project discovery.

Backend contract verified against Strnadi-API `rewrite`, commit `9d24c7af`:

- `GET /connect/user-info`, with the Administration bearer token, identifies the
  signed-in account before selecting its initial project.
- `GET /users/{id}/projects`, with the Administration bearer token, returns
  `id`, `name`, `description`, `domain`, and nullable `apiDomain`. This endpoint
  lists role-associated projects. Token exchange additionally checks membership.
- `GET /projects` supplies the browseable catalog. `POST
  /projects/{projectId}/members` joins the caller using JSON `{ "email": ... }`;
  the email is read from the authenticated `/account/profile` response and its
  account ID is checked. The app never submits a role or another user's email.
  A successful response must be HTTP 201 and identify the signed-in user.
- `POST /connect/token`, using the existing token-exchange grant and `project_id`,
  authorizes the chosen project. The client validates subject, issuer, expiry,
  and project audience before activating it.
- `domain` is a website URL and is never used for API requests. Missing or invalid
  HTTPS API origins are unavailable in the selector. Redirects are disabled for
  credential-bearing discovery and exchange requests.

Selection preferences are keyed by Administration issuer, environment and account.
The active routing descriptor is restored before capturing the activated session;
its existing scope marker must still match. Foreground online restoration checks
access again. A missing selection falls back to an accessible project only after
successful token exchange. Empty discovery or an unsuccessful fallback fails
closed with localized feedback. Offline restoration retains the established
session checks and cannot validate server-side revocation until online.

A switch prepares credentials before changing routing. It creates a new logical
session, rejects late responses from the previous session, clears the cached role,
and replaces the navigation stack without running guest-draft adoption. A local
activation failure restores the previous routing and credential. Recording,
paused capture, start/stop processing, and finalization block switching.

Recording ownership and persisted backend/upload identifiers are not migrated or
cleared. Their existing account/environment scope includes API origin and project
ID. Upload and cache guards therefore reject another project's records; pending
work cannot borrow the new project's credential. Background isolates restore the
same routing descriptor and validate the activated marker rather than performing
an automatic project fallback.

## Validation

Mocked tests cover discovery parsing, unsafe/missing API URLs, success, exchange
failure and retry, local storage rollback, account-specific selection, restart
routing restoration, revoked fallback, empty discovery, logout races, recording
blocking, stale upload ownership, and UI loading/error/empty states. Light/dark
selector goldens are included. No automated test calls a live API or SQLite.

## Device QA still required

On both iOS and Android with an account assigned to two projects:

1. Switch from the profile menu; verify active project, map, articles, profile,
   recordings and notifications refresh without showing the previous project.
2. Create a reviewed draft and queue an upload in A. Switch to B, then restart.
   Confirm A's files, backend IDs and retry state remain assigned to A; switch
   back and verify upload recovery without duplication.
3. Try switching while recording, while paused, and during finalization. Confirm
   the explanation appears and capture continues in its original project.
4. Interrupt discovery, exchange, and local persistence. Confirm retry behavior
   and that a failed switch keeps the old project usable.
5. Revoke access, restart online, and verify fallback and its notice. Repeat with
   no available projects. Restore offline and reconnect to check revocation.
6. Switch accounts and environments; verify remembered selections, cached data,
   delayed HTTP responses and background jobs cannot cross ownership boundaries.

Deployment of the discovery endpoints and authenticated live/device behavior
must be verified separately from these mocked tests.

## Joining projects

The selector offers Browse projects and Join. Joining preserves the active
project; the user then explicitly selects the joined project to switch. A new
account with no projects sees the same catalog during sign-in and can join its
first project before any Tenant session is activated. Cancelling leaves no
activated session. Join failures are retryable; the backend permits repeating a
self-join without assigning duplicate roles.

The current `/users/{id}/projects` implementation uses roles, so it omits
role-free memberships. Successful self-join IDs are retained as discovery hints
in storage keyed by account, issuer and environment, and resolved against the
current catalog. They never authorize requests: switching/restoration still
requires a valid project-token exchange. On a different installation, a role-free
membership can be opened by repeating the idempotent Join operation. The backend
should eventually expose membership-based discovery directly.

Additional mocked checks cover own-email-only JSON, 201/redirect handling,
identity mismatch, denied join and retry, role-free restoration, account isolation,
revoked access despite remembered membership, logout before POST, first-project
onboarding/navigation, and the browse/join UI. Device QA should also exercise
first login without memberships, self-join without a role, restart, a dropped
join response followed by retry, and cancellation/logout during discovery.

## Project diagnostics

Structured lifecycle logs use the shared `AppLogger` with scope `projects`.
Starts are debug-level; completion and lifecycle markers are info-level. Each
operation has a process-local operation ID, nested parent ID where applicable,
and elapsed milliseconds. Discovery and remembered-membership events include
counts. Expected denials, cancellation, session changes and recording guards
produce warnings; unexpected failures produce errors with the caught stack.
HTTP method/status/timing remain in the existing API diagnostics.

Coverage includes selector loading/browsing/joining/retrying/navigation,
first-project onboarding, account-project discovery, catalog requests,
membership persistence, project-token exchange, Administration refresh,
restoration, revoked-access fallback, switch commit/rollback, routing-preference
recovery, and logout. New project events never serialize account/project names,
IDs, API domains, email, credentials, response bodies, or arbitrary exception
messages. They use shared telemetry consent/redaction and failure deduplication;
stale operations are suppressed after a telemetry-session change. Activation
and guarded rollback boundaries log explicitly without retaining the prior
session's operation ID.

Logging tests use in-memory sinks and mocked boundaries to verify correlation,
classification, privacy, unchanged results/errors when logging fails, late-event
suppression, and real switch/rollback lifecycle markers. Native Sentry delivery
still requires consent-enabled device QA.

On interactive login, accounts with multiple usable project memberships see the
project selector before project-token exchange, even if a previous selection is
remembered. One usable project continues automatically. Cancelling the selector
cancels login without activating a project. Session restoration retains its
existing remembered-selection behavior. The login picker only lists memberships;
the settings selector continues to offer project browsing and joining.

Review follow-up: project switches clean up the old tenant device registration
and invalidate the Firebase token before changing the active project. Failed
token invalidation or binding cleanup aborts the switch. Commit and rollback
both synchronize notifications for their resulting logical session; logout
during cleanup cannot register a candidate. Registration failures are logged
and can be retried by the existing Firebase synchronization flow. Verify push
delivery on-device across A → B, rollback, and logout during a switch.

Restoration tries each discovered fallback after an access rejection, including
stale remembered memberships. Network, server, and session-change failures stop
restoration instead of being mistaken for rejected project access.
