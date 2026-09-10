# Mobile map feature endpoint

Implements the CR-2026-004 response with `features`, without a contract-version parameter.
The map sends its center, zoom and logical viewport dimensions, dialect mode, clustering
switch, date range, and `ownerScope=Mine` plus the activated user ID for “only me”.
The existing “older” interval remains exclusive of 2017-01-01 by sending 2016-12-31
as the API's inclusive `createdTo` date.

The filter panel exposes `ownerScope=All|Mine|Others`, `mixDialects`, `mixSources`,
`onlyMeaningfulDialects`, and `hideOthersWithoutMeaningfulDialect`. Mixing controls
are enabled while clustering is on and keep their values when clustering is off.
Mine/Others and hiding others without a dialect require a verified current-user ID;
the last option supplies the ID even with ownerScope=All. Missing identity fails
closed instead of dropping the user-relative constraint. Guests can use all other
filters. Only-meaningful applies to everyone's recordings, including the current
user, when both meaningful-dialect options are enabled.

Every filter change invalidates pending results and refreshes the viewport. Reset
restores mixing=true/true, meaningful filters=false/false, ownerScope=All, and the
existing map/age/dialect-mode/clustering defaults.

Markers use the API's database colors and percentages directly, including unknown.
Representative selection, admin precedence and GPS fallback belong to the backend.
The app preserves representative and location-part identifiers separately. It rejects
malformed features instead of silently dropping recordings or substituting colors.

A cluster previews five recordings and loads additional pages only on demand. Failure
keeps the preview and allows retry. HTTP 409/410 closes the stale picker and refreshes
the viewport. Host, login session and request checks prevent stale results from opening
a recording or appending pages. Coincident/overlapping markers have a chooser; clusters
zoom to bounds when useful, otherwise open the paginated picker.

## Verification

Automated tests use fixture responses, fake loaders and a mocked Dio transport; no live
API or SQLite. Tests cover request serialization, both feature kinds, weighted colors,
unknown, invalid responses, cursor escaping, retry, expiry, stale results, and a marker
golden. A passing mock test does not establish that the draft backend is deployed.

Manual device QA against an implementation of this contract:

1. Check clustered and unclustered views and all three dialect modes. Compare marker
   segments with server percentages, including multiple same-dialect representatives.
2. Check All/Mine/Others and newer/older filters, especially date boundaries.
   Toggle each mixing and meaningful-dialect option, including both meaningful
   filters together. Check reset, disable/re-enable clustering, and guest controls.
3. Pan, zoom and rotate quickly; resize the viewport and check markers follow the latest
   request. Check antimeridian bounds and markers at the same coordinates.
4. Tap a standalone recording; zoom into a cluster and select every coincident group.
   For a cluster larger than five, load more and open its sixth recording.
5. Disconnect while paging, retry after reconnection, then expire/change a snapshot;
   ensure it refreshes without silently losing or duplicating members.
6. Switch account/environment or leave the map during a pending request. Ensure old
   details and queued page results never appear in the new session.
7. Check Czech, English and German text with large accessibility fonts.

This change does not modify recording capture, offline uploads or local database data.
