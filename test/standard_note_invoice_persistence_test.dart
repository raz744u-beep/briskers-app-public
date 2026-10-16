import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/screens/jobs/invoice_note_draft_rules.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const manual = 'Customer asked to retain replaced parts.';
  const warranty =
      'Warranty: 12 months / 12,000 miles.\n\nOriginal exclusions.';
  const disclaimers = [
    {'body': 'Original disclaimer', 'signature_required': true},
  ];

  test(
    'cached synthetic invoice stores chosen note in durable memo outbox',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = LocalDocumentDetailCache(database: db);
      await cache.save('shop', 'TEST-NOTES-001', {
        'id': 'TEST-NOTES-001',
        'kind': 'invoice',
        'row_version': 1,
        'legacy_read_only': false,
        'memo': manual,
        'offline_warranty_detail': {'disclaimers': disclaimers},
      });
      final merged = mergeStandardNoteIntoDraft(manual, warranty);
      await OfflineDocumentEditService(database: db)
          .saveMemo('shop', 'TEST-NOTES-001', merged);
      // A fresh service and cache read model reopening after interruption.
      final reopened = await LocalDocumentDetailCache(database: db).load(
        'shop',
        'TEST-NOTES-001',
      );
      expect(reopened?['memo'], '$manual\n\n$warranty');
      expect(
        (reopened?['offline_warranty_detail'] as Map)['disclaimers'],
        disclaimers,
      );
      final repeat = mergeStandardNoteIntoDraft(
        reopened!['memo'].toString(),
        warranty,
      );
      expect(repeat, merged);
      await OfflineDocumentEditService(database: db)
          .saveMemo('shop', 'TEST-NOTES-001', repeat);
      final queued = await db
          .customSelect(
            "SELECT payload_json FROM sync_outbox WHERE entity_type='document_edit' AND operation='memo'",
          )
          .get();
      expect(queued, hasLength(1));
      expect(
        jsonDecode(queued.single.read<String>('payload_json'))['memo'],
        merged,
      );
    },
  );

  test('new local invoice retains selected note and single create queue after reopening', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = OfflineDocumentDraftService(database: db);
    final id = await service.createQuickInvoice(
      'shop',
      customerId: 'customer',
      customerName: 'Customer',
    );
    await service.saveMemo(
      'shop',
      id,
      mergeStandardNoteIntoDraft(manual, warranty),
    );
    final restored = await LocalDocumentDetailCache(database: db).load('shop', id);
    final repeated = mergeStandardNoteIntoDraft(
      restored!['memo'].toString(),
      warranty,
    );
    await OfflineDocumentDraftService(database: db)
        .saveMemo('shop', id, repeated);
    expect(
      (await LocalDocumentDetailCache(database: db).load('shop', id))?['memo'],
      '$manual\n\n$warranty',
    );
    final queue = await db
        .customSelect(
          "SELECT id FROM sync_outbox WHERE entity_type='document_draft_create'",
        )
        .get();
    expect(queue, hasLength(1));
  });

  test('invoice selection wiring preserves saved text and remains available to Secretary', () {
    final source = File('lib/screens/jobs/job_document_screen.dart')
        .readAsStringSync();
    final apply = source.substring(
      source.indexOf('  Future<void> _applyStandardNoteBody'),
      source.indexOf('  Future<void> _addStandardNote'),
    );
    expect(apply, contains('await _saveInlineNotes(preserveText: true)'));
    expect(apply, isNot(contains('!widget.isOwner')));
    final picker = source.substring(
      source.indexOf('  Future<void> _addStandardNote'),
      source.indexOf('  Future<Map<String, dynamic>?> _editDisclaimerSheet'),
    );
    expect(picker, contains('canManage: widget.isOwner'));
    expect(
      picker,
      contains(
        "await _applyStandardNoteBody(selected['body']?.toString() ?? '')",
      ),
    );
    final editor = source.substring(
      source.indexOf('  Future<Map<String, dynamic>?> _createStandardNote'),
      source.indexOf('  Future<void> _applyStandardNoteBody'),
    );
    expect(editor, contains('!widget.isOwner'));
    expect(editor, contains('_standardNotes.saveOffline'));
  });
}

