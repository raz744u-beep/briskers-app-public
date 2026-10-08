import 'package:drift/drift.dart' show Variable;
import 'package:saf/saf.dart';

import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';

class ExpenseIqIndexResult {
  const ExpenseIqIndexResult(this.matched, this.missing);
  final int matched;
  final int missing;
}

class ExpenseIqSyncCounts {
  const ExpenseIqSyncCounts({
    required this.indexed,
    required this.pending,
    required this.uploaded,
    required this.failed,
    required this.missing,
    required this.uploading,
    required this.enabled,
    required this.wifiOnly,
  });
  final int indexed, pending, uploaded, failed, missing, uploading;
  final bool enabled, wifiOnly;
}

class ExpenseIqBatchResult {
  const ExpenseIqBatchResult({
    required this.uploaded,
    required this.failed,
    required this.hasPending,
    this.loginRequired = false,
  });
  final int uploaded, failed;
  final bool hasPending, loginRequired;
}

/// All photo-to-transaction links are durable in SQLite. Original photos
/// remain untouched in the ExpenseIQ folder. SAF URI permissions must persist
/// across restarts; the user should not move/delete the source folder.
class ExpenseIqLocalPhotoSync {
  ExpenseIqLocalPhotoSync({
    BriskersApi api = const BriskersApi(),
    BriskersLocalDatabase? database,
    Saf? saf,
  })  : _api = api,
        _database = database ?? localDatabase,
        _saf = saf ?? Saf();

  final BriskersApi _api;
  final BriskersLocalDatabase _database;
  final Saf _saf;
  static const _table = 'local_expense_iq_photos';

  String _photoKey(String filename) {
    final lower = filename.trim().toLowerCase();
    if (lower.endsWith('.jpeg')) {
      return lower.substring(0, lower.length - 5);
    }
    if (lower.endsWith('.jpg')) {
      return lower.substring(0, lower.length - 4);
    }
    return '';
  }

  /// Index file references in small, restart-safe SQLite transactions.
  ///
  /// Previous versions tried ~10,000 statements in one transaction, leaving
  /// slower phones showing no progress for extended periods. Committed batches
  /// survive interruption and can safely be resumed with another scan.
  Future<ExpenseIqIndexResult> indexPhotos(
    String businessId, {
    required List<Map<String, dynamic>> candidates,
    required List<Map<String, dynamic>> files,
    void Function(int processed, int total)? onProgress,
  }) async {
    final byKey = <String, Map<String, dynamic>>{};
    for (final file in files) {
      final key = _photoKey(file['name']?.toString() ?? '');
      if (key.isNotEmpty) byKey[key] = file;
    }

    final items = <List<Object?>>[];
    final seenTransactions = <String>{};
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    var matched = 0;
    var missing = 0;
    for (final candidate in candidates) {
      final transactionId = candidate['transaction_id']?.toString() ?? '';
      final photoId = candidate['photo_id']?.toString().trim().toLowerCase() ?? '';
      if (transactionId.isEmpty ||
          photoId.isEmpty ||
          !seenTransactions.add(transactionId)) {
        continue;
      }
      final file = byKey[photoId];
      final uri = file?['uri']?.toString();
      final filename = file?['name']?.toString() ?? '$photoId.jpg';
      if (uri == null || uri.isEmpty) {
        missing++;
      } else {
        matched++;
      }
      items.add([
        businessId,
        transactionId,
        photoId,
        filename,
        uri,
        uri == null || uri.isEmpty ? 'missing' : 'pending',
        now,
      ]);
    }

    await _database.customStatement(
      '''
      INSERT OR IGNORE INTO local_expense_iq_sync_settings
        (business_id, enabled, wifi_only)
      VALUES (?, 1, 1)
      ''',
      [businessId],
    );
    onProgress?.call(0, items.length);
    const batchSize = 100;
    const upsertSql = '''
      INSERT INTO $_table
        (business_id, transaction_id, photo_id, filename, source_uri,
         state, attempts, claimed_at, last_error, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, NULL, NULL, ?)
      ON CONFLICT(business_id, transaction_id) DO UPDATE SET
        photo_id=excluded.photo_id,
        filename=CASE WHEN excluded.source_uri IS NOT NULL
                      THEN excluded.filename ELSE $_table.filename END,
        source_uri=coalesce(excluded.source_uri, $_table.source_uri),
        state=CASE
          WHEN $_table.state='uploaded' THEN 'uploaded'
          WHEN coalesce(excluded.source_uri,$_table.source_uri) IS NULL
            THEN 'missing'
          WHEN $_table.state='uploading' THEN 'uploading'
          ELSE 'pending'
        END,
        attempts=CASE
          WHEN $_table.state='uploaded' THEN $_table.attempts
          ELSE 0
        END,
        updated_at=excluded.updated_at
    ''';
    for (var offset = 0; offset < items.length; offset += batchSize) {
      final end = offset + batchSize < items.length
          ? offset + batchSize
          : items.length;
      await _database.batch((batch) {
        for (final values in items.sublist(offset, end)) {
          batch.customStatement(upsertSql, values);
        }
      });
      onProgress?.call(end, items.length);
      // Yield between committed batches so the screen can paint progress.
      await Future<void>.delayed(Duration.zero);
    }
    return ExpenseIqIndexResult(matched, missing);
  }

