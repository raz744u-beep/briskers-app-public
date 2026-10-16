import '../services/local_job_deletion_v3.dart';
import '../services/offline_job_purge.dart';
import '../core/supabase_config.dart';
import 'briskers_local_database.dart';

final BriskersLocalDatabase localDatabase = BriskersLocalDatabase.defaults();

Future<void> initializeLocalDatabase() async {
  LocalJobDeletionV3.currentActorIdProvider = () {
    try { return supabase.auth.currentUser?.id; } catch (_) { return null; }
  };
  await localDatabase.customSelect('SELECT 1').get();
  await LocalJobDeletionV3.ensureSchema(localDatabase);
  await OfflineJobPurge.ensureSchema(localDatabase);
  final localPurges = await localDatabase.customSelect(
    "SELECT business_id,operation_id FROM local_offline_job_purge_requests WHERE cleanup_state<>'complete'",
  ).get();
  for (final row in localPurges) {
    await OfflineJobPurge.resumeCleanup(localDatabase, row.read<String>('business_id'), row.read<String>('operation_id'));
  }
  final pending = await localDatabase.customSelect(
    "SELECT DISTINCT business_id FROM local_job_deletion_v3_cleanup WHERE state<>'complete'",
  ).get();
  for (final row in pending) {
    await LocalJobDeletionV3.resumePendingCleanup(localDatabase, row.read<String>('business_id'));
  }
}

