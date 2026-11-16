import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Idle photo mirror only reads known synchronized photo references', () {
    final s = File('lib/services/offline_attachment_mirror_service.dart')
        .readAsStringSync();
    expect(s, contains('local_finding_photos'));
    expect(s, contains('local_pre_inspection_photos'));
    expect(s, contains("upload_state = 'synced'"));
    expect(s, contains("business_id = ?"));
    expect(s, contains('LocalAttachmentCache'));
    expect(s, contains('OfflineCachedAttachmentReferences'));
    expect(s, contains('knownReferences(businessId)'));
    expect(s, contains('_cache.existing(ref.bucket, ref.key)'));
    expect(s, contains('_cache.getOrDownload(ref.bucket, ref.key)'));
    expect(s, contains('batchSize = 24'));
    expect(s, contains('forceOffline'));
    expect(s, contains('prefs.setInt(cursorKey'));
    expect(s, isNot(contains('DELETE FROM')));
    expect(s, isNot(contains('UPDATE local_')));
  });

  test('Background mirror requires Wi-Fi, charging, no forced offline', () {
    final worker = File('lib/services/expenseiq_background_scheduler.dart')
        .readAsStringSync();
    final shell = File('lib/screens/shell_screen.dart')
        .readAsStringSync();
    expect(worker, contains("offlineMediaMirrorTaskName = 'briskers.offline.media.prefetch'"));
    expect(worker, contains('networkType: NetworkType.unmetered'));
    expect(worker, contains('requiresCharging: true'));
    expect(worker, contains('registerPeriodicTask('));
    expect(worker, contains('BriskersConnectionModeController.instance.initialize()'));
    expect(worker, contains('if (BriskersConnectionModeController.instance.forceOffline)'));
    expect(worker, contains('OfflineAttachmentMirrorService().prefetchBatch'));
    expect(shell, contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(shell, contains('.scheduleOfflineMediaMirror(widget.businessId)'));
  });
}
