import 'local_document_identity.dart';
import 'local_estimate_conversion.dart';
import 'local_document_repository.dart';
import 'package:drift/drift.dart';

import '../core/document_presentation.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';
import 'local_job_retirement.dart';
import 'offline_invoice_payment_ledger.dart';
import 'local_customer_vehicle_identity.dart';
import 'local_invoice_closure.dart';

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
    final canonical = await LocalDocumentIdentity(_database).canonicalId(businessId, id);
    if (canonical != id) {
      final originals = await LocalDocumentRepository(database: _database)
          .listByKind(businessId, kind: 'invoice');
      for (final original in originals) {
        if (original['id'] != canonical) continue;
        // Index-only zero placeholders must not override saved receipt detail.
        final identity = {...original}..remove('paid_amount')..remove('pending_payment');
        return hydrate(businessId, identity);
      }
      return const {};
    }

    if (await _blocked(businessId, index)) return const {};
    final cached =
        await _cache.loadReadOnly(businessId, id) ?? const <String, dynamic>{};
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
    // A saved offline snapshot can retain temporary customer/vehicle IDs after
    // the index was reconciled. Project only the exact, shop-scoped aliases.
    final identities = LocalCustomerVehicleIdentity(_database);
    for (final field in ['customer_id', 'vehicle_id']) {
      final value = document[field]?.toString();
      if (value != null && value.isNotEmpty) {
        document[field] = await identities.resolve(businessId, value);
      }
    }
    if ((document['vehicle_id']?.toString().isEmpty ?? true) &&
        document['job_id'] == index['job_id']) {
      document['vehicle_id'] = index['vehicle_id'];
    }
    if (document['kind'] == 'invoice') {
      // A summary may itself be hydrated again for an expanded history row.
      // Retain already-posted local receipts so the queue recognizes their IDs.
      if (document['payments'] is List) {
        document['payments'] = [
          for (final payment in (document['payments'] as List).whereType<Map>())
            if (payment['state'] == 'posted' && payment['_finalized_locally'] == true)
              {...payment, '_local_pending_payment': false}
            else payment,
        ];
      }
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
      // Queued receipts may already be finalized locally. Sync state cannot
      // turn that saved accounting decision back into "pending finalization".
      document = await LocalInvoiceClosureStore(_database)
          .projectFinalized(businessId, document);
    }
    if (document['kind'] == 'estimate') {
      document = await LocalEstimateConversion(_database).project(businessId, document);
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
    await LocalDocumentIdentity(_database).prepare();
    final rows = await _database
        .customSelect(
          'SELECT d.*, j.vehicle_id, j.vehicle_label, j.job_number '
          'FROM local_documents d LEFT JOIN local_jobs j '
          'ON j.business_id=d.business_id AND j.id=d.job_id '
          'WHERE d.business_id=? AND (d.customer_id=? OR EXISTS('
          'SELECT 1 FROM local_document_identity_aliases a JOIN local_documents remote '
          'ON remote.business_id=a.business_id AND remote.id=a.alias_id '
          'WHERE a.business_id=d.business_id AND a.canonical_id=d.id AND remote.customer_id=?)) '
          "AND lower(COALESCE(d.status,''))<>'void'",
          variables: [
            Variable<String>(businessId),
            Variable<String>(customerId),
            Variable<String>(customerId),
          ],
        )
        .get();
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final row in rows) {
      final index = <String, dynamic>{
        'id': row.read<String>('id'),
        'kind': row.read<String>('kind'),
        'job_id': row.readNullable<String>('job_id'),
        'customer_id': row.readNullable<String>('customer_id'),
        'document_date': row.readNullable<String>('document_date'),
        'vehicle_id': row.readNullable<String>('vehicle_id'),
        'vehicle': row.readNullable<String>('vehicle_label'),
        'job_number': row.readNullable<String>('job_number'),
        'status': row.readNullable<String>('status'),
        'display_status_code': row.readNullable<String>('display_status_code'),
        'document_number': row.readNullable<String>('document_number'),
        'total_amount': row.read<double>('total'),
        'row_version': row.readNullable<int>('row_version'),
        'closed_at': row.data['closed_at'],
        'converted': row.read<int>('converted') == 1,
      };
      final document = await hydrate(businessId, index);
      if (document.isEmpty || !seen.add('${document['id']}')) continue;
      if (!includeClosed && DocumentPresentation(document).isClosed) continue;
      result.add(document);
    }
    return result;
  }
}
