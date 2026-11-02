import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'briskers_api.dart';

/// Separate from normal invoice/Job deletion, which intentionally preserves
/// estimates. No offline fallback or queued destructive operation is allowed.
class TestJobCleanupGateway {
  const TestJobCleanupGateway();

  Future<void> verifyOwner(String businessId) async {
    final businesses = await const BriskersApi().myBusinesses();
    if (!businesses.any((business) =>
        '${business['business_id'] ?? business['id'] ?? ''}' == businessId &&
        '${business['role_code'] ?? business['role'] ?? ''}' == 'owner')) {
      throw StateError('Owner access required.');
    }
  }

  /// Bounded Owner-only lightweight discovery. Never fetch the full 5k+
  /// Jobs RPC merely to populate a deletion preview.
  Future<List<Map<String, dynamic>>> jobs(String businessId) async {
    final raw = await networkSupabase.rpc(
      'briskers_test_job_cleanup_candidates_v1',
      params: {'p_business_id': businessId},
    );
    return List<dynamic>.from(raw as List)
        .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> preview(String businessId, String jobId) async =>
      Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_test_job_cleanup_preview_v1',
        params: {'p_business_id': businessId, 'p_job_id': jobId},
      ) as Map);

  Future<Map<String, dynamic>> execute(
    String businessId,
    String jobId, {
    required String fingerprint,
    required String confirmation,
  }) async => Map<String, dynamic>.from(await networkSupabase.rpc(
    'briskers_test_job_cleanup_execute_v1',
    params: {
      'p_business_id': businessId,
      'p_job_id': jobId,
      'p_expected_fingerprint': fingerprint,
      'p_test_confirmation': confirmation,
    },
  ) as Map);

  Future<Map<String, dynamic>> tombstones(String businessId) async {
    try {
      return Map<String, dynamic>.from(await networkSupabase.rpc(
        'briskers_test_job_cleanup_tombstones_v1',
        params: {'p_business_id': businessId},
      ) as Map);
    } on PostgrestException catch (error) {
      // Compatible before the atomic cleanup migration is installed. Do not
      // suppress network, authorization or malformed-response failures.
      if (error.code == 'PGRST202' &&
          error.message.contains('briskers_test_job_cleanup_tombstones_v1')) {
        return {
          'schema_version': 1, 'business_id': businessId,
          'deleted_job_ids': <String>[], 'deleted_document_ids': <String>[],
        };
      }
      rethrow;
    }
  }
}
