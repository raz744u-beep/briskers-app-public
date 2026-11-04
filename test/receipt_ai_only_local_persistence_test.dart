// ignore_for_file: prefer_interpolation_to_compose_strings, use_null_aware_elements, curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:typed_data';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _ReceiptSyncApi extends BriskersApi {
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
  }) async => {'transaction_id': 'server-transaction'};

  @override
  Future<Map<String, dynamic>> applyExpenseReceiptExtraction(
    String businessId,
    String transactionId,
    Map<String, dynamic> extraction,
  ) async => throw StateError('Synthetic receipt service unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('receipt revision replaces remapped pending extraction after interrupted sync', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    final cache = LocalFinancialCache(database: db);
    final service = OfflineFinancialWriteService(
      database: db,
      cache: cache,
      api: _ReceiptSyncApi(),
    );
    addTearDown(db.close);
    const business = 'synthetic-receipt-shop';
    const extraction = <String, dynamic>{
      'review_confirmed': true,
      'receipt_total': 10,
    };
    await service.createLocalTransaction(
      business,
      direction: 'expense',
      accountId: 'account',
      categoryId: 'category',
      amount: 10,
      date: DateTime(2026, 11, 3),
      receipts: const [],
      receiptExtraction: extraction,
    );
    // Fake transport only: no Supabase initialization or external request.
    await service.flush(business);
    var rows = await db
        .customSelect(
          "SELECT entity_id FROM sync_outbox WHERE entity_type = 'financial_receipt_extraction'",
        )
        .get();
    expect(rows.single.read<String>('entity_id'), 'server-transaction');
    await service.updateLocalTransaction(
      business,
      'server-transaction',
      direction: 'expense',
      accountId: 'account',
      categoryId: 'category',
      amount: 11,
      date: DateTime(2026, 11, 3),
      receiptExtraction: {...extraction, 'receipt_total': 11},
    );
    rows = await db
        .customSelect(
          "SELECT entity_id FROM sync_outbox WHERE entity_type = 'financial_receipt_extraction'",
        )
        .get();
    expect(rows, hasLength(1));
    final detail = await cache.loadTransactionDetail(
      business,
      'server-transaction',
    );
    expect(detail!['receipt_details']['receipt_total'], 11);
  });

  test('confirmed offline receipt, parts and one original survive database restart', () async {
    final root = await Directory.systemTemp.createTemp('receipt-offline-');
    final dbFile = File(root.path + '/briskers.sqlite');
    const business = 'synthetic-receipt-shop';
    final original = Uint8List.fromList([1, 25, 86, 0, 255]);
    const description =
        'Brake Disc, Brake Pad Set, Brake Pad Sensor — Inv. 74966713 — 10/27/26 — \$191.35';
    final reviewed = <String, dynamic>{
      'vendor_name': 'Worldpac',
      'vendor_invoice_number': '74966713',
      'receipt_date': '2026-10-27',
      'receipt_total': 191.35,
      'extraction_source': 'existing_online_receipt_ai',
      'review_confirmed': true,
      'items': <Map<String, dynamic>>[
        {
          'description': 'Brake Disc',
          'sku': '34 11 6 886 478',
          'quantity': 2,
          'unit_price': 56.70,
          'total_amount': 113.40,
        },
        {
          'description': 'Brake Pad Set',
          'sku': '34 11 6 852 253',
          'quantity': 1,
          'unit_price': 62.25,
          'total_amount': 62.25,
        },
        {
          'description': 'Brake Pad Sensor',
          'sku': '34 35 6 792 567',
          'quantity': 1,
          'unit_price': 15.70,
          'total_amount': 15.70,
        },
      ],
    };

    var db = BriskersLocalDatabase(NativeDatabase(dbFile));
    var cache = LocalFinancialCache(database: db);
    var service = OfflineFinancialWriteService(
      database: db,
      cache: cache,
      mediaDirectoryProvider: () async => root,
    );
    try {
      final detail = await service.createLocalTransaction(
        business,
        direction: 'expense',
        accountId: 'account-synthetic',
        accountName: 'Business account',
        categoryId: 'category-synthetic',
        categoryName: 'Customer Parts',
        amount: 191.35,
        date: DateTime(2026, 10, 27),
        counterpartyName: 'Worldpac',
        remarks: description,
        receipts: [
          {
            'filename': 'worldpac.jpg',
            'mime_type': 'image/jpeg',
            'bytes': original,
          },
        ],
        receiptExtraction: reviewed,
      );
      final id = detail['id'].toString();
      expect(detail['receipt_count'], 1);
      expect(detail['receipt_details']['vendor_invoice_number'], '74966713');
      expect(detail['receipt_items'], hasLength(3));
      expect(
        detail['remarks'],
        'Brake Disc, Brake Pad Set, Brake Pad Sensor — Inv. 74966713 — 10/27/26 — \$191.35',
      );
      final photoPath =
          (detail['attachments'] as List).first['local_file_path'] as String;
      expect(await File(photoPath).readAsBytes(), original);

      // An edit to the same reviewed expense does not stage another photo.
      await service.updateLocalTransaction(
        business,
        id,
        direction: 'expense',
        accountId: 'account-synthetic',
        accountName: 'Business account',
        categoryId: 'category-synthetic',
        categoryName: 'Customer Parts',
        amount: 191.35,
        date: DateTime(2026, 10, 27),
        counterpartyName: 'Worldpac',
        remarks: description,
        receipts: const [],
        receiptExtraction: reviewed,
      );
      final queuedReceipt = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id = ? "
            "AND entity_type = 'financial_receipt_extraction'",
            variables: [const Variable<String>(business)],
          )
          .getSingle();
      expect(queuedReceipt.read<int>('n'), 1);

      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(dbFile));
      cache = LocalFinancialCache(database: db);
      final persisted = await cache.loadTransactionDetail(business, id);
      expect(persisted, isNotNull);
      expect(persisted!['receipt_count'], 1);
      expect(persisted['receipt_items'], hasLength(3));
      expect(persisted['receipt_extraction']['review_confirmed'], true);
      expect(
        (persisted['receipt_items'] as List).first['sku'],
        '34 11 6 886 478',
      );
      expect((persisted['attachments'] as List), hasLength(1));
      expect(await File(photoPath).readAsBytes(), original);
      final financialRows = await cache.loadTransactions(business);
      expect(financialRows, hasLength(1));
      expect(financialRows.single['amount'], 191.35);
      expect(financialRows.single['sync_state'], 'pending');
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
}
