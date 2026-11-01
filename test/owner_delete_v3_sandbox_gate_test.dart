import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/core/supabase_config.dart';
import 'package:briskers_app/services/job_sync_service.dart';

void main() {
  test('deletion feed flag cannot enable production builds', () {
    const requested = bool.fromEnvironment(
      'BRISKERS_OWNER_DELETE_V3_FEED', defaultValue: false,
    );
    expect(JobSyncService.deletionFeedEnabled, isSyntheticTestBuild && requested);
    if (!isSyntheticTestBuild) {
      expect(JobSyncService.deletionFeedEnabled, isFalse);
    }
  });

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

  test('synthetic app rejects placeholder and production publishable keys', () {
    if (!isSyntheticTestBuild) return;
    const rejected = {
      '',
      'sb_publishable_',
      'sb_publishable_ci_placeholder',
      'sb_publishable_placeholder',
      'sb_publishable_test',
      productionSupabasePublishableKey,
    };
    if (rejected.contains(supabasePublishableKey) ||
        supabasePublishableKey.length < 30 ||
        !supabasePublishableKey.startsWith('sb_publishable_')) {
      expect(verifySupabaseEnvironment, throwsStateError);
    } else {
      expect(verifySupabaseEnvironment, returnsNormally);
    }
  });
}
