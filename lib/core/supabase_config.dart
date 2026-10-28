import 'connection_mode.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The regular shop app ALWAYS uses its existing production configuration.
// A synthetic test build uses a different Supabase project and MUST receive
// its own publishable key at build time; no fallback to production is allowed.
const isSyntheticTestBuild = bool.fromEnvironment(
  'BRISKERS_SYNTHETIC_BUILD', defaultValue: false,
);
const productionSupabaseUrl = 'https://coensavcnuwuqaeszohb.supabase.co';
const syntheticSandboxUrl = 'https://tjptzpgnpqwzhsbrzwpo.supabase.co';
const supabaseUrl =
    isSyntheticTestBuild ? syntheticSandboxUrl : productionSupabaseUrl;
const supabasePublishableKey = isSyntheticTestBuild
    ? String.fromEnvironment('BRISKERS_SYNTHETIC_PUBLISHABLE_KEY')
    : 'sb_publishable_tY4v9OoY0nkbeFl-5cnGbA_FoWzD9aP';

const syntheticAndroidAppId = 'com.briskers.briskers_test';

void verifySyntheticAppIdentity(String actualPackageId) {
  if (isSyntheticTestBuild && actualPackageId != syntheticAndroidAppId) {
    throw StateError(
      'Briskers TEST must be installed as a separate application. '
      'The regular shop app cannot be used for synthetic deletion tests.',
    );
  }
}

void verifySupabaseEnvironment() {
  if (isSyntheticTestBuild &&
      (supabaseUrl != syntheticSandboxUrl ||
          supabasePublishableKey.isEmpty ||
          !supabasePublishableKey.startsWith('sb_publishable_'))) {
    throw StateError('Invalid isolated Briskers TEST configuration.');
  }
}

SupabaseClient get supabase => Supabase.instance.client;

SupabaseClient get networkSupabase {
  BriskersConnectionModeController.instance.ensureNetworkAllowed();
  return Supabase.instance.client;
}
