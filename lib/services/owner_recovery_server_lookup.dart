import '../core/connection_mode.dart';
import '../core/supabase_config.dart';

/// The only recovery network exception while Force Offline remains enabled.
/// This fixed RPC is authenticated, Owner-authorized and read-only on the server.
/// It never changes connection mode and cannot call an upload API.
class OwnerRecoveryServerLookup {
  Future<Map<String, dynamic>> fetch(Map<String, dynamic> request) async {
    if (!BriskersConnectionModeController.instance.forceOffline) {
      throw StateError('Enable Force Offline before verifying recovery.');
    }
    if (supabase.auth.currentSession == null) {
      throw StateError(
        'An authenticated Owner session is required. No records changed.',
      );
    }
    final result = await supabase.rpc(
      'briskers_owner_recovery_lookup_v1',
      params: request,
    );
    if (!BriskersConnectionModeController.instance.forceOffline) {
      throw StateError('Connection mode changed; recovery was not committed.');
    }
    return Map<String, dynamic>.from(result as Map);
  }
}
