import 'package:drift/drift.dart';

import '../core/document_presentation.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';
import 'local_job_retirement.dart';
import 'offline_invoice_payment_ledger.dart';

/// Hydrates customer-facing summaries from saved authoritative payment detail
/// and the durable, identity-deduplicated receipt queue. No financial writes.
class CustomerDocumentSummaryService {
  CustomerDocumentSummaryService({
    BriskersLocalDatabase? database,
    LocalDocumentDetailCache? cache,
  }) : _database = database ?? localDatabase,
       _cache = cache ?? LocalDocumentDetailCache(database: database);

  final BriskersLocalDatabase _database;
  final LocalDocumentDetailCache _cache;

  Future<bool> _blocked(String businessId, Map<String, dynamic> index) async {
    final id = index['id']?.toString() ?? '';
    if (await LocalJobRetirement.isDocumentBlocked(_database, businessId, id)) {
      return true;
    }
    final jobId = index['job_id']?.toString() ?? '';
    return index['kind'] == 'invoice' &&
        jobId.isNotEmpty &&
        await LocalJobRetirement.isJobBlocked(_database, businessId, jobId);
  }

  Future<Map<String, dynamic>> hydrate(
    String businessId,
    Map<String, dynamic> index,
  ) async {
    final id = index['id']?.toString() ?? '';
    if (id.isEmpty) return Map.from(index);
    if (await _blocked(businessId, index)) return const {};
    final cached =
        await _cache.load(businessId, id) ?? const <String, dynamic>{};
    final indexVersion = num.tryParse(index['row_version']?.toString() ?? '');
    final detailVersion = num.tryParse(cached['row_version']?.toString() ?? '');
    final cacheValid =
        cached.isNotEmpty &&
        (cached['id'] == null || cached['id']?.toString() == id) &&
        (cached['kind'] == null || cached['kind'] == index['kind']);
    final cacheCurrent =
        cacheValid &&
        (indexVersion == null ||
            detailVersion == null ||
            detailVersion >= indexVersion ||
            cached['sync_state'] == 'pending');
    // Keep index closure evidence even if an older full detail is all we have.
    var document = <String, dynamic>{
      ...index,
      if (cacheCurrent) ...cached,
      'id': id,
      'kind': index['kind'],
      if (index['closed_at'] != null) 'closed_at': index['closed_at'],
    };
    // Fresh API aggregates take precedence over cached detail, when present.
    if (index.containsKey('paid_amount') &&
        index.containsKey('pending_payment')) {
      document.addAll(index);
    }
    if (document['kind'] == 'invoice') {
      final queued = await OfflineInvoicePaymentLedger(database: _database)
          .pendingForInvoice(businessId, id);
      // Missing pending data must remain unknown rather than becoming a
      // fabricated zero through the queue projection's numeric default.
      final pendingKnown = document['pending_payment'] != null;
      document = OfflineInvoicePaymentLedger.projectPendingPayments(
        document,
        queued,
      );
      if (!pendingKnown) document.remove('pending_payment');
    }
    if (document['kind'] == 'estimate') {
      final invoiceId = document['converted_invoice_id']?.toString() ?? '';
      final retiredConversion = invoiceId.isNotEmpty
          ? await LocalJobRetirement.isDocumentBlocked(
              _database,
              businessId,
              invoiceId,
            )
          : cacheCurrent && cached['_retired_conversion'] == true;
      if (retiredConversion) {
        document['converted'] = false;
        document['converted_invoice_id'] = null;
        document['converted_invoice_number'] = null;
        document['converted_invoice_date'] = null;
      }
    }
    if (await _blocked(businessId, document)) return const {};
    return document;
  }

  Future<List<Map<String, dynamic>>> forCustomer(
    String businessId,
    String customerId, {
    bool includeClosed = false,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT * FROM local_documents WHERE business_id=? AND customer_id=? '
          "AND lower(COALESCE(status,''))<>'void'",
          variables: [
            Variable<String>(businessId),
            Variable<String>(customerId),
          ],
        )
        .get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final index = <String, dynamic>{
        'id': row.read<String>('id'),
        'kind': row.read<String>('kind'),
        'job_id': row.readNullable<String>('job_id'),
        'status': row.readNullable<String>('status'),
        'display_status_code': row.readNullable<String>('display_status_code'),
        'document_number': row.readNullable<String>('document_number'),
        'total_amount': row.read<double>('total'),
        'row_version': row.readNullable<int>('row_version'),
        'closed_at': row.data['closed_at'],
        'converted': row.read<int>('converted') == 1,
      };
      final document = await hydrate(businessId, index);
      if (document.isEmpty) continue;
      if (!includeClosed && DocumentPresentation(document).isClosed) continue;
      result.add(document);
    }
    return result;
  }
}
