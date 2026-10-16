import '../services/local_job_deletion_v3.dart';
import '../core/supabase_config.dart';
import 'briskers_local_database.dart';

final BriskersLocalDatabase localDatabase = BriskersLocalDatabase.defaults();

Future<void> initializeLocalDatabase() async {
  LocalJobDeletionV3.currentActorIdProvider = () {
    try { return supabase.auth.currentUser?.id; } catch (_) { return null; }
  };
  await localDatabase.customSelect('SELECT 1').get();
  await LocalJobDeletionV3.ensureSchema(localDatabase);
  final pending = await localDatabase.customSelect(
    "SELECT DISTINCT business_id FROM local_job_deletion_v3_cleanup WHERE state<>'complete'",
  ).get();
  for (final row in pending) {
    await LocalJobDeletionV3.resumePendingCleanup(localDatabase, row.read<String>('business_id'));
  }
}

