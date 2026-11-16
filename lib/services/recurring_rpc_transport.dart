import '../core/connection_mode.dart';
import '../core/supabase_config.dart';
import 'offline_recurring_repository.dart';

/// The recovery read is the ONLY explicit Force Offline exception here.
/// It does not toggle connection mode or wake the normal sync queue.
class RecurringRpcTransport {
  const RecurringRpcTransport();

  Future<Map<String, dynamic>> readSnapshot(String businessId) async {
    final identity = supabase.auth.currentSession?.user.id;
    if (identity == null) throw StateError('Open the saved shop account first.');
    final data = await supabase.rpc('briskers_recurring_recovery_v1',
      params: {'p_business_id': businessId}).timeout(const Duration(seconds: 45));
    if (supabase.auth.currentSession?.user.id != identity) {
      throw StateError('Account changed during recurring download.');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> writeBundle(String businessId, String operationId,
      RecurringRow rule, List<RecurringRow> occurrences) async {
    final modes = BriskersConnectionModeController.instance;
    modes.ensureNetworkAllowed();
    final revision = modes.revision;
    final identity = supabase.auth.currentSession?.user.id;
    if (identity == null) throw StateError('Open the saved shop account first.');
    final data = await networkSupabase.rpc('briskers_sync_recurring_bundle_v1', params: {
      'p_business_id': businessId, 'p_operation_id': operationId,
      'p_rule': rule, 'p_occurrences': occurrences,
    }).timeout(const Duration(seconds: 45));
    if (supabase.auth.currentSession?.user.id != identity || modes.revision != revision) {
      throw StateError('Account or connection mode changed; changes remain pending.');
    }
    return Map<String, dynamic>.from(data as Map);
  }
}
