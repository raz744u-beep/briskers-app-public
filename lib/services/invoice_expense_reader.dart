import 'local_financial_cache.dart';

/// Reads saved invoice/job expenses before considering a network fallback.
/// Local Database Sync remains responsible for refreshing saved history.
class InvoiceExpenseReader {
  InvoiceExpenseReader({LocalFinancialCache? cache})
      : _cache = cache ?? LocalFinancialCache();
  final LocalFinancialCache _cache;

  Future<List<Map<String, dynamic>>?> load({
    required String businessId,
    required String documentId,
    String? jobId,
    required bool offline,
    required Future<List<Map<String, dynamic>>> Function() fetchRemote,
  }) async {
    final local = await _cache.loadLinkedExpenses(
      businessId,
      documentId: documentId,
      relatedJobId: jobId == null || jobId.isEmpty ? null : jobId,
    );
    if (local != null || offline) return local;
    return fetchRemote();
  }
}
