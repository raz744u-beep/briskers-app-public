import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_attachment_cache.dart';

/// Opportunistically mirrors photo objects already referenced by authorized,
/// locally synchronized Jobs/Findings. Never edits records or removes originals.
///
/// This is a bounded part of the complete offline media mirror: customer notes,
/// expenses and imported ExpenseIQ originals need their own inventories.
class OfflineAttachmentMirrorService {
  OfflineAttachmentMirrorService({
    BriskersLocalDatabase? database,
    LocalAttachmentCache? cache,
  }) : _database = database ?? localDatabase,
       _cache = cache ?? LocalAttachmentCache();

  final BriskersLocalDatabase _database;
  final LocalAttachmentCache _cache;

  static const _cursorPrefix = 'briskers_media_prefetch_cursor_';

  Future<OfflineAttachmentMirrorResult> prefetchBatch(
    String businessId, {
    int batchSize = 24,
  }) async {
    if (businessId.isEmpty || batchSize <= 0 ||
        BriskersConnectionModeController.instance.forceOffline) {
      return const OfflineAttachmentMirrorResult(
        examined: 0, downloaded: 0, missing: 0, total: 0);
    }

    // Only synchronized, server-backed keys are eligible. Local-only camera
    // files are never copied, evicted, rewritten or marked synced here.
    const keys = '''
      SELECT storage_bucket AS bucket, storage_key AS object_key,
             local_file_path AS local_path
      FROM local_finding_photos
      WHERE business_id = ? AND upload_state = 'synced'
        AND COALESCE(storage_bucket, '') <> ''
        AND COALESCE(storage_key, '') <> ''
      UNION
      SELECT storage_bucket AS bucket, storage_key AS object_key,
             local_file_path AS local_path
      FROM local_pre_inspection_photos
      WHERE business_id = ? AND upload_state = 'synced'
        AND COALESCE(storage_bucket, '') <> ''
        AND COALESCE(storage_key, '') <> ''
    ''';
    final count = await _database.customSelect(
      'SELECT COUNT(*) AS n FROM ($keys)',
      variables: [Variable<String>(businessId), Variable<String>(businessId)],
    ).getSingle();
    final total = count.read<int>('n');
    if (total == 0) {
      return const OfflineAttachmentMirrorResult(
        examined: 0, downloaded: 0, missing: 0, total: 0);
    }

    final prefs = await SharedPreferences.getInstance();
    final cursorKey = '$_cursorPrefix$businessId';
    final offset = prefs.getInt(cursorKey) ?? 0;
    final safeOffset = offset >= total ? 0 : offset;
    final rows = await _database.customSelect(
      'SELECT * FROM ($keys) ORDER BY bucket, object_key LIMIT ? OFFSET ?',
      variables: [
        Variable<String>(businessId), Variable<String>(businessId),
        Variable<int>(batchSize), Variable<int>(safeOffset),
      ],
    ).get();
    var downloaded = 0;
    var missing = 0;
    for (final row in rows) {
      if (BriskersConnectionModeController.instance.forceOffline) break;
      final existingPath = row.readNullable<String>('local_path') ?? '';
      if (existingPath.isNotEmpty && await File(existingPath).exists()) {
        continue;
      }
      final bucket = row.read<String>('bucket');
      final key = row.read<String>('object_key');
      if (await _cache.existing(bucket, key) != null) continue;
      // LocalAttachmentCache writes atomically via .part and retries missing
      // objects on a later cursor cycle. Download errors don't block the UI.
      final file = await _cache.getOrDownload(bucket, key);
      if (file == null) {
        missing++;
      } else {
        downloaded++;
      }
    }
    final next = safeOffset + rows.length;
    await prefs.setInt(cursorKey, next >= total ? 0 : next);
    return OfflineAttachmentMirrorResult(
      examined: rows.length, downloaded: downloaded,
      missing: missing, total: total,
    );
  }
}

class OfflineAttachmentMirrorResult {
  const OfflineAttachmentMirrorResult({
    required this.examined,
    required this.downloaded,
    required this.missing,
    required this.total,
  });

  final int examined, downloaded, missing, total;
}
