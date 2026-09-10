# Preprod Administration migration

## Mobile changes (2026-09-09)

Preprod uses `https://preprod-administration.strnadi.cz/` for PKCE authorization,
refresh and project token exchange. The Strnadi project is
`01a08608-44b7-7aba-8d0c-542148b30bf2`. Production and development retain legacy
login. Public build overrides remain `STRNADI_PREPROD_ADMINISTRATION_URL`,
`STRNADI_PREPROD_PROJECT_ID` and `STRNADI_PREPROD_API_HOST`.

## Code ownership

- `lib/config/config.dart`: the only runtime configuration loader. Administration
  URLs and project IDs use its existing defaults, `assets/config.json`, and
  `--dart-define` override pipeline. `oauth_configuration.dart` in the same folder
  is an immutable, validated configuration value; it does not load settings.
- `lib/api/controllers/auth_controller.dart`: authorization-code, refresh and
  project-exchange requests, form encoding and HTTP error classification, alongside
  the existing authentication endpoints. `UserController` owns account requests;
  `lib/api/models/administration_profile.dart` maps profile responses.
- `lib/api/dio_client.dart`: shared HTTP defaults, logging and credential handling.
  Token requests use a separate request queue from the call waiting for renewal,
  initialized by the same factory. They cannot attach a Bearer token or recurse
  through the authenticated queue. There is no parallel HTTP client implementation.
- `lib/auth/administration/`: session lifecycle, PKCE, secure credential persistence
  and browser UI. It consumes `Config` and the API controller; it does not load
  configuration or implement HTTP requests.

Optional asset keys follow the existing flat configuration:
`administrationurl` / `projectid`, `devadministrationurl` / `devprojectid`, and
`preprodadministrationurl` / `preprodprojectid`. The corresponding existing
`STRNADI_*ADMINISTRATION_URL` and `STRNADI_*PROJECT_ID` build overrides take
precedence, including explicit invalid/empty values that fail validation.

The system-browser login activates the existing app session only after receiving
a readable project JWT with the expected issuer, audience, expiry and GUID
subject. These checks constrain outbound routing; Tenant must verify signatures.
Administration tokens remain in separate secure storage. Tenant requests receive
only the project token; account mutations receive the Administration token. The own-profile endpoint
receives the project token so the response includes roles for the active project.
Dio disables credentialed redirects and does not replay mutations after failures.
Anonymous preprod requests cannot inherit a legacy JWT.

User identities accept a legacy positive integer or a normalized GUID, without
converting GUIDs into numbers. Recordings, ownership checks, caches, author
filters, achievements and device bindings preserve that distinction. OAuth data
uses `preprod|issuer-origin|tenant-origin|project-guid`, separate from old
`preprod` data. No migration rewrites old owners, backend IDs, recovery identifiers
or recording files. Existing SQLite INTEGER-affinity owner columns can retain
GUID text without a destructive table rebuild. Account matching never uses email
to bridge an old numeric account to a GUID. Legacy preprod recordings remain in
their original scope and need a separately agreed recovery/import procedure.

| Operation | Preprod destination |
| --- | --- |
| Sign in, renew, exchange | Administration `/connect/authorize`, `/connect/token` |
| Request password reset | Administration POST `/account/forgot-password`; reset is completed on the emailed browser page |
| Read/update own profile | Administration GET/PATCH `/account/profile`, with the project token |
| Read profile photo | Administration GET `/users/{guid}/profile-photo` |
| Upload profile photo | Administration POST `/account/profile-photo` |
| Delete own account | Administration DELETE `/account` |
| Connected providers | Administration GET `/account/external-logins` |
| Recordings, parts, maps, articles, achievements, devices, notifications | Tenant API |

## Backend fixes verified in source — deployment not verified

The updated `Strnadi-API/v2` checkout now has:

- `DisableAccessTokenEncryption()` and local OpenIddict validation.
- `AccountMutation` authorization accepting cookie or Bearer credentials, with
  caller resolution from `sub` or `ClaimTypes.NameIdentifier`.
- GET/PATCH `/account/profile`. The app maps `userName` to its nickname field,
  sends only the five supported editable fields, checks the returned GUID against
  the active owner, and uses explicit project roles for the existing role UI.
  An empty roles array clears previously cached role metadata.
- A Razor reset-password page at `/account/reset-password`; the old JSON POST
  action was removed. The app requests the email and leaves completion to the
  browser. Its legacy JWT-reset method is unavailable in preprod and sends no
  request to the removed JSON API.

