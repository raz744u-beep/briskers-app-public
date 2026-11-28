import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import 'repair_group_schema.dart';
import 'lan_record_inventory.dart';
import 'local_document_detail_cache.dart';
import 'local_document_sql_store.dart';
import 'local_estimate_number.dart';
import 'local_job_deletion_v3.dart';
import 'local_job_retirement.dart';
import 'local_number_allocator.dart';
import 'recovery_commit_store.dart';

/// A standalone, unconverted estimate can move with its complete saved detail.
class LanStandaloneEstimateCopy {
  const LanStandaloneEstimateCopy(this.db);

  final BriskersLocalDatabase db;

  Future<int?> _cursor(String business) async {
    final row =
        await (db.select(db.localSyncStates)..where(
              (row) =>
                  row.businessId.equals(business) &
                  row.scope.equals('documents') &
                  row.bootstrapped.equals(true),
            ))
            .getSingleOrNull();
    return row?.lastServerCursor;
  }

  static int? _number(Object? value) {
    final number = LocalEstimateNumber.existing(value);
    return number == null ? null : int.parse(number.substring(2));
  }

  static bool _eligible(LocalDocument row, String business) =>
      row.businessId == business &&
      row.kind == 'estimate' &&
      row.syncState == 'synced' &&
      row.id.isNotEmpty &&
      !row.id.startsWith('local-') &&
      row.jobId == null &&
      row.customerId != null &&
      !row.converted &&
      row.closedAt == null &&
      const {'draft', 'open'}.contains(row.status) &&
      const {null, 'draft', 'open'}.contains(row.displayStatusCode) &&
      _number(row.documentNumber) != null;

