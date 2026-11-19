import 'package:drift/drift.dart' show Variable;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String,dynamic> _creationIdentity(String raw) {
    try {
      final value=jsonDecode(raw);
      if(value is Map) {
        return {for(final key in ['operation_id','kind','customer_id','vehicle_id','provisional_job_id'])
          if(value.containsKey(key)) key:value[key]};
      }
    } on FormatException { return {'error':'Invalid creation JSON'}; }
    return {};
  }

  Future<Map<String, dynamic>> inspect({
    required String businessId,
    String jobNumber = '',
    required String invoiceNumber,
  }) async {
    if (businessId.trim().isEmpty ||
        invoiceNumber.trim().isEmpty) {
      throw ArgumentError('Business and invoice numbers are required.');
    }

    // IDs, not numbers, determine authoritative local relationships.
    // Bind every value; a query never crosses a shop's business scope.
    final jobs = await _database.customSelect(
      '''SELECT id,job_number,customer_id,customer_name
         FROM local_jobs
         WHERE business_id=? AND (lower(trim(job_number))=lower(trim(?))
           OR (?='' AND id IN (SELECT job_id FROM local_documents
             WHERE business_id=? AND kind='invoice'
               AND lower(trim(document_number))=lower(trim(?)))))
         ORDER BY id''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(jobNumber),
        Variable<String>(jobNumber.trim()),
        Variable<String>(businessId),
        Variable<String>(invoiceNumber),
      ],
    ).get();

    final documents = await _database.customSelect(
      '''SELECT d.id,d.job_id,d.document_number,d.kind,d.customer_id,
                d.document_date,d.total,d.status,d.closed_at,d.sync_state,
                c.display_name AS customer_name,
                j.job_number AS linked_job_number,
                j.customer_id AS linked_job_customer_id,
                j.vehicle_id AS linked_job_vehicle_id,
                v.id AS existing_vehicle_id,v.vin AS linked_vehicle_vin
         FROM local_documents d
         LEFT JOIN local_jobs j
           ON j.business_id=d.business_id AND j.id=d.job_id
         LEFT JOIN local_vehicles v
           ON v.business_id=j.business_id AND v.id=j.vehicle_id
         LEFT JOIN local_customers c
           ON c.business_id=d.business_id AND c.id=d.customer_id
         WHERE d.business_id=? AND lower(trim(d.document_number))=lower(trim(?))
           AND d.kind='invoice'
         ORDER BY d.id''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(invoiceNumber),
      ],
    ).get();

    final targetIds = jobs.map((row) => row.read<String>('id')).toSet();
    final targetDocuments = await _database.customSelect(
      '''SELECT d.id,d.job_id,d.document_number,d.customer_id,d.status
         FROM local_documents d
         JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id
         WHERE d.business_id=? AND d.kind='invoice'
           AND (lower(trim(j.job_number))=lower(trim(?))
             OR (?='' AND j.id IN (SELECT job_id FROM local_documents
               WHERE business_id=? AND kind='invoice'
                 AND lower(trim(document_number))=lower(trim(?)))))
         ORDER BY d.id''',
      variables: [Variable<String>(businessId), Variable<String>(jobNumber),
        Variable<String>(jobNumber.trim()), Variable<String>(businessId),
        Variable<String>(invoiceNumber)],
    ).get();
    final references = [
      for (final doc in documents)
        <String, dynamic>{
          'document_id': doc.read<String>('id'),
          'invoice_number': doc.readNullable<String>('document_number'),
          'job_id': doc.readNullable<String>('job_id'),
          'linked_job_number': doc.readNullable<String>('linked_job_number'),
          'customer_id': doc.readNullable<String>('customer_id'),
          'customer_name': doc.readNullable<String>('customer_name'),
          'document_date': doc.readNullable<String>('document_date'),
          'total': doc.read<double>('total'),
          'status': doc.readNullable<String>('status'),
          'closed_at': doc.data['closed_at'],
          'sync_state': doc.read<String>('sync_state'),
          'linked_job_customer_id':
              doc.readNullable<String>('linked_job_customer_id'),
          'party_identity_evidence': {
            'customer_record_found': doc.readNullable<String>('customer_name') != null,
            'job_customer_id': doc.readNullable<String>('linked_job_customer_id'),
            'job_vehicle_id': doc.readNullable<String>('linked_job_vehicle_id'),
            'vehicle_record_found': doc.readNullable<String>('existing_vehicle_id') != null,
            'job_vehicle_vin': doc.readNullable<String>('linked_vehicle_vin'),
          },
          'matches_target_job':
              targetIds.contains(doc.readNullable<String>('job_id')),
          'customer_identity_conflict':
              (doc.readNullable<String>('customer_id') ?? '').isNotEmpty &&
              (doc.readNullable<String>('linked_job_customer_id') ?? '').isNotEmpty &&
              doc.readNullable<String>('customer_id') !=
                  doc.readNullable<String>('linked_job_customer_id'),
        },
    ];

    // Read only the selected invoices' raw snapshots. Calling the ordinary
    // detail cache would project tasks and migrate caches during inspection.
    final tables = (await _database.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
      "('local_document_details','recovery_document_cache','local_invoice_number_corrections','local_customer_vehicle_create_ids')",
    ).get()).map((r) => r.read<String>('name')).toSet();
    final prefs = await SharedPreferences.getInstance();
    for (final reference in references) {
      final id = reference['document_id'] as String;
      final key = 'briskers_document_detail_${businessId}_$id';
      String? raw;
      if (tables.contains('recovery_document_cache')) {
        final row = await _database.customSelect(
          'SELECT payload_json FROM recovery_document_cache WHERE business_id=? AND document_id=?',
          variables: [Variable(businessId), Variable(id)],
        ).getSingleOrNull();
        raw = row?.readNullable<String>('payload_json');
      }
      if (raw == null && tables.contains('local_document_details')) {
        final row = await _database.customSelect(
          'SELECT payload_json FROM local_document_details WHERE cache_key=?',
          variables: [Variable(key)],
        ).getSingleOrNull();
        raw = row?.readNullable<String>('payload_json');
      }
      raw ??= prefs.getString(key);
      Object? decoded;
      try { decoded = raw == null ? null : jsonDecode(raw); }
      on FormatException { reference['snapshot_error'] = 'Invalid saved JSON'; }
      reference['snapshot_found'] = decoded is Map;
      final evidence = reference['party_identity_evidence'] as Map<String,dynamic>;
      final creates = await _database.customSelect(
        "SELECT payload_json,attempt_count,state FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type='document_draft_create'",
        variables:[Variable(businessId),Variable(id)],
      ).get();
      evidence['creation_records'] = [for (final row in creates) {
        'state':row.data['state'],'attempt_count':row.data['attempt_count'],
        'saved_identity': _creationIdentity(row.read<String>('payload_json')),
      }];
      if (decoded is Map && tables.contains('local_customer_vehicle_create_ids')) {
        final aliases = await _database.customSelect(
          'SELECT local_id,server_id FROM local_customer_vehicle_create_ids WHERE business_id=? AND local_id IN (?,?)',
          variables:[Variable(businessId),Variable(decoded['customer_id']?.toString() ?? ''),
            Variable(decoded['vehicle_id']?.toString() ?? '')],
        ).get();
        evidence['saved_aliases'] = [for (final row in aliases) row.data];
      }

      if (tables.contains('local_invoice_number_corrections')) {
        final correction = await _database.customSelect(
          'SELECT old_invoice_number,new_invoice_number,old_job_number,new_job_number,kept_invoice_id,created_at '
          'FROM local_invoice_number_corrections WHERE business_id=? AND invoice_id=?',
          variables:[Variable(businessId),Variable(id)],
        ).getSingleOrNull();
        if (correction != null) reference['number_correction'] = correction.data;
      }
      if (decoded is Map) {
        reference['saved'] = {
          for (final field in ['id','document_number','customer_id','customer_name',
            'job_id','job_number','vehicle_id','vehicle','vehicle_vin','vin','document_date','status','closed_at',
            'total_amount','paid_amount','pending_payment','_server_document_id'])
            if (decoded.containsKey(field)) field: decoded[field],
        };
      }
    }

    final unmatched = references.where((row) =>
        row['matches_target_job'] != true ||
        row['customer_identity_conflict'] == true).toList();

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
      'target_job_invoices': [
        for (final row in targetDocuments) {
          'document_id': row.read<String>('id'),
          'job_id': row.readNullable<String>('job_id'),
          'invoice_number': row.readNullable<String>('document_number'),
          'customer_id': row.readNullable<String>('customer_id'),
          'status': row.readNullable<String>('status'),
        },
      ],
      'ambiguous': jobs.length != 1 || references.length != 1 ||
          unmatched.isNotEmpty,
      'has_duplicate_invoice_number': references.length > 1,
      'read_only': true,
    };
  }
}
