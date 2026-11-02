import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/connection_mode.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_attachment_cache.dart';
import 'offline_cached_attachment_references.dart';

/// Opportunistically mirrors photo objects already referenced by authorized,
/// locally synchronized Jobs/Findings. Never edits records or removes originals.
///
/// This is a bounded part of the complete offline media mirror: customer notes,
/// expenses and imported ExpenseIQ originals need their own inventories.
class OfflineAttachmentMirrorService {
  OfflineAttachmentMirrorService({
    BriskersLocalDatabase? database,
    LocalAttachmentCache? cache,
    OfflineCachedAttachmentReferences? cachedReferences,
  }) : _database = database ?? localDatabase,
       _cache = cache ?? LocalAttachmentCache(),
       _cachedReferences = cachedReferences ??
           OfflineCachedAttachmentReferences(database: database);

  final BriskersLocalDatabase _database;
  final LocalAttachmentCache _cache;
  final OfflineCachedAttachmentReferences _cachedReferences;

  static const _cursorPrefix = 'briskers_media_prefetch_cursor_';

  // Read-only catalog: the 'total' is only media whose *metadata* this
  // device knows. Never call that all of the shop's historical attachments.
  Future<List<OfflineMediaReference>> knownReferences(String businessId) async {
    if (businessId.isEmpty) return const [];
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
    // Include previously cached finance/receipt and customer-note photos.
    // This is a local inventory only; the worker never enumerates a cloud
    // bucket or requests records outside the authenticated shop mirror.
    final known = <String, OfflineMediaReference>{};
    void add(OfflineMediaReference ref) {
      if (ref.bucket.isEmpty || ref.key.isEmpty) return;
      final id = '${ref.bucket}::${ref.key}';
      final previous = known[id];
      if (previous == null ||
          (previous.localPath.isEmpty && ref.localPath.isNotEmpty)) {
        known[id] = ref;
      }
    }

    final rows = await _database.customSelect(
      'SELECT * FROM ($keys)',
      variables: [Variable<String>(businessId), Variable<String>(businessId)],
    ).get();
    for (final row in rows) {
      add(OfflineMediaReference(
        bucket: row.read<String>('bucket'),
        key: row.read<String>('object_key'),
        localPath: row.readNullable<String>('local_path') ?? '',
      ));
    }
    try {
      for (final ref in await _cachedReferences.collect(businessId)) {
        add(ref);
      }
    } catch (_) {
      // Keep locally indexed Findings and inspections available even when
      // a legacy financial/note cache is unreadable. It will retry later.
    }
    final ordered = known.values.toList()
      ..sort((a, b) =>
          '${a.bucket}::${a.key}'.compareTo('${b.bucket}::${b.key}'));
    return ordered;
  }

  Future<OfflineAttachmentInventory> inventory(String businessId) async {
    final refs = await knownReferences(businessId);
    var locallyAvailable = 0;
    for (final ref in refs) {
      if (ref.localPath.isNotEmpty) {
        final file = File(ref.localPath);
        if (await file.exists() && await file.length() > 0) {
          locallyAvailable++;
          continue;
        }
      }
      if (await _cache.existing(ref.bucket, ref.key) != null) {
        locallyAvailable++;
      }
    }
    return OfflineAttachmentInventory(
      known: refs.length,
      available: locallyAvailable,
    );
  }



  Future<OfflineAttachmentMirrorResult> prefetchBatch(
    String businessId, {
    int batchSize = 24,
  }) async {
    if (businessId.isEmpty || batchSize <= 0 ||
        BriskersConnectionModeController.instance.forceOffline) {
      return const OfflineAttachmentMirrorResult(
        examined: 0, downloaded: 0, missing: 0, total: 0);
    }

    final ordered = await knownReferences(businessId);
    final total = ordered.length;
    if (total == 0) {
      return const OfflineAttachmentMirrorResult(
          examined: 0, downloaded: 0, missing: 0, total: 0);
    }

    final prefs = await SharedPreferences.getInstance();
    final cursorKey = '$_cursorPrefix$businessId';
    final offset = prefs.getInt(cursorKey) ?? 0;
    final safeOffset = offset < 0 || offset >= total ? 0 : offset;
    final batch = ordered.skip(safeOffset).take(batchSize).toList();
    var examined = 0;
    var downloaded = 0;
    var missing = 0;
    for (final ref in batch) {
      if (BriskersConnectionModeController.instance.forceOffline) break;
      examined++;
      if (ref.localPath.isNotEmpty) {
        final local = File(ref.localPath);
        if (await local.exists() && await local.length() > 0) continue;
      }
      if (await _cache.existing(ref.bucket, ref.key) != null) continue;
      // A failed photo is retried when this bounded cursor cycles back.
      final file = await _cache.getOrDownload(ref.bucket, ref.key);
      if (file == null) {
        missing++;
      } else {
        downloaded++;
      }
    }
    final next = safeOffset + examined;
    await prefs.setInt(cursorKey, next >= total ? 0 : next);
    return OfflineAttachmentMirrorResult(
      examined: examined, downloaded: downloaded,
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

class OfflineAttachmentInventory {
  const OfflineAttachmentInventory({
    required this.known,
    required this.available,
  });

  final int known, available;
  int get missing => known - available;
}