  static Map<String, dynamic>? _detail(String? raw, LocalDocument row) {
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic> ||
          data['id'] != row.id ||
          data['kind'] != row.kind ||
          (data['business_id'] != null &&
              data['business_id'] != row.businessId) ||
          data['customer_id'] != row.customerId ||
          data['job_id'] != null ||
          data['status'] != row.status ||
          !const {
            null,
            'draft',
            'open',
          }.contains(data['display_status_code']) ||
          (row.rowVersion != null && data['row_version'] != row.rowVersion) ||
          _number(data['document_number']) != _number(row.documentNumber) ||
          data['converted'] == true ||
          data['converted_invoice_id'] != null ||
          data['_local_draft'] == true ||
          data['_server_document_id'] != null ||
          data['signature'] != null ||
          data['signature_url'] != null ||
          data['signed_at'] != null ||
          data['approved_at'] != null ||
          data['declined_at'] != null ||
          data['authorization'] != null ||
          data['authorization_number'] != null ||
          (data['paid_amount'] ?? 0) != 0 ||
          (data['pending_payment'] ?? 0) != 0 ||
          data['lines'] is! List ||
          (data['lines'] as List).any(
            (line) => line is! Map<String, dynamic>,
          )) {
        return null;
      }
      return data;
    } on FormatException {
      return null;
    }
  }

  Future<Set<String>> _blocked(String business) async {
    await LocalDocumentSqlStore.ensure(db);
    await RepairGroupSchema.ensure(db);
    final prefix = LocalDocumentDetailCache.key(business, '');
    final rows = await db
        .customSelect(
          'SELECT entity_id AS id FROM sync_outbox WHERE business_id=? AND state<>\'done\' '
          'UNION SELECT estimate_id AS id FROM local_estimate_conversion_evidence WHERE business_id=? '
          'UNION SELECT estimate AS id FROM repair_groups_v1 WHERE business=? '
          'UNION SELECT estimate AS id FROM repair_group_members_v1 WHERE business=? '
          'UNION SELECT substr(cache_key,?) AS id FROM local_document_detail_deleted '
          'WHERE substr(cache_key,1,?)=?',
          variables: [
            for (var i = 0; i < 4; i++) Variable(business),
            Variable(prefix.length + 1),
            Variable(prefix.length),
            Variable(prefix),
          ],
        )
        .get();
    final aliases = await db
        .customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' "
          "AND name='local_document_identity_aliases'",
        )
        .getSingleOrNull();
    final linkedIds = aliases == null
        ? <QueryRow>[]
        : await db
              .customSelect(
                'SELECT alias_id AS id FROM local_document_identity_aliases WHERE business_id=? '
                'UNION SELECT canonical_id AS id FROM local_document_identity_aliases WHERE business_id=?',
                variables: [Variable(business), Variable(business)],
              )
              .get();
    return {
      ...await LocalJobRetirement.blockedDocumentIds(db, business),
      ...await LocalJobDeletionV3.blockedDocumentIds(db, business),
      for (final row in [...rows, ...linkedIds]) row.read<String>('id'),
    };
  }

  Future<Map<String, String?>> _details(String business) async {
    final prefix = LocalDocumentDetailCache.key(business, '');
    final rows = await db
        .customSelect(
          "SELECT d.id, c.payload_json FROM local_documents d "
          "JOIN local_document_details c ON c.cache_key=? || d.id "
          "WHERE d.business_id=? AND d.kind='estimate'",
          variables: [Variable(prefix), Variable(business)],
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('id'): row.readNullable<String>('payload_json'),
    };
  }

  Future<Map<String, dynamic>?> share(String business) async {
    final cursor = await _cursor(business);
    if (cursor == null || cursor < 0) return null;
    final blocked = await _blocked(business);
    final details = await _details(business);
    final docs =
        await (db.select(db.localDocuments)..where(
              (row) =>
                  row.businessId.equals(business) & row.kind.equals('estimate'),
            ))
            .get();
    final counts = <int?, int>{};
    for (final row in docs) {
      counts.update(
        _number(row.documentNumber),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      'cursor': cursor,
      'records': [
        for (final row in docs)
          if (_eligible(row, business) &&
              !blocked.contains(row.id) &&
              counts[_number(row.documentNumber)] == 1 &&
              _detail(details[row.id], row) != null)
            {'index': row.toJson(), 'detail': details[row.id]},
      ],
    };
  }

  Future<int> copyMissing({
    required String business,
    required Object? bundle,
    required Map<String, LocalCustomer> sourceCustomers,
    required Map<String, LocalVehicle> sourceVehicles,
    required Map<String, List<LocalCustomerVehicle>> sourceLinks,
    required Set<String> queuedIds,
    required Set<String> approvedIdentities,
  }) async {
    if (bundle == null) return 0;
    if (bundle is! Map<String, dynamic> ||
        bundle['cursor'] is! int ||
        bundle['records'] is! List) {
      throw const FormatException('Invalid estimate copy data.');
    }
    final cursor = await _cursor(business);
    if (cursor == null ||
        cursor < 0 ||
        (bundle['cursor'] as int) < cursor ||
        (bundle['records'] as List).isEmpty) {
      return 0;
    }

    final blocked = await _blocked(business);
    final prefix = LocalDocumentDetailCache.key(business, '');
    final cached = await db
        .customSelect(
          'SELECT cache_key FROM local_document_details WHERE substr(cache_key,1,?)=?',
          variables: [Variable(prefix.length), Variable(prefix)],
        )
        .get();
    final prefs = await SharedPreferences.getInstance();
    final existingDetails = {
      ...prefs.getKeys(),
      for (final row in cached) row.read<String>('cache_key'),
    };
    final existing = {
      for (final row in await db.select(db.localDocuments).get()) row.id,
    };
    final numbers = await LocalNumberAllocator(
      db,
    ).occupiedNumbers(business, 'estimate');
    final ids = <String>{};
    final sourceNumbers = <int>{};
    var copied = 0;
    for (final raw in bundle['records'] as List<dynamic>) {
      if (raw is! Map<String, dynamic> ||
          raw['index'] is! Map<String, dynamic> ||
          raw['detail'] is! String) {
        throw const FormatException('Invalid LAN estimate.');
      }
      final row = LocalDocument.fromJson(raw['index'] as Map<String, dynamic>);
      final serialized = raw['detail'] as String;
      final detail = _detail(serialized, row);
      if (!_eligible(row, business) || detail == null || !ids.add(row.id)) {
        throw const FormatException('Invalid or duplicate LAN estimate.');
      }
      final number = _number(row.documentNumber)!;
      if (!sourceNumbers.add(number)) {
        throw const FormatException('Duplicate LAN estimate number.');
      }
      final key = LocalDocumentDetailCache.key(business, row.id);
      if (!approvedIdentities.contains(
            LanRecordInventory.recordIdentity(business, 'estimate', row.id),
          ) ||
          blocked.contains(row.id) ||
          existing.contains(row.id) ||
          existingDetails.contains(key) ||
          numbers.contains(number) ||
          await RecoveryCommitStore.isOriginal(db, business, row.id) ||
          await RecoveryCommitStore.snapshot(db, business, row.id) != null) {
        continue;
      }

      final customer = sourceCustomers[row.customerId];
      if (customer == null || queuedIds.contains(customer.id)) continue;
      final savedCustomer = await (db.select(
        db.localCustomers,
      )..where((row) => row.id.equals(customer.id))).getSingleOrNull();
      if (savedCustomer != customer) continue;
      final vehicleId = detail['vehicle_id'];
      if (vehicleId != null) {
        final vehicle = sourceVehicles[vehicleId];
        if (vehicle == null || queuedIds.contains(vehicle.id)) continue;
        final originalLinks = sourceLinks[vehicle.id];
        if (originalLinks?.length != 1 ||
            originalLinks!.single.customerId != customer.id) {
          continue;
        }
        final savedVehicle = await (db.select(
          db.localVehicles,
        )..where((row) => row.id.equals(vehicle.id))).getSingleOrNull();
        final savedLinks =
            await (db.select(db.localCustomerVehicles)..where(
                  (row) =>
                      row.businessId.equals(business) &
                      row.vehicleId.equals(vehicle.id),
                ))
                .get();
        if (savedVehicle != vehicle ||
            savedLinks.length != 1 ||
            savedLinks.single.customerId != customer.id) {
          continue;
        }
      }

      await db.into(db.localDocuments).insert(row);
      await db.customStatement(
        'INSERT INTO local_document_details VALUES (?,?)',
        [key, serialized],
      );
      numbers.add(number);
      copied++;
    }
    return copied;
  }
}
