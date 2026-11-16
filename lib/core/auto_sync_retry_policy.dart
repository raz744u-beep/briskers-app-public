/// Conservative retry delays for durable pending customer/invoice outbox work.
/// The app attempts reconciliation while foregrounded; no polling occurs in
/// Force Offline, and no data is discarded after an unavailable endpoint.
class AutoSyncRetryPolicy {
  const AutoSyncRetryPolicy._();

  static Duration delayAfterStalledAttempt(int stalledAttempts) {
    if (stalledAttempts <= 0) return const Duration(minutes: 1);
    // 2, 4, 8, 15, 15... minutes after attempts that made no progress.
    final exponent = stalledAttempts > 4 ? 4 : stalledAttempts;
    final minutes = 1 << exponent;
    return Duration(minutes: minutes > 15 ? 15 : minutes);
  }

  static bool eligible({
    required bool inForeground,
    required bool forceOffline,
    required bool busy,
    required int pendingCount,
    required DateTime now,
    DateTime? notBefore,
  }) =>
      inForeground &&
      !forceOffline &&
      !busy &&
      pendingCount > 0 &&
      (notBefore == null || !now.isBefore(notBefore));
}
