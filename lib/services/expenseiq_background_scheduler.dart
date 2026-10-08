import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../core/supabase_config.dart';
import '../local/local_database_provider.dart';
import 'expenseiq_local_photo_sync.dart';

const expenseIqBackgroundTaskName = 'briskers.expenseiq.photo.upload';

/// A WorkManager task runs in a headless Flutter engine and isolate.
/// The app's persisted Supabase session is reused; no credentials in task data.
@pragma('vm:entry-point')
void expenseIqPhotoCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != expenseIqBackgroundTaskName) return true;
    final businessId = inputData?['businessId']?.toString() ?? '';
    if (businessId.isEmpty) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await initializeLocalDatabase();
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );
      if (Supabase.instance.client.auth.currentSession == null) {
        return false;
      }
      final sync = ExpenseIqLocalPhotoSync();
      final result = await sync.uploadBatch(businessId);
      if (result.hasPending && result.uploaded > 0) {
        await ExpenseIqBackgroundScheduler.scheduleNext(businessId);
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}

class ExpenseIqBackgroundScheduler {
  const ExpenseIqBackgroundScheduler._();

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    await Workmanager().initialize(expenseIqPhotoCallbackDispatcher);
  }

  static Future<Constraints> _constraints(String businessId) async {
    final counts = await ExpenseIqLocalPhotoSync().counts(businessId);
    return Constraints(
      networkType:
          counts.wifiOnly ? NetworkType.unmetered : NetworkType.connected,
    );
  }

  static Future<void> schedule(String businessId) async {
    if (!Platform.isAndroid) return;
    final counts = await ExpenseIqLocalPhotoSync().counts(businessId);
    if (!counts.enabled || counts.pending + counts.failed == 0) return;
    await Workmanager().registerPeriodicTask(
      'expenseiq-periodic-$businessId',
      expenseIqBackgroundTaskName,
      frequency: const Duration(minutes: 15),
      inputData: {'businessId': businessId},
      constraints: await _constraints(businessId),
    );
    await scheduleNext(businessId);
  }

  static Future<void> scheduleNext(String businessId) async {
    if (!Platform.isAndroid) return;
    final counts = await ExpenseIqLocalPhotoSync().counts(businessId);
    if (!counts.enabled || counts.pending + counts.failed == 0) return;
    await Workmanager().registerOneOffTask(
      'expenseiq-once-$businessId-${DateTime.now().microsecondsSinceEpoch}',
      expenseIqBackgroundTaskName,
      inputData: {'businessId': businessId},
      constraints: await _constraints(businessId),
      initialDelay: const Duration(seconds: 5),
    );
  }
}
