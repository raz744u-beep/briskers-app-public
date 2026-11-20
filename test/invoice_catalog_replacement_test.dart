import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/widgets/invoice_item_picker.dart';

class _Api extends BriskersApi {
  Map<String,dynamic> detail = {
    'id':'invoice', 'kind':'invoice', 'status':'open', 'row_version':1,
    'lines':[{'id':'original-line', 'item_id':'wrong-part', 'name':'Wrong part',
      'line_kind':'item', 'quantity':2, 'unit_price':10, 'tax_rate':0}],
  };
  int calls = 0;
  @override
  Future<Map<String,dynamic>> documentDetail(String businessId, String documentId) async =>
    Map<String,dynamic>.from(jsonDecode(jsonEncode(detail)) as Map);
  @override
  Future<void> updateDocumentLineV2(String businessId, String lineId, {
    required int expectedVersion, required String name, required num quantity,
    required num unitPrice, required num taxRate, String? description,
    required String lineKind, String? replacementItemId,
  }) async {
    calls++;
    expect(lineId,'original-line');
    expect(replacementItemId,'correct-part');
    expect(expectedVersion,1);
    detail = {...detail, 'row_version':2, 'total_amount':66,
      'lines':[{'id':lineId, 'item_id':replacementItemId, 'name':name,
        'description':description, 'quantity':quantity, 'unit_price':unitPrice,
        'tax_rate':taxRate, 'line_kind':lineKind}]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => LocalDocumentDetailCache.sqliteWritesEnabled = false);

  test('catalog replacement survives restart and replays on the same line', () async {
    final dir=await Directory.systemTemp.createTemp('catalog-replacement');
    addTearDown(() => dir.delete(recursive:true));
    final file=File('${dir.path}/db.sqlite');
    var db=BriskersLocalDatabase(NativeDatabase(file));
    await LocalDocumentDetailCache.initialize(db);
    var cache=LocalDocumentDetailCache(database:db);
    final api=_Api();
    await cache.save('shop','invoice',api.detail);
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,status,total,row_version) VALUES('invoice','shop','invoice','open',20,1)");
    var service=OfflineDocumentEditService(api:api,cache:cache,database:db);
    await service.updateLine('shop','invoice','original-line',name:'Correct part',
      replacementItemId:'correct-part',replacementPricingUnit:'each',description:'Selected from catalog',
      quantity:2,unitPrice:30,taxRate:.1,lineKind:'item');
    expect(api.calls,0);
    final saved=(await cache.load('shop','invoice'))!;
    expect(saved['total_amount'],66);
    expect((saved['lines'] as List).single,containsPair('id','original-line'));
    expect((saved['lines'] as List).single,containsPair('item_id','correct-part'));
    expect((saved['lines'] as List).single,containsPair('pricing_unit','each'));
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    cache=LocalDocumentDetailCache(database:db);
    service=OfflineDocumentEditService(api:api,cache:cache,database:db);
    final restarted=(await cache.load('shop','invoice'))!;
    expect((restarted['lines'] as List).single,containsPair('item_id','correct-part'));
    final queued=await db.customSelect("SELECT payload_json FROM sync_outbox WHERE entity_type='document_edit' AND state='pending'").get();
    expect(queued,hasLength(1));
    expect(jsonDecode(queued.single.read<String>('payload_json')),containsPair('replacement_item_id','correct-part'));
    await service.flush('shop');
    expect(api.calls,1);
    expect((api.detail['lines'] as List).single,containsPair('id','original-line'));
    expect(await db.customSelect("SELECT id FROM sync_outbox WHERE entity_type='document_edit' AND state='pending'").get(),isEmpty);
  });

  test('unsynced draft replaces catalog link while keeping line ID and quantity', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    final service=OfflineDocumentDraftService(database:db);
    final id=await service.createStandaloneEstimate('shop',customerId:'customer',
      customerName:'Customer',initialLines:[{
        'name':'Wrong part','item_id':'wrong-part','quantity':2,
        'unit_price':10,'tax_rate':0,'line_kind':'item',
      }]);
    final cache=LocalDocumentDetailCache(database:db);
    final before=(await cache.load('shop',id))!;
    final lineId=((before['lines'] as List).single as Map)['id'].toString();
    await service.updateLine('shop',id,lineId,name:'Correct part',
      replacementItemId:'correct-part',quantity:2,unitPrice:30,taxRate:.1,lineKind:'item');
    final after=(await cache.load('shop',id))!;
    expect(after['total_amount'],66);
    expect((after['lines'] as List).single,containsPair('id',lineId));
    expect((after['lines'] as List).single,containsPair('quantity',2));
    expect((after['lines'] as List).single,containsPair('item_id','correct-part'));
  });

  test('replacement cannot turn allocated labor into a part', () async {
    final db=BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await LocalDocumentDetailCache.initialize(db);
    final cache=LocalDocumentDetailCache(database:db);
    await cache.save('shop','invoice',{'id':'invoice','kind':'invoice','status':'open',
      'lines':[{'id':'engine','name':'Labor','line_kind':'item','quantity':18,'unit_price':150}]});
    await expectLater(OfflineDocumentEditService(database:db,cache:cache)
      .updateLine('shop','invoice','engine',name:'Part',replacementItemId:'part',
        quantity:18,unitPrice:150,taxRate:0,lineKind:'item'),throwsStateError);
    expect(((await cache.load('shop','invoice'))!['lines'] as List).single,containsPair('name','Labor'));
    expect(await db.customSelect('SELECT id FROM sync_outbox').get(),isEmpty);
  });

  testWidgets('saved catalog search returns the selected item identity', (tester) async {
    Map<String,dynamic>? selected;
    await tester.pumpWidget(MaterialApp(home:Builder(builder:(context) => Scaffold(
      body:TextButton(onPressed:() async {
        selected=await showModalBottomSheet<Map<String,dynamic>>(context:context,
          isScrollControlled:true,builder:(_) => const InvoiceItemPicker(accent:Colors.teal,items:[
            {'id':'wrong','name':'Oil filter','selling_price':12},
            {'id':'correct','name':'Air filter','selling_price':24},
          ]));
      },child:const Text('Replace'))))));
    await tester.tap(find.text('Replace')); await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'air'); await tester.pump();
    expect(find.text('Oil filter'),findsNothing);
    await tester.tap(find.text('Air filter')); await tester.pumpAndSettle();
    expect(selected,containsPair('id','correct'));
  });
}
