import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:briskers_app/services/local_number_evidence.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prefilled invoice number preview preserves orphan ownership and creation rechecks a concurrent reservation', () async {
    SharedPreferences.setMockInitialValues({});
    final db=BriskersLocalDatabase(NativeDatabase.memory()); addTearDown(db.close);
    final numbers=LocalNumberAllocator(db);
    await LocalDocumentSqlStore.ensure(db);
    final original=jsonEncode({'id':'saved','kind':'invoice','document_number':'6380',
      'job_id':'saved-job','job_number':'J-60','lines':[{'name':List.filled(100000,'x').join()}],
      'payments':[{'id':'receipt','amount':25}],'total_amount':25});
    await LocalDocumentSqlStore.write(db,'briskers_document_detail_shop_saved',original);
    await numbers.setNextNumber('shop','invoice',6380);
    await numbers.setNextNumber('shop','job',60);
    final full=await LocalNumberEvidence.documents(db,'shop');
    final compact=await LocalNumberEvidence.documents(db,'shop',numbersOnly:true);
    expect(compact.single['document_number'],full.single['document_number']);
    expect(compact.single['job_number'],full.single['job_number']);
    expect(compact.single.containsKey('lines'),false);
    expect(compact.single.containsKey('payments'),false);
    final preview=await numbers.invoicePreview('shop');
    expect(preview.nextInvoice,6381); expect(preview.nextJob,61);
    expect(preview.invoices,isEmpty); expect(preview.jobs,isEmpty);
    expect(await numbers.allocate('shop','invoice','another-invoice'),6381);
    expect(await numbers.allocate('shop','invoice','new-invoice'),6382);
    expect(await numbers.allocate('shop','job','new-job'),61);
    expect(await LocalDocumentSqlStore.read(db,'briskers_document_detail_shop_saved'),original);
  });
}
