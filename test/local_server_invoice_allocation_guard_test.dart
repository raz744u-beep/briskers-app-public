import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/local/local_database_provider.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_server_invoice_allocation_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    debugUseLocalDatabase(db);
  });
  tearDown(() async {
    debugUseLocalDatabase(null);
    await db.close();
  });
  Future<void> savedInvoice({String state = 'pending', String business = 'shop'}) =>
    db.customStatement("INSERT INTO local_documents(id,business_id,kind,document_number,status,total,sync_state) "
      "VALUES('dakota',?,'invoice','6360','closed',554.24,?)", [business, state]);
  final blocked = isA<StateError>().having((e) => e.message, 'actionable message', contains('Use Force Offline'));

  for (final action in ['quick invoice', 'job invoice', 'estimate conversion']) {
    test('$action cannot reach server-only allocator with local numbered work', () async {
      await savedInvoice();
      final before = (await db.customSelect('SELECT * FROM local_documents').getSingle()).data;
      // Supabase is deliberately uninitialized. The actual public API must
      // refuse before reaching its network client, and preserve all records.
      const api = BriskersApi();
      final Future<String> operation;
      if (action == 'quick invoice') {
        operation = api.createQuickInvoice('shop', customerId: 'tyra');
      } else if (action == 'job invoice') {
        operation = api.createInvoice('shop', 'tyra-job');
      } else {
        operation = api.convertEstimate('shop', 'tyra-estimate');
      }
      await expectLater(operation, throwsA(blocked));
      expect((await db.customSelect('SELECT * FROM local_documents').getSingle()).data, before);
    });
  }

  test('closed paid invoice outside refreshed list still blocks cloud allocation', () async {
    final raw = jsonEncode({'id': 'dakota', 'kind': 'invoice',
      'document_number': '6360', 'closed_at': '2026-11-02',
      'total_amount': 554.24, 'paid_amount': 554.24});
    const key = 'briskers_document_detail_shop_dakota';
    await LocalDocumentSqlStore.write(db, key, raw);
    await expectLater(LocalServerInvoiceAllocationGuard.assertSafe(db, 'shop'), throwsA(blocked));
    expect(await LocalDocumentSqlStore.read(db, key), raw);
  });

  test('acknowledged index and another business do not block server allocation', () async {
    await savedInvoice(state: 'synced');
    await LocalServerInvoiceAllocationGuard.assertSafe(db, 'shop');
    await db.customStatement("UPDATE local_documents SET sync_state='pending'");
    await LocalServerInvoiceAllocationGuard.assertSafe(db, 'other-shop');
  });
}
