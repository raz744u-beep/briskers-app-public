import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';

/// The public number is derived from the permanent record identity. Devices
/// can allocate independently, including before they have ever synchronized.
class LocalEstimateNumber {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String identity(String business, String documentId) {
    final raw = documentId.replaceFirst(RegExp(r'^local-estimate-'), '');
    if (_uuid.hasMatch(raw)) return raw.toLowerCase();
    // Pre-upgrade drafts used a timestamp and salt instead of a UUID. Keep
    // their existing local identity and derive a repeatable sync identity.
    final bytes = const DartSha256()
        .hashSync(utf8.encode(jsonEncode([business, documentId])))
        .bytes;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '8${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20, 32)}';
  }

  static String? existing(Object? value) {
    final number = value?.toString().trim();
    if (number == null ||
        number.isEmpty ||
        number.toLowerCase() == 'pending sync') {
      return null;
    }
    return number;
  }

  static String forDocument(String business, String id) =>
      'EST-${identity(business, id).replaceAll('-', '').toUpperCase()}';

  static Map<String, dynamic> project(
    String business,
    Map<String, dynamic> detail,
  ) {
    final id = detail['id']?.toString();
    if (detail['kind'] != 'estimate' ||
        id == null ||
        id.isEmpty ||
        existing(detail['document_number']) != null) {
      return detail;
    }
    return {...detail, 'document_number': forDocument(business, id)};
  }

  static Future<String?> stored(
    BriskersLocalDatabase db,
    String business,
    String id,
  ) async {
    final row = await db
        .customSelect(
          "SELECT document_number FROM local_documents WHERE business_id=? AND id=? AND kind='estimate'",
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    return existing(row?.data['document_number']);
  }

  static Future<void> fillMissing(
    BriskersLocalDatabase db,
    String business,
    String id,
    Object? knownNumber,
  ) => db.customStatement(
    "UPDATE local_documents SET document_number=? WHERE business_id=? AND id=? AND kind='estimate' "
    "AND (document_number IS NULL OR lower(trim(document_number)) IN ('','pending sync'))",
    [existing(knownNumber) ?? forDocument(business, id), business, id],
  );
  static Future<void> ensureRepairQueue(
    BriskersLocalDatabase db,
  ) => db.customStatement(
    'CREATE TABLE IF NOT EXISTS local_estimate_number_repairs_v1 '
    '(business_id TEXT NOT NULL, estimate_id TEXT NOT NULL, PRIMARY KEY(business_id,estimate_id))',
  );

  static Future<void> queueServerRepair(
    BriskersLocalDatabase db,
    String business,
    String id,
  ) async {
    if (!_uuid.hasMatch(id)) return;
    await ensureRepairQueue(db);
    await db.customStatement(
      'INSERT OR IGNORE INTO local_estimate_number_repairs_v1 VALUES(?,?)',
      [business, id],
    );
  }
}
