import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import '../local/local_database_provider.dart';
import 'local_job_deletion_v3.dart';

/// Explicit, isolated Android TEST fixture. Not reachable in production.
class SyntheticLocalOwnerFixture {
  static const business = 'dad00000-0000-4000-8000-000000000001';
  static const actor = 'dad00000-0000-4000-8000-000000000002';
  static const syncedJob = 'dad00000-0000-4000-8000-000000000003';
  static const invoice = 'dad00000-0000-4000-8000-000000000004';
  static const otherJob = 'dad00000-0000-4000-8000-000000000005';

  static Future<void> initializeForTestOnly() async {
    if (!isSyntheticTestBuild) {
      throw StateError('Local demo provisioning is TEST-only.');
    }
    await BriskersConnectionModeController.instance
        .setMode(BriskersConnectionMode.offline);
    final db = localDatabase;
    await LocalJobDeletionV3.ensureSchema(db);
    await db.transaction(() async {
      await db.customStatement(
        "INSERT OR IGNORE INTO local_jobs "
        "(id,business_id,access_scope,title,status,job_number,sync_state) "
        "VALUES (?,?, 'full', 'TEST: Previously synced repair', 'open', "
        "'TEST-7001', 'synced')", [syncedJob, business]);
      await db.customStatement(
        "INSERT OR IGNORE INTO local_documents "
        "(id,business_id,job_id,kind,document_number,status,sync_state,total) "
        "VALUES (?,?,?,'invoice','TEST-8001','open','synced',125.00)",
        [invoice, business, syncedJob]);
      await db.customStatement(
        "INSERT OR IGNORE INTO local_jobs "
        "(id,business_id,access_scope,title,status,job_number,sync_state) "
        "VALUES (?,?, 'full', 'TEST: Unrelated repair', 'open', "
        "'TEST-7002', 'synced')", [otherJob, business]);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_business_context_$actor', jsonEncode({
      'business_id': business,
      'business_name': 'Briskers ISOLATED TEST — NO REAL DATA',
      'role_code': 'owner',
    }));
  }
}
