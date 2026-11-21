import 'dart:io';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/core/document_presentation.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_closure.dart';
import 'package:briskers_app/services/offline_invoice_finalization.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('closure posts dated Income once, batch rollback and stale preview preserve records', () async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.offline);
    final folder = await Directory.systemTemp.createTemp('synthetic-close-');
    final file = File('${folder.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async { await db.close(); await folder.delete(recursive: true);
      LocalDocumentDetailCache.sqliteWritesEnabled = false; });
    await LocalDocumentDetailCache.initialize(db);
    Map<String, dynamic> fixture(String id, {bool invalid = false}) => {
      'id': id, 'kind': 'invoice', 'status': 'issued', 'total_amount': 109.75,
      'paid_amount': 10, 'pending_payment': 99.75, 'tax_amount': 9.75,
      'payments': [
        {'id': '$id-posted', 'state': 'posted', 'amount': 10,
          'payment_method_id': 'cash', 'payment_method_name': 'Cash', 'payment_date':'2026-11-12'},
        {'id': '$id-received', 'state': 'pending', 'amount': 99.75,
          'payment_method_id': 'cash', if (!invalid) 'payment_method_name': 'Cash', 'payment_date':'2026-11-13'},
      ],
    };
    var cache = LocalDocumentDetailCache(database: db);
    for (final id in ['one','two']) {
      await cache.save('test-shop',id,fixture(id,invalid:id=='two'));
    }
    var closure = LocalInvoiceClosure(database: db);
    // A failure on the second invoice rolls back the first invoice's Income.
    await expectLater(closure.close('test-shop',['one','two'],isOwner:true),throwsStateError);
    expect((await db.customSelect('SELECT * FROM local_invoice_closures').get()),isEmpty);
    final store = LocalInvoiceClosureStore(db); await store.prepareIncome();
    expect(await store.finalizedIncome('test-shop'),isEmpty);
    await cache.save('test-shop','two',fixture('two'));
    final plan = await closure.preview('test-shop',['one'],isOwner:true);
    final changed = fixture('one');
    (changed['payments'] as List).last['payment_date'] = '2026-11-14';
    await cache.save('test-shop','one',changed);
    await expectLater(closure.close('test-shop',['one'],isOwner:true,confirmed:plan),throwsStateError);
    expect(await store.finalizedIncome('test-shop'),isEmpty);
    await cache.save('test-shop','one',fixture('one'));
    final valid = await closure.preview('test-shop',['one','two'],isOwner:true);
    await closure.close('test-shop',['one','two'],isOwner:true,confirmed:valid);
    await closure.close('test-shop',['one','two'],isOwner:true);
    final income = await store.finalizedIncome('test-shop');
    expect(income,hasLength(2));
    expect(income.every((r) => r['transaction_date']=='2026-11-13' && r['amount']==99.75),isTrue);
    await db.close(); db = BriskersLocalDatabase(NativeDatabase(file));
    cache = LocalDocumentDetailCache(database:db); closure = LocalInvoiceClosure(database:db);
    await closure.close('test-shop',['one','two'],isOwner:true);
    expect(await LocalInvoiceClosureStore(db).finalizedIncome('test-shop'),income);
    expect(DocumentPresentation((await cache.loadReadOnly('test-shop','one'))!).isClosed,isTrue);
    // Historical closed data is not retroactively finalized.
    await cache.save('test-shop','historical', fixture('historical'));
    final finalization = OfflineInvoiceFinalization(database: db);
    await finalization.save('test-shop',['historical'],isOwner:true,close:false);
    await cache.save('test-shop','historical', {...fixture('historical'),'status':'closed','closed_at':'2026-11-01'});
    await finalization.finalizeLocally('test-shop','historical',isOwner:true,resumeSavedRequest:true);
    await closure.close('test-shop',['historical'],isOwner:true);
    expect(await LocalInvoiceClosureStore(db).finalizedIncome('test-shop'),income);
    // An older local close can outrank an unrefreshed issued detail, too.
    await cache.save('test-shop','old-local-close',fixture('old-local-close'));
    await finalization.save('test-shop',['old-local-close'],isOwner:true,close:false);
    await db.customStatement("INSERT INTO local_invoice_closures(business_id,invoice_id,closed_at,operation_id,payload) VALUES('test-shop','old-local-close','2026-11-01','historical-close','{}')");
    await finalization.finalizeLocally('test-shop','old-local-close',isOwner:true,resumeSavedRequest:true);
    expect(await LocalInvoiceClosureStore(db).finalizedIncome('test-shop'),income);
  });
}
