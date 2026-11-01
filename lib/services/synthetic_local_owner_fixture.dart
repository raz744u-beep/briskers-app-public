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
  static const paymentJob = 'dad00000-0000-4000-8000-000000000006';
  static const paymentInvoice = 'dad00000-0000-4000-8000-000000000007';
  static const paymentOperation = 'dad00000-0000-4000-8000-000000000008';

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
    // Idempotent fixture: creates only fake financial records inside the
    // separately installed synthetic TEST application, never production.
    await db.transaction(() async {
      await db.customStatement(
        "INSERT OR IGNORE INTO local_jobs "
        "(id,business_id,access_scope,title,status,job_number,sync_state) "
        "VALUES (?,?,'full','TEST: Fake payment repair','open','TEST-7003','synced')",
        [paymentJob, business]);
      await db.customStatement(
        "INSERT OR IGNORE INTO local_documents "
        "(id,business_id,job_id,kind,document_number,status,sync_state,total) "
        "VALUES (?,?,?,'invoice','TEST-8003','open','synced',450.00)",
        [paymentInvoice, business, paymentJob]);
      // A queued receipt is intentionally fake. Nothing was charged,
      // received or submitted. The app is forced into Offline mode.
      await db.customStatement(
        "INSERT INTO sync_outbox "
        "(business_id,entity_type,entity_id,operation,payload_json) "
        "SELECT ?,'invoice_payment_received',?,'record_received_payment',? "
        "WHERE NOT EXISTS (SELECT 1 FROM sync_outbox WHERE business_id=? "
        "AND entity_type='invoice_payment_received' AND entity_id=?)",
        [business, paymentInvoice, jsonEncode({
          'synthetic_test_only': true, 'operation_id': paymentOperation,
          'invoice_id': paymentInvoice, 'method_name': 'TEST cash',
          'amount_cents': 20000,
        }), business, paymentInvoice]);
      await db.customStatement(
        "INSERT OR IGNORE INTO local_financial_cache "
        "(business_id,cache_key,payload_json) VALUES (?,?,?)",
        [business, 'synthetic_payment_audit:$paymentJob', jsonEncode({
          'synthetic_test_only': true, 'job_id': paymentJob,
          'invoice_id': paymentInvoice, 'action': 'FAKE amount edited',
          'before_cents': 10000, 'after_cents': 20000,
        })]);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_business_context_$actor', jsonEncode({
      'business_id': business,
      'business_name': 'Briskers ISOLATED TEST — NO REAL DATA',
      'role_code': 'owner',
    }));
  }
}
