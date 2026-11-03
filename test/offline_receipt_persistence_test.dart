// ignore_for_file: prefer_interpolation_to_compose_strings, use_null_aware_elements, curly_braces_in_flow_control_structures
import 'dart:io';
import 'dart:typed_data';

import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_receipt_parser.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('confirmed offline receipt, parts and one original survive database restart',
      () async {
    final root = await Directory.systemTemp.createTemp('receipt-offline-');
    final dbFile = File(root.path + '/briskers.sqlite');
    const business = 'synthetic-receipt-shop';
    final original = Uint8List.fromList([1, 25, 86, 0, 255]);
    final reviewed = LocalReceiptParser.parse('''
WORLD PAC
Worldpac
Invoice 74966713
Date 10/27/2026
34 11 6 886 478 Brake Disc 2 56.70 113.40
34 11 6 852 253 Brake Pad Set 1 62.25 62.25
34 35 6 792 567 Brake Pad Sensor 1 15.70 15.70
TOTAL \$191.35
''')..['review_confirmed'] = true;

    var db = BriskersLocalDatabase(NativeDatabase(dbFile));
    var cache = LocalFinancialCache(database: db);
    var service = OfflineFinancialWriteService(
      database: db, cache: cache, mediaDirectoryProvider: () async => root,
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
        remarks: LocalReceiptParser.formatDescription(reviewed),
        receipts: [{
          'filename': 'worldpac.jpg',
          'mime_type': 'image/jpeg',
          'bytes': original,
        }],
        receiptExtraction: reviewed,
      );
      final id = detail['id'].toString();
      expect(detail['receipt_count'], 1);
      expect(detail['receipt_details']['vendor_invoice_number'], '74966713');
      expect(detail['receipt_items'], hasLength(3));
      expect(detail['remarks'],
        'Brake Disc, Brake Pad Set, Brake Pad Sensor — Inv. 74966713 — 10/27/26 — \$191.35');
      final photoPath = (detail['attachments'] as List).first['local_file_path'] as String;
      expect(await File(photoPath).readAsBytes(), original);

      // An edit to the same reviewed expense does not stage another photo.
      await service.updateLocalTransaction(
        business, id,
        direction: 'expense',
        accountId: 'account-synthetic',
        accountName: 'Business account',
        categoryId: 'category-synthetic',
        categoryName: 'Customer Parts',
        amount: 191.35,
        date: DateTime(2026, 10, 27),
        counterpartyName: 'Worldpac',
        remarks: LocalReceiptParser.formatDescription(reviewed),
        receipts: const [],
        receiptExtraction: reviewed,
      );
      final queuedReceipt = await db.customSelect(
        "SELECT COUNT(*) AS n FROM sync_outbox WHERE business_id = ? "
        "AND entity_type = 'financial_receipt_extraction'",
        variables: [const Variable<String>(business)],
      ).getSingle();
      expect(queuedReceipt.read<int>('n'), 1);

      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(dbFile));
      cache = LocalFinancialCache(database: db);
      final persisted = await cache.loadTransactionDetail(business, id);
      expect(persisted, isNotNull);
      expect(persisted!['receipt_count'], 1);
      expect(persisted['receipt_items'], hasLength(3));
      expect(persisted['receipt_extraction']['review_confirmed'], true);
      expect((persisted['receipt_items'] as List).first['sku'],
        '34 11 6 886 478');
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
