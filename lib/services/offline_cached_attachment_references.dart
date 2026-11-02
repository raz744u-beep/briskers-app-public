import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';

/// Remote photo references already learned from authenticated, shop-scoped
/// local financial and customer-note snapshots. Reads only: no server fetches,
/// no permission promotions, no changes to pending/unsynced originals.
class OfflineCachedAttachmentReferences {
  const OfflineCachedAttachmentReferences({BriskersLocalDatabase? database})
      : _database = database;

  final BriskersLocalDatabase? _database;

  Future<List<OfflineMediaReference>> collect(String businessId) async {
    if (businessId.isEmpty) return const [];
    final references = <String, OfflineMediaReference>{};
    void collectFrom(Object? data) {
      if (data is List) {
        for (final value in data) {
          collectFrom(value);
        }
        return;
      }
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final attachments = map['attachments'];
      if (attachments is List) {
        for (final raw in attachments.whereType<Map>()) {
          final attachment = Map<String, dynamic>.from(raw);
          final state = attachment['upload_state']?.toString() ?? '';
          if (state == 'pending' || state == 'uploading' ||
              state == 'failed') {
            // Device-only, unsynchronized photos must remain where they are.
            continue;
          }
          final bucket =
              attachment['bucket']?.toString() ?? 'briskers-private';
          final key = attachment['key']?.toString() ?? '';
          if (bucket.isEmpty || key.isEmpty) continue;
          final ref = OfflineMediaReference(
            bucket: bucket,
            key: key,
            localPath: attachment['local_file_path']?.toString() ?? '',
          );
          references['${ref.bucket}::${ref.key}'] = ref;
        }
      }
    }

    Object? decode(String? payload) {
      if (payload == null || payload.isEmpty) return null;
      try {
        return jsonDecode(payload);
      } catch (_) {
        // A partially written/corrupted snapshot is never considered proof.
        return null;
      }
    }

    // Financial receipt and transaction detail caches are business-scoped.
    // Exclude totals/aggregates; amounts and financial calculations are not
    // read or modified by the media mirror.
    final database = _database ?? localDatabase;
    final rows = await database.customSelect(
      '''
      SELECT payload_json FROM local_financial_cache
      WHERE business_id = ? AND (
        cache_key LIKE 'transaction_detail_%'
        OR cache_key = 'transactions_snapshot'
        OR cache_key = 'linked_expenses_complete_v1'
      )
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    for (final row in rows) {
      collectFrom(decode(row.readNullable<String>('payload_json')));
    }

    // Notes use SharedPreferences rather than SQLite. The exact shop-scoped
    // prefix AND suffix prevent reading another shop's customer snapshots.
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'briskers_customer_section_${businessId}_';
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix) || !key.endsWith('_notes')) continue;
      collectFrom(decode(prefs.getString(key)));
    }

    final result = references.values.toList()
      ..sort((a, b) =>
          '${a.bucket}::${a.key}'.compareTo('${b.bucket}::${b.key}'));
    return result;
  }
}

class OfflineMediaReference {
  const OfflineMediaReference({
    required this.bucket,
    required this.key,
    this.localPath = '',
  });

  final String bucket;
  final String key;
  final String localPath;
}
