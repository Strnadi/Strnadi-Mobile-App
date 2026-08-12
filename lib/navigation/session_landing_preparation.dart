typedef ActiveVerifiedSessionIdCapture = Future<String?> Function();
typedef GuestDraftAdoption = Future<void> Function();

/// Prepares local recording ownership before exposing authenticated screens.
///
/// Dependencies are injected so ordering and failures can be verified without
/// opening SQLite or activating a real authentication/API client.
Future<bool> prepareSessionLanding({
  required ActiveVerifiedSessionIdCapture captureActiveVerifiedSessionId,
  required GuestDraftAdoption adoptGuestDrafts,
}) async {
  final String? initialSessionId = await captureActiveVerifiedSessionId();
  if (initialSessionId == null || initialSessionId.trim().isEmpty) return false;

  await adoptGuestDrafts();

  // Adoption is transactionally bound to its captured login, but the session
  // can still be invalidated immediately after that transaction commits.
  // Rechecking prevents navigation under a login that changed while the local
  // drafts were being adopted.
  final String? currentSessionId = await captureActiveVerifiedSessionId();
  return currentSessionId == initialSessionId;
}
