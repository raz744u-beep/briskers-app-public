import 'package:drift/drift.dart' show Variable;

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Read-only exact-ID check for suspicious invoice/Job references.
///
/// This service deliberately never "repairs" links by a visible number,
/// because imported and local numbers can collide. Owner must first compare
/// the full document graph and actual payment evidence.
class LocalInvoiceLinkAudit {
  LocalInvoiceLinkAudit({BriskersLocalDatabase? database})
      : _database = database ?? localDatabase;

  final BriskersLocalDatabase _database;

  Future<Map<String, dynamic>> inspect({
    required String businessId,
    required String jobNumber,
    required String invoiceNumber,
  }) async {
    if (businessId.trim().isEmpty ||
        jobNumber.trim().isEmpty ||
        invoiceNumber.trim().isEmpty) {
      throw ArgumentError('Business, Job and invoice numbers are required.');
    }

    // IDs, not numbers, determine authoritative local relationships.
    // Bind every value; a query never crosses a shop's business scope.
    final jobs = await _database.customSelect(
      '''SELECT id,job_number,customer_id,customer_name
         FROM local_jobs
         WHERE business_id=? AND lower(trim(job_number))=lower(trim(?))
         ORDER BY id''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobNumber),
      ],
    ).get();

    final documents = await _database.customSelect(
      '''SELECT d.id,d.job_id,d.document_number,d.kind,d.customer_id,
                j.job_number AS linked_job_number,
                j.customer_id AS linked_job_customer_id
         FROM local_documents d
         LEFT JOIN local_jobs j
           ON j.business_id=d.business_id AND j.id=d.job_id
         WHERE d.business_id=? AND lower(trim(d.document_number))=lower(trim(?))
           AND d.kind='invoice'
         ORDER BY d.id''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(invoiceNumber),
      ],
    ).get();

    final targetIds = jobs.map((row) => row.read<String>('id')).toSet();
    final references = [
      for (final doc in documents)
        <String, dynamic>{
          'document_id': doc.read<String>('id'),
          'invoice_number': doc.readNullable<String>('document_number'),
          'job_id': doc.readNullable<String>('job_id'),
          'linked_job_number': doc.readNullable<String>('linked_job_number'),
          'customer_id': doc.readNullable<String>('customer_id'),
          'linked_job_customer_id':
              doc.readNullable<String>('linked_job_customer_id'),
          'matches_target_job':
              targetIds.contains(doc.readNullable<String>('job_id')),
        },
    ];

    final unmatched = references.where((row) =>
        row['matches_target_job'] != true).toList();

    return <String, dynamic>{
      'job_number': jobNumber,
      'invoice_number': invoiceNumber,
      'target_jobs': [
        for (final row in jobs)
          <String, dynamic>{
            'job_id': row.read<String>('id'),
            'job_number': row.readNullable<String>('job_number'),
            'customer_id': row.readNullable<String>('customer_id'),
            'customer_name': row.readNullable<String>('customer_name'),
          },
      ],
      'references': references,
      'ambiguous': jobs.length != 1 || references.length != 1 ||
          unmatched.isNotEmpty,
      'has_duplicate_invoice_number': references.length > 1,
      'read_only': true,
    };
  }
}
