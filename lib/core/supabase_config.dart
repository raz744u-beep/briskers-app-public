import 'connection_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'briskers_environment.dart';

SupabaseClient get supabase => Supabase.instance.client;

SupabaseClient get networkSupabase {
  BriskersConnectionModeController.instance.ensureNetworkAllowed();
  return Supabase.instance.client;
}
