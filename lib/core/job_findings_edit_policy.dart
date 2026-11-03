/// Role- and provenance-scoped permission for editing Job vehicle findings.
/// A verified full local Job may accept Owner edits while offline, even when
/// its cached server capabilities are missing. Preview snapshots never grant
/// writes; server-backed actions retain their existing capability checks.
bool canEditJobFindings({
  required bool firstFrameOnly,
  required bool contentBlocked,
  required bool serverAllows,
  required bool onlineReady,
  required bool isOwner,
  required bool verifiedLocal,
}) {
  if (firstFrameOnly || contentBlocked) return false;
  if (serverAllows) return true;
  return !onlineReady && isOwner && verifiedLocal;
}
