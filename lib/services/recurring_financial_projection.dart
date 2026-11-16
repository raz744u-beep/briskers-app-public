import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'local_financial_cache.dart';
import 'local_financial_totals_journal.dart';
import 'offline_recurring_repository.dart';

/// Writes recurring records into the real expense list/detail and totals journal.
/// Called only inside the recurrence repository's SQLite transaction.
class RecurringFinancialProjection {
  const RecurringFinancialProjection(this.businessId);
  final String businessId;

  static String _identity(RecurringRow row) =>
      OfflineRecurringRepository.occurrenceKey(
        row['recurring_rule_id'] as String,
        row['recurring_occurrence_date'] as String,
      );

  Future<void> call(BriskersLocalDatabase database,
      RecurringRow? before, RecurringRow after) async {
    if (after['business_id'] != businessId ||
        (before != null && before['business_id'] != businessId)) {
      throw StateError('Recurring projection business mismatch.');
    }
    final cache = LocalFinancialCache(database: database);
    final journal = LocalFinancialTotalsJournal(database: database);
    final id = after['id'] as String;
    final oldId = before?['id'] as String? ?? id;
    final rows = await cache.loadTransactions(businessId);
    final matches = rows.where((row) => row['id'] == oldId || row['id'] == id ||
        (row['recurring_rule_id'] != null &&
         row['recurring_occurrence_date'] != null && _identity(row) == _identity(after)))
        .toList();
    if (matches.any((row) => row['id'] != id && row['id'] != oldId)) {
      throw StateError('Another expense already claims this occurrence.');
    }
    final existing = await cache.loadTransactionDetail(businessId, oldId);
    final destination = oldId == id ? existing :
        await cache.loadTransactionDetail(businessId, id);
    if ((existing?['sync_state'] == 'pending' ||
         destination?['sync_state'] == 'pending') &&
        (existing?['recurring_engine_owned'] != true &&
         destination?['recurring_engine_owned'] != true)) {
      throw StateError('An existing expense has pending local changes.');
    }
    final pending = after['_state'] == 'pending' || after['_state'] == 'conflict';
    final amount = (after['amount_minor'] as int) / 100;
    final attachments = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final source in [existing, destination, after]) {
      for (final raw in (source?['attachments'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final photo = Map<String, dynamic>.from(raw);
        final key = photo['id']?.toString() ?? photo['attachment_id']?.toString() ?? photo['local_file_path']?.toString() ?? photo['storage_key']?.toString() ?? jsonEncode(photo);
        if (!seen.add(key)) continue;
        attachments.add({...photo, 'transaction_id': id});
      }
    }
    final detail = <String, dynamic>{
      ...?existing,
      ...?destination,
      for (final entry in after.entries)
        if (!entry.key.startsWith('_')) entry.key: entry.value,
      'id': id, 'business_id': businessId,
      'amount': amount,
      'signed_amount': after['direction'] == 'expense' ? -amount : amount,
      'transaction_date': after['date'],
      'counterparty_id': after['vendor_id'],
      'recurring': true,
      'recurring_engine_owned': true,
      // Keeps the record through ordinary limited-list refreshes.
      'recurring_verified_download': !pending,
      'sync_state': pending ? 'pending' : 'synced',
      'attachments': attachments,
      'receipt_count': attachments.length,
      'editable': true,
      'deletable': false,
    };
    final pendingMetadata = await database.customSelect('''
      SELECT id FROM sync_outbox WHERE business_id=?
      AND entity_type='financial_receipt_extraction' AND state='pending'
      AND entity_id IN (?,?) LIMIT 1
    ''', variables: [Variable<String>(businessId),Variable<String>(oldId),Variable<String>(id)]).get();
    if (pendingMetadata.isNotEmpty && existing != null) {
      for (final field in ['receipt_extraction','receipt_details','receipt_items']) {
        if (existing.containsKey(field)) detail[field] = existing[field];
      }
    }
    if (detail['receipt_details'] is Map) {
      detail['receipt_details'] = {
        ...Map<String, dynamic>.from(detail['receipt_details'] as Map),
        'transaction_id': id,
      };
    }
    if (detail['receipt_items'] is List) {
      detail['receipt_items'] = [
        for (final item in detail['receipt_items'] as List)
          if (item is Map) {...item, 'transaction_id': id},
      ];
    }
    if (oldId != id) {
      await journal.remap(businessId, 'transaction:$oldId', 'transaction:$id',
        newTransactionId: id);
      final queued = await database.customSelect('''
        SELECT id,entity_type,payload_json FROM sync_outbox
        WHERE business_id=? AND entity_type IN
          ('financial_photo','financial_receipt_extraction') AND state='pending'
      ''', variables: [Variable<String>(businessId)]).get();
      for (final queue in queued) {
        final payload = Map<String, dynamic>.from(
          jsonDecode(queue.read<String>('payload_json')) as Map);
        if (payload['transaction_id'] != oldId) continue;
        payload['transaction_id'] = id;
        await database.customStatement('''
          UPDATE sync_outbox SET payload_json=?,
            entity_id=CASE WHEN entity_type='financial_receipt_extraction'
              THEN ? ELSE entity_id END WHERE business_id=? AND id=?
        ''', [jsonEncode(payload), id, businessId, queue.read<int>('id')]);
      }
      await database.customStatement('''
        DELETE FROM local_financial_cache WHERE business_id=? AND cache_key=?
      ''', [businessId, 'transaction_detail_$oldId']);
    }
    await cache.saveTransactionDetail(businessId, id, detail);
    await cache.saveTransactions(businessId, [
      for (final row in rows)
        if (!matches.contains(row)) row,
      detail,
    ]);
    if (pending || existing?['sync_state'] == 'pending') {
      await journal.record(businessId, 'transaction:$id',
        before: before == null ? null : {
          ...before, 'id': id,
          'amount': (before['amount_minor'] as int) / 100,
          'transaction_date': before['date'],
          'counterparty_id': before['vendor_id'],
        }, after: detail);
    }
    // A read/ack is not a full-period totals baseline. Keep existing deltas until
    // reconcileAndSaveBaseline proves the canonical record is included.
  }
}
