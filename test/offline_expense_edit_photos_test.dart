import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _business = 'synthetic-photo-shop';
const _transaction = 'synthetic-existing-transaction';
const _existingAttachment = <String, dynamic>{
  'attachment_id': 'synthetic-existing-receipt',
  'filename': 'already-attached.jpg',
  'bucket': 'synthetic-bucket',
  'key': 'synthetic/existing-receipt',
  'upload_state': 'synced',
};

Map<String, dynamic> _receipt(int value) => {
  // Equal filenames are intentional: each explicitly selected photo is kept.
  'filename': 'synthetic-receipt.jpg',
  'mime_type': 'image/jpeg',
  'bytes': Uint8List.fromList([value, value + 1, value + 2]),
};

class _Api extends BriskersApi {
  final registrations = <String, Map<String, dynamic>>{};
  final registrationCalls = <String>[];
  final registeredTransactions = <String>[];
  final uploaded = <String, List<int>>{};
  int updateCalls = 0;
  int createCalls = 0;
  int uploadCalls = 0;
  bool failNextUploadAcknowledgement = false;

  @override
  Future<void> updateManualTransaction(
    String businessId,
    String transactionId, {
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    expect(businessId, _business);
    expect(transactionId, _transaction);
    updateCalls++;
  }

  @override
  Future<Map<String, dynamic>> syncCreateManualTransaction(
    String businessId, {
    required String operationId,
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    expect(businessId, _business);
    createCalls++;
    return {'transaction_id': _transaction};
  }

  @override
  Future<Map<String, dynamic>> syncRegisterExpensePhoto(
    String businessId,
    String transactionId, {
    required String operationId,
    required String filename,
    required String mimeType,
  }) async {
    expect(businessId, _business);
    expect(transactionId, _transaction);
    registrationCalls.add(operationId);
    registeredTransactions.add(transactionId);
    return registrations.putIfAbsent(operationId, () => {
      'attachment_id': 'synthetic-server-$operationId',
      'bucket': 'synthetic-bucket',
      'key': 'synthetic/$operationId',
    });
  }

  @override
  Future<void> uploadRegisteredAttachment(
    String businessId, {
    required String bucket,
    required String key,
    required String attachmentId,
    required String mimeType,
    required Uint8List bytes,
    AttachmentReplayGuard? replayGuard,
  }) async {
    expect(businessId, _business);
    uploadCalls++;
    // Like the real registered-upload path, a retry uses the same identity.
    uploaded.putIfAbsent(attachmentId, () => List<int>.of(bytes));
    if (failNextUploadAcknowledgement) {
      failNextUploadAcknowledgement = false;
      throw StateError('Synthetic lost upload acknowledgement');
    }
  }
}

class _FailingCache extends LocalFinancialCache {
  _FailingCache(BriskersLocalDatabase database) : super(database: database);
  bool failNextSave = false;

  @override
  Future<void> saveTransactionDetail(
    String businessId,
    String transactionId,
    Map<String, dynamic> detail,
    {int? visibilityGeneration},
  ) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Synthetic interrupted cache write');
    }
    await super.saveTransactionDetail(businessId, transactionId, detail);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File dbFile;
  late BriskersLocalDatabase database;
  late LocalFinancialCache cache;
  late _Api api;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('expense-edit-photos-');
    dbFile = File('${directory.path}/synthetic.sqlite');
    database = BriskersLocalDatabase(NativeDatabase(dbFile));
    cache = LocalFinancialCache(database: database);
    api = _Api();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  OfflineFinancialWriteService service({LocalFinancialCache? overrideCache}) =>
      OfflineFinancialWriteService(
        database: database,
        cache: overrideCache ?? cache,
        api: api,
        mediaDirectoryProvider: () async => directory,
      );

  Future<void> seed() async {
    await cache.saveTransactions(_business, [
      {'id': _transaction, 'amount': 10, 'receipt_count': 1},
    ]);
    await cache.saveTransactionDetail(_business, _transaction, {
      'id': _transaction,
      'amount': 10,
      'attachments': [_existingAttachment],
      'receipt_count': 1,
    });
  }

  Future<Map<String, dynamic>> edit(
    OfflineFinancialWriteService writer, {
    String id = _transaction,
    String direction = 'expense',
    List<Map<String, dynamic>> receipts = const [],
  }) => writer.updateLocalTransaction(
    _business,
    id,
    direction: direction,
    accountId: 'synthetic-account',
    accountName: 'Synthetic cash',
    categoryId: 'synthetic-category',
    categoryName: 'Synthetic category',
    amount: 25,
    date: DateTime(2026, 10, 14),
    receipts: receipts,
  );

  Future<List<Map<String, dynamic>>> photoPayloads() async {
    final rows = await database.customSelect(
      "SELECT payload_json FROM sync_outbox "
      "WHERE entity_type = 'financial_photo' ORDER BY id",
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(
      jsonDecode(row.read<String>('payload_json')) as Map,
    )).toList();
  }

  Future<void> restart() async {
    await database.close();
    database = BriskersLocalDatabase(NativeDatabase(dbFile));
    cache = LocalFinancialCache(database: database);
  }

  for (final direction in ['expense', 'income']) {
    test('$direction edit preserves existing photos through restart and re-edit',
        () async {
      await seed();
      final detail = await edit(
        service(),
        direction: direction,
        receipts: [_receipt(10), _receipt(20)],
      );
      final attached = List<dynamic>.from(detail['attachments'] as List);
      expect(attached, hasLength(3));
      expect(attached.first, _existingAttachment);
      expect(detail['receipt_count'], 3);
      final before = await photoPayloads();
      expect(before, hasLength(2));
      expect(before.map((row) => row['operation_id']).toSet(), hasLength(2));
      for (final photo in before) {
        expect(await File(photo['local_file_path'] as String).exists(), isTrue);
      }

      await restart();
      final restored = await cache.loadTransactionDetail(_business, _transaction);
      expect(restored!['attachments'], attached);
      await edit(service(), direction: direction);
      expect(await photoPayloads(), before);
      final edited = await cache.loadTransactionDetail(_business, _transaction);
      expect(edited!['attachments'], attached);

      await service().flush(_business);
      expect(await photoPayloads(), isEmpty);
      expect(api.registrations, hasLength(2));
      expect(api.uploaded.values, unorderedEquals([
        [10, 11, 12],
        [20, 21, 22],
      ]));
      final synced = await cache.loadTransactionDetail(_business, _transaction);
      final syncedPhotos = List<Map<String, dynamic>>.from(
        synced!['attachments'] as List,
      );
      expect(syncedPhotos.first, _existingAttachment);
      expect(syncedPhotos.every((photo) => photo['upload_state'] == 'synced'), isTrue);
      expect(syncedPhotos, hasLength(3));
      final calls = api.uploadCalls;
      await service().flush(_business);
      expect(api.uploadCalls, calls);
    });
  }

  test('upload retry after restart reuses the same receipt operation exactly once',
      () async {
    await seed();
    await edit(service(), receipts: [_receipt(30)]);
    final queued = (await photoPayloads()).single;
    api.failNextUploadAcknowledgement = true;
    await service().flush(_business);
    expect(await photoPayloads(), [queued]);
    final interrupted = await cache.loadTransactionDetail(_business, _transaction);
    expect((interrupted!['attachments'] as List).last['upload_state'], 'pending');

    await restart();
    await service().flush(_business);
    expect(await photoPayloads(), isEmpty);
    expect(api.registrationCalls, [queued['operation_id'], queued['operation_id']]);
    expect(api.registrations, hasLength(1));
    expect(api.uploaded, hasLength(1));
    expect(api.uploadCalls, 2);
    final restored = await cache.loadTransactionDetail(_business, _transaction);
    expect(restored!['receipt_count'], 2);
    expect((restored['attachments'] as List).first, _existingAttachment);
    expect((restored['attachments'] as List).last['upload_state'], 'synced');
    expect(await File(queued['local_file_path'] as String).readAsBytes(), [30, 31, 32]);
  });

  test('editing an offline-created transaction appends photos and remaps once',
      () async {
    final created = await service().createLocalTransaction(
      _business,
      direction: 'expense',
      accountId: 'synthetic-account',
      accountName: 'Synthetic cash',
      categoryId: 'synthetic-category',
      categoryName: 'Synthetic category',
      amount: 10,
      date: DateTime(2026, 10, 13),
      receipts: [_receipt(40)],
    );
    final localId = created['id'] as String;
    await edit(service(), id: localId, receipts: [_receipt(50)]);
    final queue = await database.customSelect(
      'SELECT entity_type FROM sync_outbox ORDER BY id',
    ).get();
    expect(queue.map((row) => row.read<String>('entity_type')), [
      'financial_create', 'financial_photo', 'financial_photo',
    ]);
    await restart();
    await service().flush(_business);
    expect(api.createCalls, 1);
    expect(api.updateCalls, 0);
    expect(api.registeredTransactions, [_transaction, _transaction]);
    expect(api.registrations, hasLength(2));
    expect(await photoPayloads(), isEmpty);
    final saved = await cache.loadTransactionDetail(_business, _transaction);
    expect(saved!['receipt_count'], 2);
    expect((saved['attachments'] as List).every(
      (photo) => photo['upload_state'] == 'synced',
    ), isTrue);
  });

  test('interrupted edit rolls back attachment list and queue before retry',
      () async {
    await seed();
    final failing = _FailingCache(database)..failNextSave = true;
    await expectLater(
      edit(service(overrideCache: failing), receipts: [_receipt(60)]),
      throwsStateError,
    );
    expect(await photoPayloads(), isEmpty);
    expect(await database.customSelect('SELECT id FROM sync_outbox').get(), isEmpty);
    final unchanged = await cache.loadTransactionDetail(_business, _transaction);
    expect(unchanged!['attachments'], [_existingAttachment]);
    expect(unchanged['amount'], 10);
    expect((await cache.loadTransactions(_business)).single['receipt_count'], 1);

    await edit(service(overrideCache: failing), receipts: [_receipt(60)]);
    expect(await photoPayloads(), hasLength(1));
    final retried = await cache.loadTransactionDetail(_business, _transaction);
    expect(retried!['receipt_count'], 2);
    expect((retried['attachments'] as List).first, _existingAttachment);
    await service().flush(_business);
    expect(api.uploaded, hasLength(1));
  });
}
