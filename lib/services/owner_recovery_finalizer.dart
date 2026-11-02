import 'dart:convert';
import 'package:drift/drift.dart';
import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_document_detail_cache.dart';
import 'local_job_retirement.dart';
import 'offline_invoice_recovery_proof.dart';
import 'owner_recovery_server_lookup.dart';
import 'recovery_commit_store.dart';

/// Adopts only an already-uploaded, quarantined four-operation recovery chain.
/// No server mutations, retry uploads, or preference writes occur here.
class OwnerRecoveryFinalizer {
  OwnerRecoveryFinalizer({
    BriskersLocalDatabase? database,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? lookup,
  }) : _db = database ?? localDatabase,
       _lookup = lookup ?? OwnerRecoveryServerLookup().fetch;
  final BriskersLocalDatabase _db;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) _lookup;

  static const _holds = {
    'customer_create': 'Owner local recovery is authoritative; sync disabled',
    'vehicle_create': 'Owner local recovery is authoritative; sync disabled',
    'document_draft_create':
        'Owner assigned authoritative local number; sync disabled',
    'invoice_payment_received':
        'Owner recovery payment preserved; sync disabled',
  };

  static int _cents(Object? value) {
    final n = num.tryParse(value?.toString() ?? '');
    if (n == null || !n.isFinite) throw StateError('Invalid recovery amount.');
    return (n * 100).round();
  }

  static String _text(Object? value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) throw StateError('Missing recovery identity.');
    return s;
  }

  Future<List<QueryRow>> _rows(String sql, List<String> args) => _db
      .customSelect(sql, variables: args.map(Variable<String>.new).toList())
      .get();

  Future<Map<String, dynamic>> _local(String b, String id) async {
    final docs = await _rows(
      '''SELECT d.*,j.vehicle_id,j.job_number,
      j.sync_state AS job_sync_state FROM local_documents d JOIN local_jobs j
      ON j.business_id=d.business_id AND j.id=d.job_id
      WHERE d.business_id=? AND d.id=? AND d.kind='invoice' ''',
      [b, id],
    );
    if (docs.length != 1) {
      throw StateError('Original local invoice is missing.');
    }
    final d = docs.single.data;
    if (d['sync_state'] != 'pending' || d['job_sync_state'] != 'pending') {
      throw StateError('Original recovery records have changed.');
    }
    final customer = _text(d['customer_id']), vehicle = _text(d['vehicle_id']);
    final expected = {
      'customer_create': customer,
      'vehicle_create': vehicle,
      'document_draft_create': id,
      'invoice_payment_received': id,
    };
    for (final entry in {
      'local_customers': customer,
      'local_vehicles': vehicle,
    }.entries) {
      final source = await _rows(
        'SELECT sync_state FROM ${entry.key} WHERE business_id=? AND id=?',
        [b, entry.value],
      );
      if (source.length != 1 || source.single.data['sync_state'] != 'pending') {
        throw StateError('Original customer or vehicle is missing or changed.');
      }
    }
    final all = await _rows(
      'SELECT * FROM sync_outbox WHERE business_id=? ORDER BY id',
      [b],
    );
    final ops = <String, Map<String, dynamic>>{};
    final visits = await _rows(
      'SELECT * FROM local_job_visits WHERE business_id=? AND job_id=?',
      [b, _text(d['job_id'])],
    );
    if (visits.length != 1 ||
        visits.single.data['visit_number'] != 1 ||
        visits.single.data['closed_at'] != null) {
      throw StateError(
        'Original initial visit is missing or has additional work to review.',
      );
    }
    final ids = {
      id,
      customer,
      vehicle,
      _text(d['job_id']),
      _text(visits.single.data['id']),
    };
    for (final entry in expected.entries) {
      final matches = all
          .where(
            (r) =>
                r.data['entity_type'] == entry.key &&
                r.data['entity_id'] == entry.value,
          )
          .toList();
      if (matches.length != 1 ||
          matches.single.data['state'] != 'conflict' ||
          matches.single.data['last_error'] != _holds[entry.key]) {
        throw StateError('Original ${entry.key} is not uniquely quarantined.');
      }
      ops[entry.key] = matches.single.data;
    }
    for (final row in all) {
      if (ops.values.any((o) => o['id'] == row.data['id'])) continue;
      if (![
        'pending',
        'inflight',
        'conflict',
        'failed',
      ].contains(row.data['state'])) {
        continue;
      }
      final raw = row.read<String>('payload_json');
      if (ids.contains(row.data['entity_id']) ||
          ids.any((id) => raw.contains(id))) {
        throw StateError(
          'Related unsynchronized edits require review before recovery.',
        );
      }
    }
    final snapshot = await LocalDocumentDetailCache(database: _db).load(b, id);
    if (snapshot == null ||
        snapshot['id'] != id ||
        snapshot['job_id'] != d['job_id'] ||
        snapshot['customer_id'] != customer ||
        snapshot['vehicle_id'] != vehicle ||
        _cents(snapshot['total_amount']) != _cents(d['total'])) {
      throw StateError('Original invoice snapshot is incomplete or changed.');
    }
    return {
      'document': d,
      'operations': ops,
      'snapshot': snapshot,
      'visit': visits.single.data,
    };
  }

  Map<String, dynamic> _payload(Map<String, dynamic> state, String kind) =>
      Map<String, dynamic>.from(
        jsonDecode(
              ((state['operations'] as Map)[kind] as Map)['payload_json']
                  as String,
            )
            as Map,
      );

  void _verify(
    String b,
    Map<String, dynamic> local,
    Map<String, dynamic> proof,
  ) {
    final d = local['document'] as Map;
    final snapshot = local['snapshot'] as Map;
    final invoice = _payload(local, 'document_draft_create');
    final customer = _payload(local, 'customer_create');
    final vehicle = _payload(local, 'vehicle_create');
    final payment = _payload(local, 'invoice_payment_received');
    if (invoice['customer_id'] != d['customer_id'] ||
        invoice['vehicle_id'] != d['vehicle_id'] ||
        invoice['kind'] != 'invoice' ||
        vehicle['customer_id'] != d['customer_id'] ||
        vehicle['idempotent_v1'] != true ||
        payment['invoice_id'] != d['id'] ||
        proof['customer_operation_id'] != customer['operation_id'] ||
        proof['local_vehicle_id'] != d['vehicle_id'] ||
        proof['document_number'] != d['document_number'] ||
        proof['job_number'] != d['job_number']) {
      throw StateError('Recovery chain or assigned numbers do not match.');
    }
    for (final key in ['id', 'customer_id', 'vehicle_id', 'job_id']) {
      final id = _text(proof[key]);
      if (id.startsWith('local-')) {
        throw StateError('Server identity is provisional.');
      }
    }
    final visit = local['visit'] as Map;
    final serverVisit = proof['initial_visit'];
    if (serverVisit is! Map ||
        serverVisit['job_id'] != proof['job_id'] ||
        serverVisit['visit_number'] != 1 ||
        serverVisit['closed_at'] != null ||
        (visit['work_summary']?.toString() ?? '') !=
            (serverVisit['work_summary']?.toString() ?? '') ||
        _text(serverVisit['id']).startsWith('local-')) {
      throw StateError('Initial visit identity or work summary differs.');
    }
    final lines = snapshot['lines'];
    final remote = proof['lines'];
    if (lines is! List ||
        remote is! List ||
        lines.isEmpty ||
        lines.length != remote.length) {
      throw StateError('Original invoice lines do not match.');
    }
    // Verify every original line, not just its count or aggregate total.
    for (var i = 0; i < lines.length; i++) {
      final a = lines[i] as Map, z = remote[i] as Map;
      for (final key in ['name', 'description', 'line_kind', 'item_id']) {
        if ((a[key]?.toString() ?? '') != (z[key]?.toString() ?? '')) {
          throw StateError('Invoice line ${i + 1} differs ($key).');
        }
      }
      for (final key in ['quantity', 'unit_price', 'tax_rate']) {
        final av = num.tryParse(a[key]?.toString() ?? '');
        final zv = num.tryParse(z[key]?.toString() ?? '');
        if (av == null || zv == null || !av.isFinite || av != zv) {
          throw StateError('Invoice line ${i + 1} differs ($key).');
        }
      }
    }
    for (final key in ['net_amount', 'tax_amount', 'total_amount']) {
      if (_cents(snapshot[key]) != _cents(proof[key])) {
        throw StateError('Original invoice totals differ ($key).');
      }
    }
    if (snapshot['document_date'] != proof['document_date'] ||
        (snapshot['memo']?.toString() ?? '') !=
            (proof['memo']?.toString() ?? '')) {
      throw StateError('Invoice date or notes differ.');
    }
    OfflineInvoiceRecoveryProof.verify(
      owner: true,
      invoice: proof,
      payments: (proof['payments'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList(),
      businessId: b,
      invoiceId: _text(proof['id']),
      invoiceOperationId: _text(invoice['operation_id']),
      paymentOperationId: _text(payment['operation_id']),
      totalCents: _cents(d['total']),
      paymentCents: payment['amount_cents'] as int,
      paymentMethodId: _text(payment['method_id']),
      paymentDate: _text(payment['payment_date']),
      expectedLineCount: lines.length,
    );
  }

  Future<String> reconcile({
    required bool isOwner,
    required String businessId,
    required String localInvoiceId,
  }) async {
    final mode = BriskersConnectionModeController.instance;
    if (!isOwner || !mode.forceOffline) {
      throw StateError('Owner and Force Offline are required for recovery.');
    }
    final revision = mode.revision;
    void guard() {
      if (!mode.forceOffline || mode.revision != revision) {
        throw StateError('Connection mode changed; no recovery was committed.');
      }
    }

    await RecoveryCommitStore.ensure(_db);
    final prior = await _rows(
      'SELECT server_invoice_id FROM recovery_commits WHERE business_id=? AND local_invoice_id=?',
      [businessId, localInvoiceId],
    );
    // The durable receipt is authoritative on restart; do not replay or re-adopt.
    if (prior.isNotEmpty) return prior.single.read<String>('server_invoice_id');
    final original = await _db.transaction(
      () => _local(businessId, localInvoiceId),
    );
    final d = original['document'] as Map;
    final proof = await _lookup({
      'p_business_id': businessId,
      'p_invoice_operation_id': _text(
        _payload(original, 'document_draft_create')['operation_id'],
      ),
      'p_customer_operation_id': _text(
        _payload(original, 'customer_create')['operation_id'],
      ),
      'p_local_vehicle_id': _text(d['vehicle_id']),
      'p_payment_operation_id': _text(
        _payload(original, 'invoice_payment_received')['operation_id'],
      ),
    });
    guard();
    _verify(businessId, original, proof);
    final mapping = <String, String>{
      localInvoiceId: _text(proof['id']),
      _text(d['job_id']): _text(proof['job_id']),
      _text(d['customer_id']): _text(proof['customer_id']),
      _text(d['vehicle_id']): _text(proof['vehicle_id']),
      _text((original['visit'] as Map)['id']): _text(
        (proof['initial_visit'] as Map)['id'],
      ),
    };
    if (mapping.length != 5 || mapping.values.toSet().length != 5) {
      throw StateError('Recovery identities are not distinct.');
    }
    await _db.transaction(() async {
      guard();
      final again = await _rows(
        'SELECT server_invoice_id FROM recovery_commits WHERE business_id=? AND local_invoice_id=?',
        [businessId, localInvoiceId],
      );
      if (again.isNotEmpty) {
        if (again.single.data['server_invoice_id'] != proof['id']) {
          throw StateError('Recovery identity cannot be overwritten.');
        }
        return;
      }
      if (jsonEncode(await _local(businessId, localInvoiceId)) !=
          jsonEncode(original)) {
        throw StateError(
          'Local records changed during verification. Retry while offline.',
        );
      }
      for (final job in [d['job_id'].toString(), proof['job_id'].toString()]) {
        if (await LocalJobRetirement.isJobBlocked(_db, businessId, job)) {
          throw StateError('A retired Job cannot be reconciled.');
        }
      }
      for (final id in [localInvoiceId, proof['id'].toString()]) {
        if (await LocalJobRetirement.isDocumentBlocked(_db, businessId, id)) {
          throw StateError('A retired invoice cannot be reconciled.');
        }
      }
      final archives = <Map<String, dynamic>>[];
      // Update exact relational identities only. Audit payloads and all original
      // outbox bytes remain intact; uncertain uniqueness conflicts roll back.
      const columns = {
        'id',
        'customer_id',
        'vehicle_id',
        'job_id',
        'document_id',
        'invoice_id',
        'visit_id',
        'found_job_id',
        'repair_job_id',
        'found_document_id',
        'repair_document_id',
        'mileage_source_invoice_id',
        'source_estimate_id',
        'converted_invoice_id',
      };
      final tables = await _db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'local_%' ORDER BY name",
          )
          .get();
      for (final t in tables) {
        final table = t.read<String>('name');
        if (!RegExp(r'^[a-z_]+$').hasMatch(table)) {
          throw StateError('Unknown local schema.');
        }
        if (table.contains('retirement') ||
            table.contains('quarantine') ||
            table.contains('audit')) {
          continue;
        }
        final info = await _db
            .customSelect('PRAGMA table_info("$table")')
            .get();
        final names = info.map((r) => r.read<String>('name')).toSet();
        if (!names.contains('business_id')) continue;
        final keys = names.intersection(columns);
        for (final key in keys) {
          for (final entry in mapping.entries) {
            final rows = await _rows(
              'SELECT * FROM "$table" WHERE business_id=? AND "$key"=?',
              [businessId, entry.key],
            );
            if (rows.isEmpty) continue;
            archives.add({
              'table': table,
              'column': key,
              'rows': rows.map((r) => r.data).toList(),
            });
            await _db.customStatement(
              'UPDATE "$table" SET "$key"=? WHERE business_id=? AND "$key"=?',
              [entry.value, businessId, entry.key],
            );
          }
        }
      }
      for (final entry in {
        'local_documents': proof['id'],
        'local_jobs': proof['job_id'],
        'local_customers': proof['customer_id'],
        'local_vehicles': proof['vehicle_id'],
        'local_job_visits': (proof['initial_visit'] as Map)['id'],
      }.entries) {
        await _db.customStatement(
          'UPDATE ${entry.key} SET sync_state=? WHERE business_id=? AND id=?',
          ['synced', businessId, entry.value],
        );
      }
      for (final op in (original['operations'] as Map).values) {
        await _db.customStatement(
          "UPDATE sync_outbox SET state='reconciled' WHERE business_id=? AND id=? AND state='conflict'",
          [businessId, (op as Map)['id']],
        );
      }
      final active = Map<String, dynamic>.from(proof)
        ..['sync_state'] = 'synced';
      await _db.customStatement(
        'INSERT INTO recovery_document_cache(business_id,document_id,payload_json) VALUES(?,?,?)',
        [businessId, proof['id'], jsonEncode(active)],
      );
      await _db.customStatement(
        '''INSERT INTO recovery_commits(business_id,local_invoice_id,
        server_invoice_id,identities_json,original_json,proof_json) VALUES(?,?,?,?,?,?)''',
        [
          businessId,
          localInvoiceId,
          proof['id'],
          jsonEncode(mapping),
          jsonEncode({...original, 'relational_rows': archives}),
          jsonEncode(proof),
        ],
      );
      guard();
    });
    return proof['id'] as String;
  }
}
