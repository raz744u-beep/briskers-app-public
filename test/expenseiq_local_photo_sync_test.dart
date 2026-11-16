import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';

void main() {
  test('indexing 255 photos reports committed batches and resumes safely',
      () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: db);
    final candidates = <Map<String, dynamic>>[];
    final photos = <Map<String, dynamic>>[];
    for (var i = 0; i < 255; i++) {
      candidates.add({
        'transaction_id': 'expense-$i',
        'photo_id': 'receipt-$i',
      });
      photos.add({
        'name': 'receipt-$i.jpg',
        'uri': 'content://test/receipt-$i',
      });
    }
    final progress = <int>[];
    final index = await service.indexPhotos(
      'business-1',
      candidates: candidates,
      files: photos,
      onProgress: (done, total) {
        expect(total, 255);
        progress.add(done);
      },
    );
    expect(index.matched, 255);
    expect(progress, [0, 100, 200, 255]);
    expect((await service.counts('business-1')).pending, 255);

    // Re-running the import never duplicates existing indexed receipts.
    await service.indexPhotos(
      'business-1',
      candidates: candidates,
      files: photos,
    );
    expect((await service.counts('business-1')).indexed, 255);
    await db.close();
  });

  test('ExpenseIQ indexes local SAF URIs without uploading or copying files',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: database);
    final result = await service.indexPhotos(
      'business-1',
      candidates: [
        {'transaction_id': 'expense-1', 'photo_id': 'receipt-a'},
        {'transaction_id': 'expense-2', 'photo_id': 'receipt-b'},
        {'transaction_id': 'expense-3', 'photo_id': 'receipt-missing'},
      ],
      files: [
        {'name': 'receipt-a.JPG', 'uri': 'content://test/photo-a'},
        {'name': 'receipt-b.jpeg', 'uri': 'content://test/photo-b'},
      ],
    );

    expect(result.matched, 2);
    expect(result.missing, 1);
    final counts = await service.counts('business-1');
    expect(counts.indexed, 3);
    expect(counts.pending, 2);
    expect(counts.missing, 1);
    expect(counts.uploaded, 0);
    expect(counts.enabled, true);
    expect(counts.wifiOnly, true);
    final first = await service.localForExpense('business-1', 'expense-1');
    expect(first?['source_uri'], 'content://test/photo-a');
    expect(first?['state'], 'pending');
    await database.close();
  });

  test('re-index is idempotent and preserves uploaded records', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: database);
    final candidates = [
      {'transaction_id': 'expense-1', 'photo_id': 'receipt-a'},
    ];
    final files = [
      {'name': 'receipt-a.jpg', 'uri': 'content://test/photo-a'},
    ];
    await service.indexPhotos(
      'business-1', candidates: candidates, files: files,
    );
    await database.customStatement(
      '''
      UPDATE local_expense_iq_photos SET state='uploaded'
      WHERE business_id='business-1' AND transaction_id='expense-1'
      ''',
    );
    await service.indexPhotos(
      'business-1', candidates: candidates, files: files,
    );
    expect((await service.counts('business-1')).indexed, 1);
    expect((await service.counts('business-1')).uploaded, 1);
    expect((await service.counts('business-1')).pending, 0);

    await service.setOptions('business-1', enabled: false, wifiOnly: false);
    final paused = await service.counts('business-1');
    expect(paused.enabled, false);
    expect(paused.wifiOnly, false);
    await database.close();
  });

  test('re-index cannot erase previously indexed original URI', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: database);
    final candidates = [
      {'transaction_id': 'expense-1', 'photo_id': 'receipt-a'},
    ];
    await service.indexPhotos(
      'business-1',
      candidates: candidates,
      files: [{'name': 'receipt-a.jpg', 'uri': 'content://test/original'}],
    );
    await service.indexPhotos(
      'business-1', candidates: candidates, files: [],
    );
    final photo = await service.localForExpense('business-1', 'expense-1');
    expect(photo?['source_uri'], 'content://test/original');
    expect(photo?['state'], 'pending');
    await database.close();
  });
  test('regrant changes only the verified original URI and preserves upload state',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: database);
    await service.indexPhotos(
      'shop',
      candidates: [
        {'transaction_id': 'worldpac', 'photo_id': 'receipt-a'},
        {'transaction_id': 'other', 'photo_id': 'receipt-b'},
      ],
      files: [
        {
          'name': 'receipt-a.jpg',
          'uri': 'content://android/tree/ExpenseIQ/Photos/receipt-a.jpg',
        },
        {'name': 'receipt-b.jpg', 'uri': 'content://test/other'},
      ],
    );
    await database.customStatement(
      "UPDATE local_expense_iq_photos SET state='uploaded' "
      "WHERE business_id='shop' AND transaction_id='worldpac'",
    );
    await service.reconnectOriginalPhoto(
      businessId: 'shop',
      transactionId: 'worldpac',
      expectedFilename: 'receipt-a.jpg',
      previousUri: 'content://android/tree/ExpenseIQ/Photos/receipt-a.jpg',
      verifiedUri: 'content://android/tree/ExpenseIQ/photos/receipt-a.jpg',
    );
    final recovered = await service.localForExpense('shop', 'worldpac');
    expect(
      recovered?['source_uri'],
      'content://android/tree/ExpenseIQ/photos/receipt-a.jpg',
    );
    expect(recovered?['state'], 'uploaded');
    final other = await service.localForExpense('shop', 'other');
    expect(other?['source_uri'], 'content://test/other');
    expect(other?['state'], 'pending');
    final counts = await service.counts('shop');
    expect(counts.uploaded, 1);
    expect(counts.pending, 1);
    await database.close();
  });

  test('regrant refuses stale, wrong-expense and wrong-filename references',
      () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    final service = ExpenseIqLocalPhotoSync(database: database);
    await service.indexPhotos(
      'shop',
      candidates: [
        {'transaction_id': 'worldpac', 'photo_id': 'receipt-a'},
      ],
      files: [
        {'name': 'receipt-a.jpg', 'uri': 'content://test/original'},
      ],
    );
    for (final bad in [
      {'transactionId': 'other', 'filename': 'receipt-a.jpg', 'uri': 'content://test/original'},
      {'transactionId': 'worldpac', 'filename': 'wrong.jpg', 'uri': 'content://test/original'},
      {'transactionId': 'worldpac', 'filename': 'receipt-a.jpg', 'uri': 'content://test/stale'},
    ]) {
      await expectLater(
        service.reconnectOriginalPhoto(
          businessId: 'shop',
          transactionId: bad['transactionId']!,
          expectedFilename: bad['filename']!,
          previousUri: bad['uri']!,
          verifiedUri: 'content://test/replacement',
        ),
        throwsA(isA<StateError>()),
      );
    }
    final original = await service.localForExpense('shop', 'worldpac');
    expect(original?['source_uri'], 'content://test/original');
    await database.close();
  });

}
