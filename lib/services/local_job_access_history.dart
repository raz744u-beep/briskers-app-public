import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Device-only navigation history. Reading/syncing a job is never an access,
/// and an access never changes its server modification time or sync outbox.
class LocalJobAccessHistory {
  LocalJobAccessHistory({BriskersLocalDatabase? database})
    : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  static String? get currentUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // No authenticated session: don't pool history in a shared anonymous user.
      return null;
    }
  }

  Future<void> ensureTable() => _database.customStatement('''
    CREATE TABLE IF NOT EXISTS local_job_accesses (
      business_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      job_id TEXT NOT NULL,
      last_accessed_at INTEGER NOT NULL,
      PRIMARY KEY (business_id, user_id, job_id)
    )
  ''');

  Future<void> recordAccess(
    String businessId,
    String jobId, {
    required String userId,
    DateTime? at,
  }) async {
    if (businessId.isEmpty || jobId.isEmpty || userId.isEmpty) return;
    await ensureTable();
    await _database.customStatement(
      '''
      INSERT INTO local_job_accesses
        (business_id, user_id, job_id, last_accessed_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT (business_id, user_id, job_id) DO UPDATE SET
        last_accessed_at = MAX(last_accessed_at, excluded.last_accessed_at)
    ''',
      [
        businessId,
        userId,
        jobId,
        (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  /// UI-only hook. A failed history write must never stop the job opening.
  Future<void> recordCurrentUserAccess(String businessId, String jobId) async {
    final userId = currentUserId;
    if (userId == null) return;
    try {
      await recordAccess(businessId, jobId, userId: userId);
    } catch (_) {
      // Optional local navigation history, not a business mutation.
    }
  }

  /// Offline invoice conversion may replace its provisional Job ID. Retain
  /// the newest open for every user without leaking across businesses.
  Future<void> remapJob(
    String businessId,
    String localJobId,
    String serverJobId,
  ) async {
    if (localJobId == serverJobId || serverJobId.isEmpty) return;
    await ensureTable();
    await _database.transaction(() async {
      await _database.customStatement(
        '''
        INSERT INTO local_job_accesses
          (business_id, user_id, job_id, last_accessed_at)
        SELECT business_id, user_id, ?, last_accessed_at
        FROM local_job_accesses WHERE business_id = ? AND job_id = ?
        ON CONFLICT (business_id, user_id, job_id) DO UPDATE SET
          last_accessed_at = MAX(last_accessed_at, excluded.last_accessed_at)
      ''',
        [serverJobId, businessId, localJobId],
      );
      await _database.customStatement(
        '''
        DELETE FROM local_job_accesses WHERE business_id = ? AND job_id = ?
      ''',
        [businessId, localJobId],
      );
    });
  }
}
