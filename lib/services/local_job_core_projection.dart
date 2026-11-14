import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import '../local/briskers_local_database.dart';

/// A read/refresh is not an Owner edit. Pending or conflicted local core
/// corrections remain authoritative until their own outbox operation settles.
class LocalJobCoreProjection {
  static Future<Map<String, dynamic>> merge(
    BriskersLocalDatabase db,
    String business,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id']?.toString() ?? '';
    final pending = await db
        .customSelect(
          "SELECT payload_json FROM sync_outbox WHERE business_id=? AND entity_id=? "
          "AND entity_type='job_admin' AND state IN ('pending','conflict')",
          variables: [Variable(business), Variable(id)],
        )
        .get();
    final corePending = pending.any((row) {
      try {
        final payload = jsonDecode(row.read<String>('payload_json'));
        return payload is Map && payload['core_changed'] == true;
      } catch (_) {
        return false;
      }
    });
    if (!corePending) return remote;
    final local = await db
        .customSelect(
          'SELECT * FROM local_jobs WHERE business_id=? AND id=?',
          variables: [Variable(business), Variable(id)],
        )
        .getSingleOrNull();
    if (local == null) return remote;
    return {
      ...remote,
      for (final key in [
        'customer_id',
        'customer_name',
        'vehicle_id',
        'vehicle_vin',
        'vehicle_plate',
        'title',
        'requested_work',
        'planned_hours',
      ])
        key: local.data[key],
      'vehicle': local.data['vehicle_label'],
      '_local_core_pending': true,
    };
  }
}
