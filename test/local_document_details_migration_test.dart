import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('upgrade preserves invoice detail and business rows; stale legacy copies never return',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final key=LocalDocumentDetailCache.key('shop','original-invoice');
    final original={'id':'original-invoice','document_number':'7300','total_amount':1250.50,
      'payments':[{'id':'original-payment','amount':250}],
      'lines':List.generate(18,(i)=>{'id':'line-$i','name':'Original line $i'})};
    SharedPreferences.setMockInitialValues({key:jsonEncode(original),'unrelated_setting':'keep'});
    await db.customStatement("INSERT INTO local_documents (id,business_id,kind,document_number,total) VALUES ('original-invoice','shop','invoice','7300',1250.50)");
    final before=(await db.customSelect('SELECT * FROM local_documents').getSingle()).data;
    try {
      await LocalDocumentDetailCache.initialize(db);
      final cache=LocalDocumentDetailCache(database:db);
      expect(await cache.load('shop','original-invoice'),original);
      expect((await db.customSelect('SELECT * FROM local_documents').getSingle()).data,before);
      final prefs=await SharedPreferences.getInstance();
      expect(prefs.getString('unrelated_setting'),'keep');
      // Simulate a preference-cleanup interruption followed by a committed deletion.
      await prefs.setString(key,jsonEncode(original));
      await db.transaction(() async {
        await db.customStatement('INSERT INTO local_document_detail_deleted VALUES (?)',[key]);
        await cache.remove('shop','original-invoice');
      });
      await LocalDocumentDetailCache.initialize(db);
      expect(await cache.load('shop','original-invoice'),isNull);
      await cache.save('shop','original-invoice',original);
      expect(await cache.load('shop','original-invoice'),isNull);
    } finally { LocalDocumentDetailCache.sqliteWritesEnabled=false; await db.close(); }
  });
  test('detail writes roll back with their surrounding database transaction',() async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    final cache=LocalDocumentDetailCache(database:db);
    await LocalDocumentDetailCache.initialize(db);
    try {
      await cache.save('shop','invoice',{'total_amount':10});
      await expectLater(db.transaction(() async {
        await cache.save('shop','invoice',{'total_amount':20});
        throw StateError('Injected failure');
      }),throwsStateError);
      expect(await cache.load('shop','invoice'),{'total_amount':10});
    } finally { LocalDocumentDetailCache.sqliteWritesEnabled=false; await db.close(); }
  });
}
