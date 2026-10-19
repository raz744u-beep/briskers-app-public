import 'dart:async';
import 'dart:math';
import '../core/supabase_config.dart';
import '../local/briskers_local_database.dart';
import '../local/local_database_provider.dart';
import 'local_job_deletion_v3.dart';
import 'local_sync_status_repository.dart';
import 'offline_job_purge.dart';
import 'owner_job_deletion_v3_contract.dart';

class LocalPurgeRegistrationGateway {
  const LocalPurgeRegistrationGateway();
  void assertActor(String actor) {
    if (supabase.auth.currentUser?.id != actor) throw StateError('Account access changed.');
  }
  Future<Map<String, dynamic>> register(String business, String job,
      String operation, Map<String, dynamic> confirmation) async =>
    Map<String, dynamic>.from(await networkSupabase.rpc('briskers_job_delete_register_local_v3',
      params: {'p_business_id': business, 'p_job_id': job,
        'p_operation_id': operation, 'p_confirmation': confirmation}) as Map);
}

class OwnerLocalJobPurgeService {
  OwnerLocalJobPurgeService({BriskersLocalDatabase? database,
    LocalPurgeRegistrationGateway gateway = const LocalPurgeRegistrationGateway()})
    : _db = database ?? localDatabase, _gateway = gateway;
  final BriskersLocalDatabase _db;
  final LocalPurgeRegistrationGateway _gateway;
  static final _flights = Expando<Map<String, Future<void>>>('local_job_cancellation_registration');

  Future<OfflineJobPurgePreview?> eligiblePreview(String business, String job,
      {required String actorId, required bool isOwner}) async {
    if (!isOwner) throw StateError('Only the Owner can delete a Job.');
    _gateway.assertActor(actorId);
    try {
      return await OfflineJobPurge.preview(_db, businessId: business,
        jobId: job, actorId: actorId, isOwner: isOwner);
    } on OfflineJobPurgeNeedsReconciliation {
      // Failure to prove local absence never authorizes erasure. The caller may
      // still offer a normal authoritative server preview, with its own fences.
      return null;
    }
  }

  Future<LocalDeletionCleanupResult> confirm(OfflineJobPurgePreview preview,
      {required String actorId, required bool isOwner, required bool online}) async {
    if (!isOwner) throw StateError('Only the Owner can delete a Job.');
    _gateway.assertActor(actorId);
    final result = await OfflineJobPurge.confirm(_db, preview,
      operationId: _operationId(), actorId: actorId, isOwner: isOwner);
    LocalSyncStatusRepository.notifyStateChanged(preview.businessId);
    if (online) await flushRegistrations(preview.businessId, actorId: actorId, isOwner: isOwner);
    return result;
  }

  Future<void> flushRegistrations(String business,
      {required String actorId, required bool isOwner}) {
    if (!isOwner) return Future<void>.value();
    final flights = _flights[_db] ??= {};
    final key = '$business/$actorId';
    return flights[key] ??= _flush(business, actorId).whenComplete(() { flights.remove(key); });
  }

  Future<void> _flush(String business, String actor) async {
    _gateway.assertActor(actor);
    final rows = await OfflineJobPurge.pendingRegistrations(_db, business, actor);
    for (final row in rows) {
      try {
        _gateway.assertActor(actor);
        final confirmation = Map<String, dynamic>.from(row['confirmation'] as Map);
        final operation = row['operation_id'] as String;
        final receipt = await _gateway.register(business, row['job_id'] as String,
          operation, confirmation).timeout(const Duration(seconds: 25));
        _gateway.assertActor(actor);
        validateDeletionV3Receipt(receipt, confirmation, operation);
        if (receipt['status'] != 'deleted' || receipt['storage_cleanup'] != 'not_required') {
          throw const FormatException('Local cancellation registration was not completed.');
        }
        await LocalJobDeletionV3.applyVerifiedReceipt(_db, receipt: receipt);
        await OfflineJobPurge.acknowledgeRegistration(_db, business, operation);
        LocalSyncStatusRepository.notifyStateChanged(business);
      } catch (_) {
        // Timeout, missing deployment, or remote existence all retain the SAME
        // durable operation. Never turn this refusal into permission to delete
        // a server record or manufacture a replacement operation.
      }
    }
  }
}

String _operationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
}
