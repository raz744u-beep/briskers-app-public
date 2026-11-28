import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'lan_estimate_repair_groups.dart';
import 'local_document_detail_cache.dart';
import 'local_document_sql_store.dart';
import 'local_job_retirement.dart';

typedef LanInventoryEntry = ({
  String kind,
  String identity,
  String fingerprint,
  bool pending,
  bool hasDocumentDetail,
  Map<String, String> review,
});

typedef LanInventoryDifference = ({
  List<LanInventoryEntry> onlyOnSource,
  List<LanInventoryEntry> onlyOnDestination,
  List<LanInventoryEntry> different,
  Map<String, LanInventoryEntry> destinationVersions,
  List<LanInventoryEntry> unverified,
});

/// Read-only inventory for the preview. Fingerprints describe the fields
/// compared here and do not establish that a record is safe to import.
class LanRecordInventory {
  LanRecordInventory(this.db);
  final BriskersLocalDatabase db;

  static const _columns = {
    'customer': 'id, display_name, is_company, email, phone, billing_address_json, '
        'taxable, problem_flag, problem_flag_note, contacts_json, sync_state',
    'vehicle': 'id, year, make, model, vin, license_plate, license_state, '
        'mileage, mileage_recorded_date, mileage_source_invoice_id, color, sync_state',
    'job': 'id, job_number, title, requested_work, status, customer_id, vehicle_id, '
        'planned_hours, odometer_in, assigned_employee_id, completed_at, sync_state',
    'document': 'id, kind, document_number, status, customer_id, job_id, '
        'closed_at, converted, total, document_date, sync_state',
  };

  static const _tables = {
    'customer': 'local_customers',
    'vehicle': 'local_vehicles',
    'job': 'local_jobs',
    'document': 'local_documents',
  };

  static String _hash(Object? value) => base64UrlEncode(
    const DartSha256().hashSync(utf8.encode(jsonEncode(value))).bytes,
  );

  static String shopFingerprint(String business) =>
      _hash(['briskers-lan-inventory-v1', business]);

  static String recordIdentity(String business, String kind, String id) =>
      _hash([shopFingerprint(business), kind, id]);