Foreign profiles remain deliberately unavailable. The own-profile endpoint must
never be substituted for a requested foreign account. The existing public GUID
profile-photo endpoint is a separate contract.

Remaining gate: verify exchange authentication, active/deleted accounts,
membership removal, project-token lifetime/refresh and concurrent foreground /
background rotation against the deployed environment on Android and iOS. Source
checks and mocked tests do not establish those results. No backend file or
live account was modified by this mobile follow-up.

## Validation and device QA

Automated verification uses mocked HTTP transports, secure-storage channels and
key-value stores; no API or SQLite database is used in tests. The login screen
has a golden and cancellation/retry coverage. GUID tests cover ownership,
legacy separation, project switching, logical-session renewal and logout.

Before release, verify on Android and iOS: browser sign-in and registration,
cancel/retry, project exchange, expiry/refresh, logout and environment switching,
profile operations, account deactivation, and token rejection.
Record offline; interrupt upload after parent creation; restart and retry under
the same GUID/project; verify original recovery IDs and files survive. Check
camera, microphone/location permissions, background upload and notifications.
Test old integer-owned preprod recordings separately; do not adopt them by email.
No signed build, device QA, or authenticated live integration is established here.

### Initial migration results (before profile-contract follow-up)

- Final focused OAuth, HTTP routing, GUID, draft reconciliation and upload tests:
  **304 passed**.
- Broader mocked suite with coverage: **1,416 passed, 2 failed**. The failures are
  the pre-existing dynamic translation key in `map_cluster_picker.dart` and
  `recording_note_card_narrow.png`; neither baseline was changed to hide failures.
- Static analysis: no errors; existing map warnings and repository lint notices
  remain. `git diff --check` passes.
- New login golden was rendered with Roboto and visually reviewed; it uses the
  existing yellow button color. Cancellation and retry pass.
- API repository and deployment were not changed. Public discovery was the only
  live API check; authenticated flows and device QA remain unverified.

### Profile-contract follow-up

The follow-up passed **164** targeted OAuth, profile, user and configuration tests
plus **3** profile-normalization tests. Tests cover project-token routing to the
own-profile endpoint, nickname/role conversion, supported PATCH fields, foreign
owner rejection, unexpected response ownership, HTTP 403 propagation, and no
request to the removed JSON reset API. Targeted analysis has no errors or warnings;
existing naming/deprecation lint notices remain in the two user screens. The full
suite above was not rerun for this follow-up. No live or device test was performed.

### API/configuration consolidation

Authorization requests now live in `AuthController`, with the shared
`ApiDioClient` setup and URI builder. The standalone HTTP transport, unused
project client, and separate build-configuration loader were removed; no
forwarding compatibility files remain. Configuration is loaded only by `Config`.
Configuration and API-model tests moved alongside their corresponding layers.

Final focused verification: **121 passed**. Full mocked suite with coverage:
**1,424 passed, 2 existing failures** (the map translation key and recording-note
narrow golden). Focused analysis reported no errors or warnings; existing lint
notices remain. Regression tests exercise real controller/Dio wiring, renewal
inside an authenticated request without deadlock, rejection of foreign/insecure
origins, no automatic retry after 401, and rejection of a response after logout.
`git diff --check` passes. No deployment or device verification was performed.

### Browser logout

Mobile logout closes the scoped OAuth owner and clears local credentials before
opening Administration `/connect/logout` in the system authentication browser.
Login and logout use non-ephemeral browser sessions so the logout request can
use the browser's login cookie. No tokens are placed in the logout URL and no
Dio request attempts to impersonate the browser cookie session. The existing
backend route accepts GET as well as POST. Environment switching occurs after
this browser step, using the captured old environment.

The backend accepts `redirect_uri`; the app sends the existing registered
`com.delta.strnadi://auth/callback` through the API controller's logout URL
builder. The system browser returns to the app automatically. Only that exact
callback is treated as a completed browser logout; cancellation or another URL
still leaves the app locally signed out. This is the backend's custom
`redirect_uri` contract, not OIDC `post_logout_redirect_uri`.

Device QA remains required for iOS/Android cookie sharing and automatic return.
The iOS shared-session consent prompt remains unchanged. The backend should
allowlist redirect destinations; the checked-out action currently forwards the
query value directly into AuthenticationProperties.RedirectUri.
