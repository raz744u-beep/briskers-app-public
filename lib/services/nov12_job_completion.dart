import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/briskers_local_database.dart';
import '../core/document_presentation.dart';
import 'local_document_detail_cache.dart';
import 'offline_invoice_payment_ledger.dart';
import 'offline_job_admin_service.dart';

/// One-time application of the Owner's explicit completed-job decisions.
/// Task percentages never establish payment or job completion.
class Nov12JobCompletion {
  const Nov12JobCompletion(this.db);
  final BriskersLocalDatabase db;
  Future<void> reconcile(String business, {required bool isOwner}) async {
    if (!isOwner || business.isEmpty) return;
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS owner_nov12_job_completion_v1 (business_id TEXT NOT NULL,job_id TEXT NOT NULL,invoice_id TEXT NOT NULL,evidence TEXT NOT NULL,PRIMARY KEY(business_id,job_id))',
    );
    for (final target in const [
      ('J-38', '6357', 163762),
      ('J-49', '6368', 52131),
      ('J-40', '6359', 788211),
    ]) {
      await db.transaction(() async {
        final rows = await db
            .customSelect(
              "SELECT j.id AS job_id,j.status,d.id AS invoice_id FROM local_jobs j JOIN local_documents d ON d.business_id=j.business_id AND d.job_id=j.id AND d.kind='invoice' WHERE j.business_id=? AND j.job_number=? AND d.document_number=? AND j.status NOT IN ('cancelled','deleted')",
              variables: [
                Variable(business),
                Variable(target.$1),
                Variable(target.$2),
              ],
            )
            .get();
        if (rows.length != 1) return;
        final job = rows.single.read<String>('job_id'),
            invoice = rows.single.read<String>('invoice_id');
        final applied = await db
            .customSelect(
              'SELECT 1 FROM owner_nov12_job_completion_v1 WHERE business_id=? AND job_id=?',
              variables: [Variable(business), Variable(job)],
            )
            .get();
        if (applied.isNotEmpty) return;
        final edits = await db
            .customSelect(
              "SELECT 1 FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type IN ('invoice_pending_payment_edit','invoice_tax_edit','document_edit')",
              variables: [Variable(business), Variable(invoice)],
            )
            .get();
        if (edits.isNotEmpty) return;
        final saved = await LocalDocumentDetailCache(
          database: db,
        ).loadReadOnly(business, invoice);
        if (saved == null || saved['id'] != invoice || saved['job_id'] != job)
          return;
        final detail = OfflineInvoicePaymentLedger.projectPendingPayments(
          saved,
          await OfflineInvoicePaymentLedger(
            database: db,
          ).pendingForInvoice(business, invoice),
        );
        final financial = DocumentPresentation(detail);
        if (!financial.paymentDetailsKnown ||
            !financial.fullyCovered ||
            financial.isVoid ||
            financial.totalCents != target.$3)
          return;
        await db.customStatement(
          'INSERT INTO owner_nov12_job_completion_v1 VALUES(?,?,?,?)',
          [
            business,
            job,
            invoice,
            jsonEncode({
              'owner_confirmed': '2026-11-12',
              'total_cents': financial.totalCents,
              'payments': detail['payments'],
            }),
          ],
        );
        if (!const {
          'completed',
          'closed',
        }.contains(rows.single.read<String>('status'))) {
          await OfflineJobAdminService(database: db).queueStatus(
            business,
            job,
            code: 'completed',
            name: 'Completed',
            colorHex: '#0A8F53',
            iconKey: 'task_alt',
            note:
                'Owner confirmed completed November 12; saved local payments verified. No payment changes.',
          );
        }
      });
    }
  }
}