  Future<List<LanInventoryEntry>> read(String business) => db.transaction(() async {
    if (business.trim().isEmpty) throw ArgumentError('A shop is required.');
    await LocalDocumentSqlStore.ensure(db);
    final blockedJobs = await LocalJobRetirement.blockedJobIds(db, business);
    final blockedDocuments = await LocalJobRetirement.blockedDocumentIds(db, business);
    final repairGroups = await LanEstimateRepairGroups(db).read(business);
    final entries = <LanInventoryEntry>[];

    for (final kind in _tables.keys) {
      final table = _tables[kind]!;
      final columns = _columns[kind]!;
      final document = kind == 'document';
      final rows = await db.customSelect(
        'SELECT $columns'
        '${document ? ', cache.payload_json AS cached_detail' : ''} '
        'FROM (SELECT $columns FROM $table WHERE business_id=?) record '
        '${document ? "LEFT JOIN local_document_details cache ON cache.cache_key=? || record.id "
          "WHERE record.kind IN ('estimate','invoice') AND NOT EXISTS "
          "(SELECT 1 FROM local_document_detail_deleted gone WHERE gone.cache_key=? || record.id)" : ''} '
        'ORDER BY record.id',
        variables: [
          Variable(business),
          if (document) ...[
            Variable(LocalDocumentDetailCache.key(business, '')),
            Variable(LocalDocumentDetailCache.key(business, '')),
          ],
        ],
      ).get();
      for (final row in rows) {
        final id = row.read<String>('id');
        if ((kind == 'job' && blockedJobs.contains(id)) ||
            (document && (blockedDocuments.contains(id) ||
              blockedJobs.contains(row.readNullable<String>('job_id'))))) {
          continue;
        }
        final recordKind = document ? row.read<String>('kind') : kind;
        final payload = Map<String, Object?>.from(row.data);
        final cached = payload.remove('cached_detail');
        final pending = payload.remove('sync_state') != 'synced' || id.startsWith('local-');
        final detail = _documentFields(cached, business, id, recordKind);
        final groups = recordKind == 'estimate' ? repairGroups[id] : null;
        entries.add((
          kind: recordKind,
          identity: recordIdentity(business, recordKind, id),
          fingerprint: _hash([payload, detail, ?groups]),
          pending: pending,
          hasDocumentDetail: detail != null,
          review: {
            ..._reviewFields(recordKind, payload, detail),
            if (groups != null) 'Repair groups': '${groups['groups']!.length}',
          },
        ));
      }
    }
    return List.unmodifiable(entries);
  });

  static Map<String, String> _reviewFields(
    String kind, Map<String, Object?> row, List<Object?>? detail,
  ) {
    final fields = switch (kind) {
      'customer' => {'Name': 'display_name', 'Company': 'is_company', 'Taxable': 'taxable'},
      'vehicle' => {'Year': 'year', 'Make': 'make', 'Model': 'model', 'Mileage': 'mileage', 'Color': 'color'},
      'job' => {'Number': 'job_number', 'Title': 'title', 'Status': 'status', 'Mileage in': 'odometer_in'},
      _ => {'Number': 'document_number', 'Status': 'status', 'Total': 'total', 'Date': 'document_date'},
    };
    String limited(Object? value) {
      final text = value?.toString() ?? '';
      return text.length <= 96 ? text : '${text.substring(0, 96)}…';
    }
    return {
      for (final field in fields.entries) field.key: limited(row[field.value]),
      if (detail != null) 'Line items': '${detail.length - 1}',
    };
  }

  static List<Object?>? _documentFields(
    Object? raw, String business, String id, String kind,
  ) {
    if (raw is! String) return null;
    try {
      final detail = jsonDecode(raw);
      if (detail is! Map || detail['id'] != id || detail['kind'] != kind ||
          (detail['business_id'] != null && detail['business_id'] != business) ||
          detail['lines'] is! List) {
        return null;
      }
      final lines = detail['lines'] as List;
      if (lines.any((line) => line is! Map)) return null;
      return [
        detail['memo'],
        for (final line in lines.cast<Map>())
          [
            line['id'], line['line_kind'], line['name'], line['description'],
            line['quantity'], line['unit_price'], line['tax_rate'],
          ],
      ];
    } on FormatException {
      return null;
    }
  }

  static LanInventoryDifference compare(
    Iterable<LanInventoryEntry> source,
    Iterable<LanInventoryEntry> destination,
  ) {
    Map<String, LanInventoryEntry> index(Iterable<LanInventoryEntry> entries) {
      final result = <String, LanInventoryEntry>{};
      for (final entry in entries) {
        if (result.containsKey(entry.identity)) {
          throw const FormatException('Duplicate device inventory identity.');
        }
        result[entry.identity] = entry;
      }
      return result;
    }

    final from = index(source);
    final to = index(destination);
    final onlyOnSource = <LanInventoryEntry>[];
    final onlyOnDestination = <LanInventoryEntry>[];
    final different = <LanInventoryEntry>[];
    final unverified = <LanInventoryEntry>[];
    bool needsReview(LanInventoryEntry entry) => entry.pending ||
        (const {'estimate', 'invoice'}.contains(entry.kind) &&
            !entry.hasDocumentDetail);
    for (final entry in from.values) {
      final other = to[entry.identity];
      if (needsReview(entry) || (other != null && needsReview(other))) {
        unverified.add(entry);
      } else if (other == null) {
        onlyOnSource.add(entry);
      } else if (entry.fingerprint != other.fingerprint) {
        different.add(entry);
      }
    }
    for (final entry in to.values) {
      if (from.containsKey(entry.identity)) continue;
      (needsReview(entry) ? unverified : onlyOnDestination).add(entry);
    }
    return (
      onlyOnSource: List.unmodifiable(onlyOnSource),
      onlyOnDestination: List.unmodifiable(onlyOnDestination),
      different: List.unmodifiable(different),
      destinationVersions: Map.unmodifiable({
        for (final entry in [...different, ...unverified])
          if (from.containsKey(entry.identity) && to.containsKey(entry.identity))
            entry.identity: to[entry.identity]!,
      }),
      unverified: List.unmodifiable(unverified),
    );
  }
}
