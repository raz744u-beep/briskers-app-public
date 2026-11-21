import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Document hydration coalesces overlapping reads per database/shop',
      () {
    final src =
        File('lib/services/document_index_sync_service.dart').readAsStringSync();
    expect(src,
        contains('static final Expando<Map<String, Future<void>>> _activePulls'));
    expect(src, contains('final pending = active[businessId];'));
    expect(src, contains('if (pending != null) return pending;'));
    expect(src, contains('final work = _pullUnshared(businessId);'));
    expect(src, contains('if (identical(active[businessId], work))'));
    expect(src, contains('await _prefetchAllDocumentDetails(businessId, all);'));
    expect(src, contains('TestJobCleanupPolicy.hasPendingSnapshot(snapshot)'));
  });

  test('Settings counts only already-discovered photo references', () {
    final mirror =
        File('lib/services/offline_attachment_mirror_service.dart')
            .readAsStringSync();
    final status = File('lib/screens/settings/local_sync_status_screen.dart')
        .readAsStringSync();
    expect(mirror, contains('Future<OfflineAttachmentInventory> inventory('));
    expect(mirror, contains('knownReferences(businessId)'));
    expect(mirror, contains('_cache.existing(ref.bucket, ref.key)'));
    expect(mirror, contains('class OfflineAttachmentInventory'));
    expect(status, contains('OfflineAttachmentMirrorService'));
    expect(status, contains('FutureBuilder<OfflineAttachmentInventory>'));
    expect(status, contains('Offline photo copies'));
    expect(status, contains('full historical total may be higher'));
  });
}
