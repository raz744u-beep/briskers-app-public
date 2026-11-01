import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/briskers_i18n.dart';
import 'core/connection_mode.dart';
import 'core/supabase_config.dart';
import 'local/local_database_provider.dart';
import 'services/expenseiq_background_scheduler.dart';
import 'services/local_owner_security.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail before opening a local DB or network session when a TEST build is
  // missing its independent sandbox publishable key.
  verifySupabaseEnvironment();
  if (isSyntheticTestBuild) {
    final package = await PackageInfo.fromPlatform();
    verifySyntheticAppIdentity(package.packageName);
  }
  await initializeLocalDatabase();
  await BriskersLanguageController.instance.initialize();
  await BriskersConnectionModeController.instance.initialize();
  // An enrolled Owner always starts local-only. Synchronization is a
  // separate, explicitly enabled workflow and must not begin at startup.
  if (isSyntheticTestBuild ||
      await LocalOwnerSecurity.instance.isConfigured) {
    await BriskersConnectionModeController.instance
        .setMode(BriskersConnectionMode.offline);
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  // A synthetic testing app must never run the production ExpenseIQ importer.
  if (!isSyntheticTestBuild) {
    await ExpenseIqBackgroundScheduler.initialize();
  }
  runApp(const BriskersApp());
}
