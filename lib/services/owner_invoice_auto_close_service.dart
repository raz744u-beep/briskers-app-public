import '../core/connection_mode.dart';
import 'briskers_api.dart';
import 'invoice_finalization_guard.dart';
import 'local_document_repository.dart';
import 'verified_invoice_close_events.dart';

/// Safe owner closeout after either independent action: completion or
/// payment finalization. Does not receive or finalize money.
class OwnerInvoiceAutoCloseService {
  OwnerInvoiceAutoCloseService({
    BriskersApi? api,
    InvoiceFinalizationGuard? guard,
    LocalDocumentRepository? localDocuments,
  }) : _api = api ?? const BriskersApi(),
       _guard = guard ?? InvoiceFinalizationGuard(),
       _localDocuments = localDocuments ?? LocalDocumentRepository();

  final BriskersApi _api;
  final InvoiceFinalizationGuard _guard;
  final LocalDocumentRepository _localDocuments;

  Future<int> closeEligible({
    required String businessId,
    required String jobId,
    required bool isOwner,
  }) async {
    if (!isOwner ||
        BriskersConnectionModeController.instance.forceOffline ||
        jobId.isEmpty || jobId.startsWith('local-')) {
      return 0;
    }
    final job = await _api.jobDetail(businessId, jobId);
    if (job['status']?.toString().toLowerCase() != 'completed') {
      return 0;
    }
    final documents = await _api.jobDocuments(businessId, jobId);
    var closed = 0;
    for (final row in documents) {
      if (row['kind'] != 'invoice') {
        continue;
      }
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || id.startsWith('local-')) {
        continue;
      }
      // Each source is reloaded, not derived from list/cache status.
      final invoice = await _api.documentDetail(businessId, id);
      final status = invoice['status']?.toString().toLowerCase() ?? '';
      final display = invoice['display_status_code']
          ?.toString().toLowerCase() ?? '';
      if (invoice['job_id']?.toString() != jobId ||
          invoice['closed_at'] != null ||
          const {'closed','void','voided','cancelled','canceled','reopened'}
              .contains(status) ||
          const {'closed','void','reopened'}.contains(display)) {
        continue;
      }
      num? money(Object? value) {
        final n = value is num ? value : num.tryParse(value?.toString() ?? '');
        return n != null && n.isFinite ? n : null;
      }
      final total = money(invoice['total_amount']);
      final paid = money(invoice['paid_amount']);
      final pending = money(invoice['pending_payment']);
      if (total == null || paid == null || pending == null) {
        continue;
      }
      if (!InvoiceFinalizationGuard.canAutoClose(
        isOwner: isOwner,
        jobCompleted: true,
        invoiceTotal: total,
        finalizedPayments: paid,
        pendingPayments: pending,
        reopenedForCorrection: status == 'reopened' || display == 'reopened',
      )) {
        continue;
      }
      await _guard.run<void>(
        businessId: businessId,
        invoiceIds: [id],
        isOwner: isOwner,
        action: () => _api.closeInvoice(businessId, id),
      );
      // Only an acknowledged close RPC may mark the list Closed. Never do
      // so merely because the Job became Completed or a payment was queued.
      try {
        await _localDocuments.recordServerConfirmedClosed(businessId, id);
      } catch (_) {
        // The verified server closure still deserves a retained UI update.
        // Another index refresh can repair its read-only local projection.
      }
      VerifiedInvoiceCloseEvents.serverConfirmed(VerifiedInvoiceClosed(
        businessId: businessId,
        invoiceId: id,
      ));
      closed++;
    }
    return closed;
  }
}
