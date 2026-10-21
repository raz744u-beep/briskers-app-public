import 'dart:convert';

import 'package:drift/drift.dart' show Variable;

import '../core/connection_mode.dart';
import '../core/mileage_workflow.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'briskers_api.dart';
import 'local_job_quarantine.dart';

/// A dedicated Mileage Out queue, separate from Job arrival odometer and
/// from existing document memo/line queues. Enabled only on v2 invoices.
///
/// Queued values always project over cached server detail; server failures
/// retain the row and its original revision for safe replay after restart.
class OfflineInvoiceMileageService {
  OfflineInvoiceMileageService({
    BriskersLocalDatabase? database,
    BriskersApi api = const BriskersApi(),
  }) : _database = database ?? localDatabase,
       _api = api;

  final BriskersLocalDatabase _database;
  final BriskersApi _api;
  static const _type = 'invoice_mileage_out';

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

  Future<void> queue(
    String businessId,
    String invoiceId, {
    required int expectedVersion,
    required num? mileageOut,
  }) async {
    if (invoiceId.isEmpty || invoiceId.startsWith('local-')) {
      throw StateError('This invoice needs a permanent ID before Mileage Out sync.');
    }
    if (expectedVersion < 1) throw StateError('Missing server invoice revision.');
    if (mileageOut != null && MileageWorkflow.parse(mileageOut) == null) {
      throw ArgumentError.value(mileageOut,'mileageOut','Invalid whole miles.');
    }
    await _database.transaction(() async {
      final queued = await _database.customSelect(
        """SELECT id,attempt_count,state,payload_json
           FROM sync_outbox WHERE business_id=? AND entity_id=?
           AND entity_type=? ORDER BY id""",
        variables: [Variable<String>(businessId),Variable<String>(invoiceId),
          const Variable<String>(_type)],
      ).get();
      final payload = jsonEncode({
        'mileage_out': mileageOut,
        'expected_version': expectedVersion,
      });
      if (queued.length > 1) {
        throw StateError('Multiple mileage edits need review before replay.');
      }
      if (queued.isNotEmpty) {
        final existing = queued.single;
        if (existing.read<String>('state') != 'pending' ||
            existing.read<int>('attempt_count') > 0) {
          final previous = jsonDecode(existing.read<String>('payload_json')) as Map;
          if (MileageWorkflow.parse(previous['mileage_out']) == mileageOut) return;
          throw StateError('Earlier Mileage Out is awaiting sync; do not overwrite it.');
        }
        await _database.customStatement(
          "UPDATE sync_outbox SET payload_json=?,base_row_version=?,last_error=NULL WHERE id=?",
          [payload,expectedVersion,existing.read<int>('id')],
        );
      } else {
        await _database.customStatement(
          """INSERT INTO sync_outbox(
             business_id,entity_type,entity_id,operation,payload_json,
             base_row_version,state,attempt_count,created_at
           ) VALUES (?,?,?,'update',?,?,'pending',0,?)""",
          [businessId,_type,invoiceId,payload,expectedVersion,_now()],
        );
      }
    });
  }

  Future<Map<String,dynamic>> project(
    String businessId, String invoiceId, Map<String,dynamic> detail,
  ) async {
    if (detail['kind'] != 'invoice' ||
        detail['mileage_schema_version'] != 2) {
      return detail;
    }
    final queued = await _database.customSelect(
      """SELECT payload_json,state FROM sync_outbox
         WHERE business_id=? AND entity_type=? AND entity_id=?
         AND state IN ('pending','conflict') ORDER BY id DESC LIMIT 1""",
      variables: [Variable<String>(businessId),
        const Variable<String>(_type),Variable<String>(invoiceId)],
    ).get();
    if (queued.isEmpty) return detail;
    final payload=jsonDecode(queued.single.read<String>('payload_json')) as Map;
    return {
      ...detail,
      'mileage_out': payload['mileage_out'],
      'mileage_out_sync_state': queued.single.read<String>('state'),
    };
  }

  /// Run after reconnection or a foreground save. A missing v2 RPC cannot
  /// silently convert this edit into legacy odometer_in.
  Future<void> flush(String businessId) async {
    if (BriskersConnectionModeController.instance.forceOffline) return;
    final rows=await _database.customSelect(
      """SELECT * FROM sync_outbox WHERE business_id=?
         AND entity_type=? AND state='pending' ORDER BY id""",
      variables:[Variable<String>(businessId),const Variable<String>(_type)],
    ).get();
    for (final item in rows) {
      final id=item.read<int>('id');
      final invoiceId=item.read<String>('entity_id');
      final payload=jsonDecode(item.read<String>('payload_json')) as Map;
      final version=item.readNullable<int>('base_row_version');
      if (version == null) return;
      try {
        await LocalJobQuarantine.assertReplayAllowed(
          _database,businessId,outboxId:id,
        );
        final fresh=await _database.customSelect(
          """SELECT id FROM sync_outbox WHERE id=? AND business_id=?
             AND entity_type=? AND state='pending' LIMIT 1""",
          variables:[Variable<int>(id),Variable<String>(businessId),
            const Variable<String>(_type)],
        ).get();
        if (fresh.isEmpty) continue;
        final desired=MileageWorkflow.parse(payload['mileage_out']);
        try {
          await LocalJobQuarantine.guardReplay(
            _database,businessId,
            () => _api.saveInvoiceMileageOut(
              businessId,invoiceId,expectedVersion:version,
              mileageOut: desired,
            ),
            outboxId:id,
          );
        } catch (error) {
          // The response may have been lost after a successful commit. Only
          // authoritative v5 document data can prove that exact write.
          final server=await _api.documentDetail(businessId,invoiceId);
          if (server['id']?.toString()!=invoiceId ||
              server['mileage_schema_version']!=2 ||
              MileageWorkflow.parse(server['mileage_out'])!=desired) {
            rethrow;
          }
        }
        await _database.transaction(() async {
          await LocalJobQuarantine.assertReplayAllowed(
            _database,businessId,outboxId:id,
          );
          await _database.customStatement(
            "DELETE FROM sync_outbox WHERE id=? AND business_id=? AND entity_type=?",
            [id,businessId,_type],
          );
        });
      } catch (error) {
        await _database.customStatement(
          """UPDATE sync_outbox SET attempt_count=attempt_count+1,
             last_attempt_at=?,last_error=? WHERE id=? AND business_id=?""",
          [_now(),error.toString(),id,businessId],
        );
        break;
      }
    }
  }
}
