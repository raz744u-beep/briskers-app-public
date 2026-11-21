import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_cached_attachment_references.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Media inventory includes scoped notes, expense receipts, and history',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_customer_section_shop-A_person-1_notes',
        jsonEncode([
          {'attachments': [
            {'bucket': 'briskers-private', 'key': 'note/a.jpg'},
            {'key': 'note/queued.jpg', 'upload_state': 'pending'}
          ]}
        ]));
    await prefs.setString('briskers_customer_section_shop-B_person-1_notes',
        jsonEncode([
          {'attachments': [
            {'bucket': 'briskers-private', 'key': 'other-shop.jpg'}
          ]}
        ]));

    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customStatement(
        'INSERT INTO local_financial_cache '
        '(business_id, cache_key, payload_json, updated_at) '
        'VALUES (?, ?, ?, ?)',
        [
          'shop-A',
          'transaction_detail_receipt-1',
          jsonEncode({'attachments': [
            {'bucket': 'briskers-private', 'key': 'receipt/1.jpg'}
          ]}),
          0,
        ],
      );
      await db.customStatement(
        'INSERT INTO local_financial_cache '
        '(business_id, cache_key, payload_json, updated_at) '
        'VALUES (?, ?, ?, ?)',
        [
          'shop-A',
          'transactions_snapshot',
          jsonEncode([{'attachments': [
            {'bucket': 'briskers-private', 'key': 'receipt/2.jpg'},
            {'bucket': 'briskers-private', 'key': 'receipt/1.jpg'}
          ]}]),
          0,
        ],
      );
      await db.customStatement(
        'INSERT INTO local_financial_cache '
        '(business_id, cache_key, payload_json, updated_at) '
        'VALUES (?, ?, ?, ?)',
        ['shop-B', 'transaction_detail_cross', jsonEncode({
          'attachments': [{'key':'other-shop-receipt.jpg'}]
        }), 0],
      );

      final photos =
          await OfflineCachedAttachmentReferences(database: db).collect('shop-A');
      expect(photos.map((r) => r.key).toList(), [
        'note/a.jpg', 'receipt/1.jpg', 'receipt/2.jpg',
      ]);
      expect(photos.any((x) => x.key.contains('queued')), isFalse);
      expect(photos.any((x) => x.key.contains('other-shop')), isFalse);
    } finally {
      await db.close();
    }
  });

  test('Note thumbnail and full image use the same local-file-first renderer',
      () {
    final image = File('lib/widgets/local_first_attachment_image.dart')
        .readAsStringSync();
    final notes = File('lib/screens/customers/customer_notes_section.dart')
        .readAsStringSync();
    expect(image, contains('_cache.existing(bucket, key)'));
    expect(image, contains('BriskersConnectionModeController.instance.forceOffline'));
    expect(image, contains('Image.file('));
    expect(image.indexOf('_cache.existing(bucket, key)'),
        lessThan(image.indexOf('_cache.getOrDownload(bucket, key)')));
    expect(notes, contains('LocalFirstAttachmentImage('));
    expect(notes, contains('imageFile: file'));
    final card = notes.substring(notes.indexOf('class _NoteImageState'),
        notes.indexOf('class _CustomerNoteImageViewer'));
    expect(card, isNot(contains('signedAttachmentUrl')));
    expect(card, isNot(contains('Image.network(')));
  });
}
