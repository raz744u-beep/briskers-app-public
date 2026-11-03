import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Computes number suggestions only from this device's local records.
/// Gaps are not reused: use the highest valid number plus one.
class LocalDocumentNumberSuggestions {
  LocalDocumentNumberSuggestions({BriskersLocalDatabase? database})
      : _db = database ?? localDatabase;
  final BriskersLocalDatabase _db;

  static int? _invoiceSequence(String? value) {
    final cleaned = value?.trim() ?? '';
    final match = RegExp(r'^(?:I-|MB-)?([0-9]+)$',
        caseSensitive: false).firstMatch(cleaned);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int? _jobSequence(String? value) {
    final cleaned = value?.trim() ?? '';
    final match = RegExp(r'^(?:J-)?([0-9]+)$',
        caseSensitive: false).firstMatch(cleaned);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<({String? invoice, String? job, String? latestInvoice,
      String? latestJob})> suggest(String businessId) async {
    final invoices = await _db.customSelect(
      """SELECT document_number FROM local_documents
         WHERE business_id=? AND kind='invoice'
           AND document_number IS NOT NULL""",
      variables:[Variable<String>(businessId)],
    ).get();
    final jobs = await _db.customSelect(
      """SELECT job_number FROM local_jobs WHERE business_id=?
         AND job_number IS NOT NULL""",
      variables:[Variable<String>(businessId)],
    ).get();
    int? largestInvoice;
    String? lastInvoice;
    for (final row in invoices) {
      final current=row.readNullable<String>('document_number');
      final parsed=_invoiceSequence(current);
      if (parsed != null && (largestInvoice == null || parsed > largestInvoice)) {
        largestInvoice=parsed;lastInvoice=current;
      }
    }
    int? largestJob;
    String? lastJob;
    for (final row in jobs) {
      final current=row.readNullable<String>('job_number');
      final parsed=_jobSequence(current);
      if (parsed != null && (largestJob == null || parsed > largestJob)) {
        largestJob=parsed;lastJob=current;
      }
    }
    // No numbers => ask Owner rather than guessing an initial sequence.
    return (
      invoice: largestInvoice == null ? null : '${largestInvoice + 1}',
      job: largestJob == null ? null : 'J-${largestJob + 1}',
      latestInvoice:lastInvoice,
      latestJob:lastJob,
    );
  }
}
