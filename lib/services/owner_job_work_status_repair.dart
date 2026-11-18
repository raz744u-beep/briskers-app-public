import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_document_identity.dart';
import 'local_job_work_state.dart';
import 'local_job_retirement.dart';
import 'offline_job_admin_service.dart';

/// Applies the Owner's three confirmed decisions once to unambiguous records.
/// Percent complete is never evidence of a job's lifecycle status.
class OwnerJobWorkStatusRepair {
  OwnerJobWorkStatusRepair(this.db);
  final BriskersLocalDatabase db;

  Future<void> reconcile(String business, {required bool isOwner}) async {
    if (!isOwner || business != LocalDocumentIdentity.gloriaBusiness) return;
    final work = LocalJobWorkState(db);
    await work.prepare();
    await db.customStatement(
      '''CREATE TABLE IF NOT EXISTS owner_job_work_status_repair_v1 (
      business_id TEXT NOT NULL,job_number TEXT NOT NULL,job_id TEXT NOT NULL,
      invoice_id TEXT NOT NULL,evidence TEXT NOT NULL,PRIMARY KEY(business_id,job_number))''',
    );
    for (final target in const [
      ('J-41', '6360', 'Tyra Legard', 'in_progress'),
      ('J-56', '6376', 'Terrance Sanders', 'in_progress'),
      ('J-60', '6380', 'Glenn Smith', 'open'),
    ]) {
      await db.transaction(() async {
        final applied = await db
            .customSelect(
              'SELECT 1 FROM owner_job_work_status_repair_v1 WHERE business_id=? AND job_number=?',
              variables: [Variable(business), Variable(target.$1)],
            )
            .get();
        if (applied.isNotEmpty) return;
        final rows = await db
            .customSelect(
              '''SELECT j.*,d.id AS invoice_id FROM local_jobs j
          JOIN local_documents d ON d.business_id=j.business_id AND d.job_id=j.id AND d.kind='invoice'
          WHERE j.business_id=? AND j.job_number=? AND d.document_number=? AND lower(trim(j.customer_name))=lower(?)''',
              variables: [
                Variable(business),
                Variable(target.$1),
                Variable(target.$2),
                Variable(target.$3),
              ],
            )
            .get();
        if (rows.length != 1) return;
        final row = rows.single, id = row.read<String>('id');
        if (await LocalJobRetirement.isJobBlocked(db, business, id)) return;
        final code = row.read<String>('status').toLowerCase();
        if (LocalJobWorkState.terminal.contains(code) ||
            row.data['completed_at'] != null) {
          return;
        }
        final intent = await db
            .customSelect(
              'SELECT 1 FROM local_job_status_intent_v1 WHERE business_id=? AND job_id=?',
              variables: [Variable(business), Variable(id)],
            )
            .get();
        // A new explicit decision or a task action after installing this fix
        // supersedes the older report. Never reapply a correction every read.
        if (intent.isNotEmpty) return;
        final queued = await db
            .customSelect(
              "SELECT payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type='job_admin' AND state IN ('pending','conflict','inflight')",
              variables: [Variable(business), Variable(id)],
            )
            .get();
        for (final entry in queued) {
          try {
            final payload = jsonDecode(entry.read<String>('payload_json'));
            if (payload is Map &&
                payload['status_changed'] == true &&
                payload['status_code'] != target.$4) {
              return;
            }
          } catch (_) {
            return;
          }
        }
        if (target.$4 == 'open') {
          final activity = await db
              .customSelect(
                'SELECT 1 FROM local_job_task_activity_v1 WHERE business_id=? AND job_id=? AND started=1',
                variables: [Variable(business), Variable(id)],
              )
              .get();
          if (activity.isNotEmpty) return;
          final schema = await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name IN ('regular_payroll_tasks','regular_payroll_portions') AND type='table'",
              )
              .get();
          if (schema.length == 2) {
            final started = await db
                .customSelect(
                  "SELECT 1 FROM regular_payroll_tasks t JOIN regular_payroll_portions p ON p.business_id=t.business_id AND p.task_id=t.id WHERE t.business_id=? AND t.job_id=? AND p.state<>'Open' LIMIT 1",
                  variables: [Variable(business), Variable(id)],
                )
                .get();
            if (started.isNotEmpty) return;
          }
        }
        await db.customStatement(
          'INSERT INTO owner_job_work_status_repair_v1 VALUES(?,?,?,?,?)',
          [
            business,
            target.$1,
            id,
            row.read<String>('invoice_id'),
            jsonEncode({
              'source': 'Owner confirmed Bugs 39 job status',
              'customer': target.$3,
              'invoice_number': target.$2,
              'previous_status': code,
              'correct_status': target.$4,
            }),
          ],
        );
        await OfflineJobAdminService(database: db).queueStatus(
          business,
          id,
          code: target.$4,
          name: target.$4 == 'open' ? 'Open' : 'In progress',
          colorHex: target.$4 == 'open' ? '#D97706' : '#1674DB',
          iconKey: target.$4 == 'open' ? 'work_outline' : 'sync',
          note: 'Owner-confirmed Bugs 39 status correction; invoice and payments preserved.',
        );
      });
    }
  }
}
