import 'package:briskers_app/local/briskers_local_database.dart';

/// Models the scheduler reaching an already-tested cooldown in synthetic DBs.
/// Never releases conflict/review/inflight holds or resets attempt budgets.
Future<void> expireSyncReplayCooldown(BriskersLocalDatabase db) async {
  final installed = await db.customSelect(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='sync_replay_fences_v1'",
  ).get();
  if (installed.isEmpty) return;
  await db.customStatement(
    "UPDATE sync_replay_fences_v1 SET not_before_ms=0 WHERE status='ready'",
  );
}
