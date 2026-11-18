import 'package:drift/drift.dart';

import '../core/document_search.dart';
import '../local/briskers_local_database.dart';
import 'local_number_evidence.dart';

/// A server counter cannot see numbered work still owned by this device.
/// Number-preserving reconciliation is separate from ordinary server creation.
class LocalServerInvoiceAllocationGuard {
  static Future<void> assertSafe(BriskersLocalDatabase db, String business) async {
    final rows = await db.customSelect(
      "SELECT id,document_number,sync_state FROM local_documents WHERE business_id=? AND kind='invoice'",
      variables: [Variable(business)],
    ).get();
    final indexed = {for (final row in rows) row.read<String>('id'): row};
    void stop() => throw StateError(
      'This phone has invoice numbers that the server has not reconciled. '
      'Use Force Offline to create the invoice safely with your saved shop records.',
    );
    for (final row in rows) {
      if (normalizedDocumentNumber(row.data['document_number']) != null &&
          row.read<String>('sync_state') != 'synced') {
        stop();
      }
    }
    for (final detail in await LocalNumberEvidence.documents(db, business)) {
      if (detail['kind'] != 'invoice') continue;
      final number = normalizedDocumentNumber(detail['document_number']);
      if (number == null) continue;
      final row = indexed[detail['id']];
      if (row == null || row.read<String>('sync_state') != 'synced' ||
          normalizedDocumentNumber(row.data['document_number']) != number) {
        stop();
      }
    }
  }
}
