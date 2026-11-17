import 'dart:io';
import 'dart:typed_data';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/expenseiq_local_photo_sync.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.briskers/expenseiq');
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('retained folder resolves different receipts and recovered originals survive restart', () async {
    final directory = await Directory.systemTemp.createTemp('receipt-folder');
    var database = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });
    var service = ExpenseIqLocalPhotoSync(database: database);
    await service.indexPhotos('shop', candidates: [
      {'transaction_id': 'first', 'photo_id': 'first'},
      {'transaction_id': 'second', 'photo_id': 'second'},
    ], files: [
      {'name': 'first.jpg', 'uri': 'content://old/first'},
    ]);
    await database.customStatement("UPDATE local_expense_iq_photos SET state='uploaded'");
    final resolutions = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'resolveExpenseIqPhoto');
      final filename = (call.arguments as Map)['filename'] as String;
      resolutions.add(filename);
      return {'name': filename, 'uri': 'content://retained/$filename'};
    });
    for (final id in ['first', 'second']) {
      final photo = (await service.localForExpense('shop', id))!;
      final bytes = await service.readOriginalPhoto('shop', id, photo, reader: (uri) async {
        if (uri.startsWith('content://old/')) throw PlatformException(code: 'permission_denied');
        expect(uri, 'content://retained/$id.jpg');
        return jpeg;
      });
      expect(bytes, jpeg);
      expect((await service.localForExpense('shop', id))!['state'], 'uploaded');
    }
    expect(resolutions, ['first.jpg', 'second.jpg']);
    await database.close();
    database = BriskersLocalDatabase(NativeDatabase(File('${directory.path}/shop.sqlite')));
    service = ExpenseIqLocalPhotoSync(database: database);
    for (final id in ['first', 'second']) {
      final photo = (await service.localForExpense('shop', id))!;
      expect(await service.readOriginalPhoto('shop', id, photo, reader: (_) async {
        throw StateError('Saved originals must open without folder access.');
      }), jpeg);
    }
    expect(resolutions, ['first.jpg', 'second.jpg']);
    expect(await service.recoveredOriginal('another-shop', 'first', 'first.jpg'), isNull);
  });

  test('folder recovery refuses an unrelated filename and preserves the existing reference', () async {
    final database = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final service = ExpenseIqLocalPhotoSync(database: database);
    await service.indexPhotos('shop', candidates: [
      {'transaction_id': 'expense', 'photo_id': 'original'},
    ], files: [
      {'name': 'original.jpg', 'uri': 'content://old/original'},
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => {
      'name': 'unrelated.jpg', 'uri': 'content://retained/unrelated.jpg',
    });
    final photo = (await service.localForExpense('shop', 'expense'))!;
    await expectLater(service.readOriginalPhoto('shop', 'expense', photo, reader: (_) async {
      throw StateError('Old folder unavailable');
    }), throwsStateError);
    expect((await service.localForExpense('shop', 'expense'))!['source_uri'], 'content://old/original');
    expect(await service.recoveredOriginal('shop', 'expense', 'original.jpg'), isNull);
  });
}
