import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/backup/backup_archive.dart';
import 'package:briskers_app/services/backup/expenseiq_originals_import.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Expense IQ import retains both linked and unlinked originals offline',
      () async {
    final root = await Directory.systemTemp.createTemp('expenseiq-import-test-');
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    const linkedUri =
        'content://com.android.externalstorage.documents/document/'
        'primary%3AExpenseIQ%2Fphotos%2Flinked.jpg';
    const unlinkedUri =
        'content://com.android.externalstorage.documents/document/'
        'primary%3AExpenseIQ%2Fphotos%2Funlinked.jpg';
    final originals = <String, List<int>>{
      linkedUri: [1, 3, 5, 7, 9],
      unlinkedUri: [2, 4, 6, 8],
    };
    final channel = const MethodChannel('briskers/expenseiq-originals-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var sourceReads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listExpenseIqOriginals':
          return [
            for (final entry in originals.entries)
              <String, Object>{
                'path': entry.key == linkedUri ? 'linked.jpg' : 'unlinked.jpg',
                'uri': entry.key,
                'size': entry.value.length,
                'modified': 1729000000000,
              },
          ];
        case 'copyExpenseIqOriginal':
          final args = call.arguments as Map;
          final bytes = originals[args['uri'] as String];
          if (bytes == null) throw const PlatformException(code: 'missing');
          final target = File(args['destination'] as String);
          await target.parent.create(recursive: true);
          await target.writeAsBytes(bytes, flush: true);
          sourceReads++;
          return BackupArchive.digest(target);
        default:
          throw PlatformException(code: 'unexpected_method');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    // Create the exact local receipt-link row through the normal indexer.
    final indexed = await ExpenseIqLocalPhotoSync(database: db).indexPhotos(
      'shop',
      candidates: [
        {'transaction_id': 'expense-linked', 'photo_id': 'linked'},
      ],
      files: [
        {'name': 'linked.jpg', 'uri': linkedUri},
      ],
    );
    expect(indexed.matched, 1);

    final media = Directory('${root.path}/briskers_media/expenseiq_originals');
    final scratch = Directory('${root.path}/scratch');
    await scratch.create();
    final importer = ExpenseIqOriginalsImport(db, media, scratch, channel);
    final first = await importer.run('shop', 'synthetic-tree', (_) {});
    expect(first.scanned, 2);
    expect(first.copied, 2);
    expect(first.reused, 0);
    expect(first.unreadable, 0);
    expect(first.linked, 1);
    expect(first.outstanding, 0);
    expect(sourceReads, 2);

    final imported = await db.customSelect(
      'SELECT relative_path, digest, file_uri '
      'FROM local_expense_iq_imported_files WHERE business_id = \'shop\'',
    ).get();
    expect(imported.length, 2);
    final importedPaths = <String>{};
    for (final row in imported) {
      final name = row.read<String>('relative_path');
      importedPaths.add(name);
      final file = File.fromUri(Uri.parse(row.read<String>('file_uri')));
      expect(await file.exists(), true);
      expect(await file.readAsBytes(),
          originals[name == 'linked.jpg' ? linkedUri : unlinkedUri]);
      expect(await BackupArchive.digest(file), row.read<String>('digest'));
    }
    expect(importedPaths, {'linked.jpg', 'unlinked.jpg'});

    final linked = await ExpenseIqLocalPhotoSync(database: db)
        .localForExpense('shop', 'expense-linked');
    expect(linked?['source_uri'], startsWith('file:'));

    // Re-running with unchanged source metadata reads back and checks the
    // imported bytes, rather than duplicating files or receipt links.
    final again = await importer.run('shop', 'synthetic-tree', (_) {});
    expect(again.scanned, 2);
    expect(again.copied, 0);
    expect(again.reused, 2);
    expect(again.unreadable, 0);
    expect(again.outstanding, 0);
    expect(sourceReads, 2);
    expect(await media.list().length, 2);
  });
}
