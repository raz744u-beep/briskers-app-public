import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/supabase_config.dart';
import 'package:briskers_app/services/job_sync_service.dart';

void main() {
  test('normal Briskers app never enables destructive v3 sync', () {
    if (!isSyntheticTestBuild) {
      expect(supabaseUrl, productionSupabaseUrl);
      expect(JobSyncService.deletionFeedEnabled, isFalse);
    }
  });

  test('synthetic mode cannot fall back to production endpoint', () {
    if (isSyntheticTestBuild) {
      expect(supabaseUrl, syntheticSandboxUrl);
      expect(supabaseUrl, isNot(productionSupabaseUrl));
    }
  });

  test('synthetic app identity cannot collide with regular shop app', () {
    expect(syntheticAndroidAppId, isNot('com.briskers.briskers_app'));
    if (isSyntheticTestBuild) {
      expect(
        () => verifySyntheticAppIdentity('com.briskers.briskers_app'),
        throwsStateError,
      );
      expect(
        () => verifySyntheticAppIdentity(syntheticAndroidAppId),
        returnsNormally,
      );
    }
  });

  test('unconfigured synthetic app must fail before initialization', () {
    if (isSyntheticTestBuild && supabasePublishableKey.isEmpty) {
      expect(verifySupabaseEnvironment, throwsStateError);
    }
  });
}
