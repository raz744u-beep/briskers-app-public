/// Local expense entry never grants unrelated server-only Job actions.
bool canRecordJobExpense({
  required String role,
  required bool onlineManage,
  required bool localVerified,
  required bool firstFrameOnly,
  required bool contentBlocked,
}) {
  if (contentBlocked || firstFrameOnly) return false;
  return onlineManage ||
      (localVerified && const {'owner', 'manager', 'office'}.contains(role));
}
