import 'package:drift/drift.dart';

import '../core/briskers_i18n.dart';
import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Fail-closed, read-only preflight for payment finalization and invoice close.
/// A receipt is unresolved until its durable queue row has actually retired;
/// status, acknowledgment IDs and cached monetary totals cannot bypass it.
class InvoiceFinalizationGuard {
  InvoiceFinalizationGuard({
    BriskersLocalDatabase? database,
    bool Function()? forceOffline,
  }) : _database = database ?? localDatabase,
       _forceOffline =
           forceOffline ??
           (() => BriskersConnectionModeController.instance.forceOffline);

  final BriskersLocalDatabase _database;
  final bool Function() _forceOffline;

  void _validate(String businessId, Set<String> ids, bool isOwner) {
    if (!isOwner) throw StateError(tr('invoiceFinalizationOwnerOnly'));
    if (_forceOffline()) throw StateError(tr('invoiceFinalizationOnlineOnly'));
    if (businessId.trim().isEmpty ||
        businessId != businessId.trim() ||
        ids.isEmpty ||
        ids.any(
          (id) =>
              id.trim().isEmpty ||
              id != id.trim() ||
              id.toLowerCase().startsWith('local-'),
        )) {
      throw StateError(tr('invoiceFinalizationSyncFirst'));
    }
  }

  Future<void> check({
    required String businessId,
    required Iterable<String> invoiceIds,
    required bool isOwner,
  }) async {
    final ids = invoiceIds.toSet();
    _validate(businessId, ids, isOwner);
    // Deliberately no state filter and no JSON parsing. Even an unexpected
    // state, corrupted payload, or acknowledged-but-unretired receipt blocks
    // finalization; this guard never changes or removes financial records.
    final queued = await _database
        .customSelect(
          "SELECT entity_id FROM sync_outbox WHERE business_id=? "
          "AND entity_type='invoice_payment_received'",
          variables: [Variable<String>(businessId)],
        )
        .get();
    _validate(businessId, ids, isOwner);
    if (queued.any((row) => ids.contains(row.read<String>('entity_id')))) {
      throw StateError(tr('invoiceFinalizationReceiptsPending'));
    }
  }

  /// Owner-only eligibility preflight for automatic close. This is strictly
  /// a client-side convenience check: the server must independently verify
  /// authoritative job completion, all posted payments, and zero balance
  /// inside the same protected close operation.
  static bool canAutoClose({
    required bool isOwner,
    required bool jobCompleted,
    required num invoiceTotal,
    required num finalizedPayments,
    required num pendingPayments,
    required bool reopenedForCorrection,
  }) {
    if (!isOwner || !jobCompleted || reopenedForCorrection) {
      return false;
    }
    if (!invoiceTotal.isFinite || !finalizedPayments.isFinite ||
        !pendingPayments.isFinite) {
      return false;
    }
    if (invoiceTotal < 0 || finalizedPayments < 0 || pendingPayments < 0) {
      return false;
    }
    // Prevent closing with unresolved receipts or overpayments.
    return pendingPayments.abs() < 0.005 &&
        (invoiceTotal - finalizedPayments).abs() < 0.005;
  }

  Future<T> run<T>({
    required String businessId,
    required Iterable<String> invoiceIds,
    required bool isOwner,
    required Future<T> Function() action,
  }) async {
    final ids = invoiceIds.toSet();
    await check(businessId: businessId, invoiceIds: ids, isOwner: isOwner);
    // The mode may change while SQLite is awaited, or while control returns
    // from check. No asynchronous work belongs between this check and the RPC.
    _validate(businessId, ids, isOwner);
    return action();
  }
}