  Future<ExpenseIqSyncCounts> counts(String businessId) async {
    final rows = await _database.customSelect(
      '''
      SELECT state, COUNT(*) AS quantity FROM $_table
      WHERE business_id = ? GROUP BY state
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    final values = <String, int>{
      for (final row in rows)
        row.read<String>('state'): row.read<int>('quantity'),
    };
    final options = await _database.customSelect(
      '''
      SELECT enabled, wifi_only FROM local_expense_iq_sync_settings
      WHERE business_id = ? LIMIT 1
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    final enabled = options.isEmpty || options.first.read<int>('enabled') == 1;
    final wifiOnly = options.isEmpty || options.first.read<int>('wifi_only') == 1;
    return ExpenseIqSyncCounts(
      indexed: values.values.fold<int>(0, (a, b) => a + b),
      pending: values['pending'] ?? 0,
      uploaded: values['uploaded'] ?? 0,
      failed: values['failed'] ?? 0,
      missing: values['missing'] ?? 0,
      uploading: values['uploading'] ?? 0,
      enabled: enabled,
      wifiOnly: wifiOnly,
    );
  }

  Future<void> setOptions(
    String businessId, {
    bool? enabled,
    bool? wifiOnly,
  }) async {
    final previous = await counts(businessId);
    await _database.customStatement(
      '''
      INSERT INTO local_expense_iq_sync_settings
        (business_id, enabled, wifi_only)
      VALUES (?, ?, ?)
      ON CONFLICT(business_id) DO UPDATE SET
        enabled=excluded.enabled,
        wifi_only=excluded.wifi_only
      ''',
      [
        businessId,
        (enabled ?? previous.enabled) ? 1 : 0,
        (wifiOnly ?? previous.wifiOnly) ? 1 : 0,
      ],
    );
  }

  Future<Map<String, dynamic>?> localForExpense(
    String businessId,
    String transactionId,
  ) async {
    final rows = await _database.customSelect(
      '''
      SELECT filename, source_uri, state, last_error
      FROM $_table
      WHERE business_id = ? AND transaction_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(transactionId),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data;
  }

  Future<ExpenseIqBatchResult> uploadBatch(
    String businessId, {
    int maxPhotos = 25,
  }) async {
    if (maxPhotos < 1 || maxPhotos > 100) {
      throw ArgumentError.value(maxPhotos, 'maxPhotos');
    }
    final settings = await counts(businessId);
    if (!settings.enabled) {
      return const ExpenseIqBatchResult(
        uploaded: 0, failed: 0, hasPending: false,
      );
    }
    // Supabase sessions are loaded from its persistent secure local storage
    // inside the workmanager Flutter engine. No auth token is copied to jobs.
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    // A unique microsecond lease prevents concurrent workers from freeing
    // one another's in-flight rows within the same wall-clock second.
    final claimToken = DateTime.now().toUtc().microsecondsSinceEpoch;
    final claimed = <Map<String, dynamic>>[];
    await _database.transaction(() async {
      final rows = await _database.customSelect(
        '''
        SELECT transaction_id, filename, source_uri, attempts
        FROM $_table WHERE business_id = ?
          AND source_uri IS NOT NULL
          AND (
            state='pending'
            OR (state='failed' AND attempts < 5
                AND updated_at < ?)
            OR (state='uploading' AND claimed_at < ?)
          )
        ORDER BY CASE state WHEN 'pending' THEN 0 ELSE 1 END,
                 updated_at, transaction_id
        LIMIT ?
        ''',
        variables: [
          Variable<String>(businessId),
          Variable<int>(now - 120),
          Variable<int>(claimToken - 1200 * 1000000),
          Variable<int>(maxPhotos),
        ],
      ).get();
      for (final row in rows) {
        claimed.add(Map<String, dynamic>.from(row.data));
        await _database.customStatement(
          '''
          UPDATE $_table SET state='uploading', claimed_at=?, updated_at=?
          WHERE business_id=? AND transaction_id=?
          ''',
          [claimToken, now, businessId, row.read<String>('transaction_id')],
        );
      }
    });
    if (claimed.isEmpty) {
      return const ExpenseIqBatchResult(
        uploaded: 0, failed: 0, hasPending: false,
      );
    }

    // A worker may have been killed just after the cloud accepted an upload.
    // Check finalized cloud attachments before retrying a claimed photo.
    Set<String> alreadyUploaded;
    try {
      alreadyUploaded = await _api.uploadedExpenseIqTransactions(
        businessId,
        claimed.map((row) => row['transaction_id'].toString()),
      );
    } catch (_) {
      for (final row in claimed) {
        await _database.customStatement(
          '''
          UPDATE $_table SET state='pending', claimed_at=NULL
          WHERE business_id=? AND transaction_id=?
            AND state='uploading'
          ''',
          [businessId, row['transaction_id']],
        );
      }
      rethrow;
    }

    var uploaded = 0, failed = 0, sequentialFailures = 0;
    for (final row in claimed) {
      // Switches on the Expenses screen pause safely between photos.
      if (!(await counts(businessId)).enabled) break;
      final transactionId = row['transaction_id']?.toString() ?? '';
      final filename = row['filename']?.toString() ?? 'receipt.jpg';
      if (alreadyUploaded.contains(transactionId)) {
        await _markUploaded(businessId, transactionId);
        uploaded++;
        continue;
      }
      try {
        final uri = row['source_uri']?.toString() ?? '';
        if (uri.isEmpty) throw StateError('Original photo URI is missing.');
        final bytes = await _saf.readFileBytes(uri);
        if (bytes.isEmpty) throw StateError('Original photo is empty.');
        await _api.uploadExpensePhoto(
          businessId, transactionId,
          filename: filename,
          mimeType: 'image/jpeg',
          bytes: bytes,
        );
        await _markUploaded(businessId, transactionId);
        uploaded++;
        sequentialFailures = 0;
      } catch (error) {
        failed++;
        sequentialFailures++;
        await _database.customStatement(
          '''
          UPDATE $_table
          SET state='failed', attempts=attempts+1,
              claimed_at=NULL, last_error=?, updated_at=?
          WHERE business_id=? AND transaction_id=?
          ''',
          [
            error.toString(),
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
            businessId, transactionId,
          ],
        );
      }
      if (sequentialFailures >= 5) break;
    }

    // Release unattempted claims, including after a run of failures.
    await _database.customStatement(
      '''
      UPDATE $_table SET state='pending', claimed_at=NULL
      WHERE business_id=? AND state='uploading' AND claimed_at=?
      ''',
      [businessId, claimToken],
    );
    final remaining = await _database.customSelect(
      '''
      SELECT COUNT(*) AS quantity FROM $_table
      WHERE business_id=? AND state='pending'
      ''',
      variables: [Variable<String>(businessId)],
    ).getSingle();
    return ExpenseIqBatchResult(
      uploaded: uploaded,
      failed: failed,
      hasPending: sequentialFailures < 5 &&
          remaining.read<int>('quantity') > 0,
    );
  }

  Future<void> _markUploaded(
    String businessId,
    String transactionId,
  ) async {
    await _database.customStatement(
      '''
      UPDATE $_table
      SET state='uploaded', last_error=NULL, claimed_at=NULL, updated_at=?
      WHERE business_id=? AND transaction_id=?
      ''',
      [
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
        businessId, transactionId,
      ],
    );
  }
}
