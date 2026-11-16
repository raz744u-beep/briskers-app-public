import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart';
import 'local_number_allocator.dart';

/// Public estimate numbers and stable synchronization identities are separate.
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
        !RegExp(r'^(E-)?[0-9]{1,9}$', caseSensitive: false).hasMatch(number)) {
      return null;
    }
    final digits = number.replaceFirst(
      RegExp(r'^E-', caseSensitive: false),
      '',
    );
    return int.parse(digits) == 0 ? null : 'E-$digits';
  }

  static bool isDraft(Object? status) =>
      status?.toString().trim().toLowerCase() == 'draft';

  static Future<String> allocate(
    BriskersLocalDatabase db,
    String business,
    String id,
  ) async {
    final allocator = LocalNumberAllocator(db);
    return allocator.display(
      'estimate',
      await allocator.allocate(business, 'estimate', id),
    );
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

  /// Only drafts are repaired automatically. An issued estimate requires
  /// confirmation, and the old identifier is retained in an append-only audit.
  static Future<String?> repair(
    BriskersLocalDatabase db,
    String business,
    String id, {
    String? cachedNumber,
    bool confirmed = false,
    bool cachedIssued = false,
  }) => db.transaction(() async {
    final row = await db
        .customSelect(
          "SELECT document_number,status,converted FROM local_documents WHERE business_id=? AND id=? AND kind='estimate'",
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    if (row == null) return existing(cachedNumber);
    final previous = row.readNullable<String>('document_number');
    final valid = existing(previous);
    if (valid != null) return valid;
    final historical = existing(cachedNumber);
    final issued =
        cachedIssued ||
        !isDraft(row.data['status']) ||
        row.read<int>('converted') != 0;
    if (issued && !confirmed && historical == null) return null;
    final number = historical ?? await allocate(db, business, id);
    if (historical != null) {
      final others = await db
          .customSelect(
            "SELECT document_number FROM local_documents WHERE business_id=? AND kind='estimate' AND id<>?",
            variables: [Variable(business), Variable(id)],
          )
          .get();
      final ordinal = int.parse(number.substring(2));
      if (others.any((other) {
        final candidate = existing(other.data['document_number']);
        return candidate != null &&
            int.parse(candidate.substring(2)) == ordinal;
      }))
        return null;
    }
    await db.customStatement(
      "UPDATE local_documents SET document_number=? WHERE business_id=? AND id=? AND kind='estimate'",
      [number, business, id],
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS local_estimate_number_audit_v2 '
      '(business_id TEXT NOT NULL, estimate_id TEXT NOT NULL, original_number TEXT, '
      'public_number TEXT NOT NULL, owner_confirmed INTEGER NOT NULL, recorded_at TEXT NOT NULL, '
      'PRIMARY KEY(business_id,estimate_id,public_number))',
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO local_estimate_number_audit_v2 VALUES(?,?,?,?,?,?)',
      [
        business,
        id,
        previous,
        number,
        confirmed ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    if (_uuid.hasMatch(id)) {
      await ensureRepairQueue(db);
      await db.customStatement(
        'INSERT OR REPLACE INTO local_estimate_number_sync_v2 '
        '(business_id,estimate_id,public_number,owner_confirmed) VALUES(?,?,?,?)',
        [business, id, number, confirmed ? 1 : 0],
      );
    }
    return number;
  });

  static Future<void> ensureRepairQueue(
    BriskersLocalDatabase db,
  ) => db.customStatement(
    'CREATE TABLE IF NOT EXISTS local_estimate_number_sync_v2 '
    '(business_id TEXT NOT NULL, estimate_id TEXT NOT NULL, public_number TEXT NOT NULL, '
    'owner_confirmed INTEGER NOT NULL, conflict TEXT, PRIMARY KEY(business_id,estimate_id))',
  );
}
