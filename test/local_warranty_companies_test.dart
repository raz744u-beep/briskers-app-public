import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_warranty_companies.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/offline_document_edit_service.dart';
import 'package:briskers_app/core/connection_mode.dart';

class _Api extends BriskersApi {
  final companies = <Map<String, dynamic>>[];
  int creates = 0;
  int reads = 0;
  int warrantyUpdates = 0;
  int noteUpdates = 0;
  String? linkedCompany;
  bool loseCreateReply = false;
  Completer<void>? updating;

  @override
  Future<List<Map<String, dynamic>>> warrantyCompanies(String businessId,
      {bool includeInactive = false}) async {
    reads++;
    return companies.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<String> createWarrantyCompany(String businessId, {required String name,
      String? claimsPhone, String? submissionEmail}) async {
    creates++;
    companies.add({'id':'server-company','name':name,'claims_phone':claimsPhone,
      'submission_email':submissionEmail,'active':true});
    if (loseCreateReply) throw StateError('Reply interrupted');
    return 'server-company';
  }

  @override
  Future<void> updateWarrantyCompany(String businessId, String companyId,
      {required String name, String? claimsPhone, String? submissionEmail,
      String? portalUrl, String? notes, bool active = true}) async {
    if (updating != null) await updating!.future;
    final index = companies.indexWhere((row) => row['id'] == companyId);
    companies[index] = {'id':companyId,'name':name,'claims_phone':claimsPhone,
      'submission_email':submissionEmail,'portal_url':portalUrl,'notes':notes,'active':active};
  }
  @override
  Future<Map<String,dynamic>> documentDetail(String businessId, String documentId) async => {
    'id':documentId,'kind':'invoice','origin':'native','status':'issued',
    'legacy_read_only':false,'row_version':1 + warrantyUpdates,
    'total_amount':100,'paid_amount':0,'lines':<Map<String,dynamic>>[],
  };

  @override
  Future<Map<String,dynamic>> documentWarrantyDetail(String businessId, String documentId) async => {
    'extended_warranty':true,'warranty_company_id':linkedCompany,
  };

  @override
  Future<Map<String,dynamic>> updateDocumentWarranty(String businessId, String documentId,
      {required int expectedVersion, required bool extendedWarranty,
      String? warrantyCompanyId, String? claimNumber, String? authorizationNumber,
      num? approvedAmount, num surchargeRate = .03}) async {
    warrantyUpdates++;
    linkedCompany = warrantyCompanyId;
    return {};
  }

  @override
  Future<void> updateDocumentNotes(String businessId, String documentId,
      {required int expectedVersion, String? memo}) async {
    noteUpdates++;
    throw StateError('Warranty must use its own update endpoint.');
  }

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline company create and edit persist all fields across database restart', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('warranty-local-');
    final file = File('${directory.path}/shop.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async { await db.close(); await directory.delete(recursive:true); });
    final api = _Api();
    final service = LocalWarrantyCompanies(database:db,api:api,canSync:()=>false);
    final id = await service.save('shop',name:'endurance',claimsPhone:'800-123-4567',
      submissionEmail:'claims@example.test',portalUrl:'https://example.test',notes:'Call first');
    await service.flush('shop');
    await db.close();
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase(file));
    final reopened = LocalWarrantyCompanies(database:db,api:api,canSync:()=>false);
    final row = (await reopened.available('shop')).single;
    expect(row['id'],id);
    expect(row['name'],'Endurance');
    expect(row['claims_phone'],'800-123-4567');
    expect(row['submission_email'],'claims@example.test');
    expect(row['portal_url'],'https://example.test');
    expect(row['notes'],'Call first');
    await reopened.save('shop',id:id,name:'Endurance',notes:'Updated',active:false);
    expect(await reopened.cached('shop'),isEmpty);
    expect((await reopened.cached('shop',includeInactive:true)).single['notes'],'Updated');
    expect(api.creates,0);
  });

  test('interrupted create reply is recovered without a duplicate company', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _Api()..loseCreateReply=true;
    final service = LocalWarrantyCompanies(database:db,api:api,canSync:()=>true);
    final id = await service.save('shop',name:'Warranty',portalUrl:'https://example.test',notes:'Keep this');
    await expectLater(service.flush('shop'),throwsStateError);
    api.loseCreateReply=false;
    await Future.wait([service.flush('shop'),service.flush('shop')]);
    final reads = api.reads;
    expect(await service.serverId('shop',id),'server-company');
    expect(api.reads,reads);
    expect(api.creates,1);
    expect((await service.cached('shop')).single['id'],id);
    expect(api.companies.single['notes'],'Keep this');
    await expectLater(service.save('shop',name:'warranty'),throwsStateError);
  });

  test('a local edit made during synchronization remains queued', () async {
    SharedPreferences.setMockInitialValues({});
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _Api()..updating=Completer<void>();
    final service = LocalWarrantyCompanies(database:db,api:api,canSync:()=>true);
    final id = await service.save('shop',name:'Company',notes:'First');
    final flush = service.flush('shop');
    while (api.creates == 0) { await Future<void>.delayed(Duration.zero); }
    await service.save('shop',id:id,name:'Company',notes:'Newest');
    api.updating!.complete();
    await flush;
    expect((await service.cached('shop')).single['notes'],'Newest');
    await service.flush('shop');
    expect(api.companies.single['notes'],'Newest');
    expect(api.creates,1);
  });
  test('saved invoice warranty resolves a local company through the warranty endpoint', () async {
    SharedPreferences.setMockInitialValues({});
    await BriskersConnectionModeController.instance.setMode(BriskersConnectionMode.auto);
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _Api();
    final companies = LocalWarrantyCompanies(database:db,api:api,canSync:()=>true);
    final id = await companies.save('shop',name:'Company');
    final cache = LocalDocumentDetailCache(database:db);
    await cache.save('shop','invoice',await api.documentDetail('shop','invoice'));
    await db.customStatement("INSERT INTO local_documents(id,business_id,kind,status,total,row_version) "
      "VALUES('invoice','shop','invoice','issued',100,1)");
    final edits = OfflineDocumentEditService(database:db,cache:cache,api:api);
    await edits.saveWarranty('shop','invoice',{
      'extended_warranty':true,'warranty_company_id':id,'warranty_company_name':'Company',
      'approved_amount':90,'claim_number':'CLAIM','surcharge_rate':.03,
    });
    await edits.flush('shop');
    expect(api.warrantyUpdates,1);
    expect(api.linkedCompany,'server-company');
    expect(api.noteUpdates,0);
    expect(api.creates,1);
    expect((await cache.load('shop','invoice'))!['total_amount'],100);
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(),isEmpty);
  });

}
