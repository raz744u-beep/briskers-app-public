import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/briskers_i18n.dart';
import 'core/connection_mode.dart';
import 'core/supabase_config.dart';
import 'local/local_database_provider.dart';
import 'services/expenseiq_background_scheduler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalDatabase();
  await BriskersLanguageController.instance.initialize();
  await BriskersConnectionModeController.instance.initialize();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  await ExpenseIqBackgroundScheduler.initialize();
  runApp(const BriskersApp());
}
