import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_customer_vehicle_identity.dart';

/// Read-only identity evidence for an exact saved document. Old snapshots do
/// not always have entries in the later customer/vehicle alias table.
class LocalDocumentPartyIdentity {
  const LocalDocumentPartyIdentity(this.db);
  final BriskersLocalDatabase db;

  Future<Map<String, dynamic>> project(String business, Map<String, dynamic> saved) =>
      db.transaction(() => _project(business, saved));

  Future<Map<String, dynamic>> _project(String business, Map<String, dynamic> saved) async {
    final result = Map<String, dynamic>.from(saved);
    final identities = LocalCustomerVehicleIdentity(db);
    for (final field in ['customer_id','vehicle_id']) {
      result[field] = await identities.resolve(business,saved[field]?.toString());
    }
    final id = saved['id']?.toString() ?? '';
    final row = await db.customSelect('''
      SELECT d.customer_id,d.job_id,d.kind,j.customer_id AS job_customer_id,
             j.vehicle_id,v.id AS saved_vehicle_id
      FROM local_documents d
      LEFT JOIN local_jobs j ON j.business_id=d.business_id AND j.id=d.job_id
      LEFT JOIN local_vehicles v ON v.business_id=j.business_id AND v.id=j.vehicle_id
      WHERE d.business_id=? AND d.id=?
    ''',variables:[Variable(business),Variable(id)]).getSingleOrNull();
    if (row == null || row.data['kind'] != saved['kind']) return result;
    final customer = row.readNullable<String>('customer_id') ?? '';
    final job = row.readNullable<String>('job_id') ?? '';
    final vehicle = row.readNullable<String>('vehicle_id') ?? '';
    final originalCustomer = result['customer_id']?.toString() ?? '';
    final sameJob = job.isNotEmpty && saved['job_id']?.toString() == job;
    final coherentJob = sameJob && customer.isNotEmpty && customer == row.data['job_customer_id'];
    if (originalCustomer.isNotEmpty && !originalCustomer.startsWith('local-customer-') &&
        customer.isNotEmpty && originalCustomer != customer) {
      result['_customer_identity_conflict'] = true;
      return result;
    }
    // The document's stored customer foreign key is direct evidence. Never
    // replace a different real customer ID from a conflicting saved snapshot.
    if (originalCustomer.isEmpty || originalCustomer.startsWith('local-customer-')) {
      final exists = await db.customSelect(
        'SELECT 1 FROM local_customers WHERE business_id=? AND id=?',
        variables:[Variable(business),Variable(customer)],
      ).getSingleOrNull();
      final originalExists = originalCustomer.isEmpty ? null : await db.customSelect(
        'SELECT 1 FROM local_customers WHERE business_id=? AND id=?',
        variables:[Variable(business),Variable(originalCustomer)],
      ).getSingleOrNull();
      if (originalExists != null && originalCustomer != customer) {
        result['_customer_identity_conflict'] = true;
        return result;
      }
      if (exists != null && (job.isEmpty || coherentJob)) {
        result['customer_id'] = customer;
        result['_customer_identity_source'] = 'document_index';
      }
    }
    final originalVehicle = result['vehicle_id']?.toString() ?? '';
    if (originalVehicle.isNotEmpty && !originalVehicle.startsWith('local-vehicle-')) return result;
    final knownOriginal = await db.customSelect(
      'SELECT 1 FROM local_vehicles WHERE business_id=? AND id=?',
      variables:[Variable(business),Variable(originalVehicle)],
    ).getSingleOrNull();
    if (knownOriginal != null) return result;
    if (originalVehicle.isNotEmpty) result['_vehicle_identity_unresolved'] = true;
    if (!coherentJob || result['customer_id'] != customer ||
        vehicle.isEmpty || row.data['saved_vehicle_id'] == null) {
      return result;
    }
    final relationship = await db.customSelect(
      'SELECT 1 FROM local_customer_vehicles WHERE business_id=? AND customer_id=? AND vehicle_id=?',
      variables:[Variable(business),Variable(customer),Variable(vehicle)],
    ).getSingleOrNull();
    if (relationship == null) return result;
    if (originalVehicle.isEmpty) {
      result['vehicle_id'] = vehicle;
      result['_vehicle_identity_source'] = 'linked_job';
      return result;
    }
    // An unresolved temporary vehicle requires the original creation, not
    // merely a matching label or a Job whose vehicle could since have changed.
    final creates = await db.customSelect(
      "SELECT payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? AND entity_type='document_draft_create'",
      variables:[Variable(business),Variable(id)],
    ).get();
    if (creates.length != 1 || !id.startsWith('local-invoice-')) return result;
    Object? decoded;
    try { decoded = jsonDecode(creates.single.read<String>('payload_json')); }
    on FormatException { return result; }
    if (decoded is! Map || decoded['kind'] != 'invoice' ||
        decoded['operation_id'] != id.substring('local-invoice-'.length) ||
        decoded['provisional_job_id'] != job) {
      return result;
    }
    final createdCustomer = await identities.resolve(business,decoded['customer_id']?.toString());
    final createdVehicle = await identities.resolve(business,decoded['vehicle_id']?.toString());
    if (createdCustomer != customer || createdVehicle != vehicle) return result;
    result['vehicle_id'] = vehicle;
    result['_vehicle_identity_unresolved'] = false;
    result['_vehicle_identity_source'] = 'original_creation';
    return result;
  }
}
