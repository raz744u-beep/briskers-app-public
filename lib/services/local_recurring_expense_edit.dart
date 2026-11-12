import '../core/supabase_config.dart';
import '../local/local_database_provider.dart';
import 'device_owner_authorization.dart';
import 'local_financial_cache.dart';
import 'offline_financial_write_service.dart';
import 'offline_recurring_repository.dart';
import 'recurring_financial_projection.dart';

/// Uses the existing expense editor and recurring ledger with one local commit.
/// Supabase supplies saved session identity only; no RPC is involved.
class LocalRecurringExpenseEdit {
  static Future<void> save(
    String business,
    String transaction,
    Map<String, dynamic> changes,
    List<Map<String, dynamic>> receipts, {
    Map<String, dynamic>? extraction,
  }) async {
    final grant = await DeviceOwnerAuthorization.instance.authority
        .authorizeLocal(business);
    void authorize() =>
        grant.assertValid(business, supabase.auth.currentUser?.id ?? '');
    bool allowed() {
      authorize();
      return true;
    }

    final repo = OfflineRecurringRepository(
      database: localDatabase,
      businessId: business,
      userId: grant.actorId,
      currentUserId: () => supabase.auth.currentUser?.id,
      canRead: allowed,
      canWrite: allowed,
      projectOccurrence: RecurringFinancialProjection(business).call,
    );
    final detail = await LocalFinancialCache().loadTransactionForEdit(
      business,
      transaction,
    );
    if (detail == null)
      throw StateError(
        'Saved recurring expense details are unavailable. No changes were made.',
      );
    await localDatabase.transaction(() async {
      await repo.adoptSavedExpense(detail);
      await repo.editSavedExpense(transaction, changes);
      await OfflineFinancialWriteService().attachRecurringReceipts(
        business,
        transaction,
        receipts: receipts,
        assertAuthorized: authorize,
        receiptExtraction: extraction,
      );
      authorize();
    });
  }
}
