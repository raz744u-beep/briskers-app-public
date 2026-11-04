import 'dart:convert';
import 'dart:io';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/recovery_commit_store.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/local_job_graph_delete.dart';
import 'package:briskers_app/services/local_number_allocator.dart';
import 'package:briskers_app/services/local_invoice_number_service.dart';
import 'package:briskers_app/services/offline_customer_vehicle_admin_service.dart';
import 'package:briskers_app/services/offline_document_draft_service.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';

class Store implements OwnerEnrollmentStore {
  @override Future<String?> read() async=>null;
  @override Future<void> write(String value) async { throw StateError('No online enrollment'); }
  @override Future<void> clear() async {}
}
const business='test-business';
const identity=OwnerSessionIdentity('owner','saved-session');
LocalOwnerAuthorization authority({bool unlock=true})=>LocalOwnerAuthorization(
  store:Store(),currentIdentity:()=>identity,
  verifyOwner:(_) async=>throw StateError('Network must not be called'),
  verifyLocalOwner:(b) async=>VerifiedOwnerEnrollment(identity,b),
  authenticateDevice:() async=>unlock);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BriskersLocalDatabase db;
  late LocalDocumentDetailCache cache;
  late OfflineDocumentDraftService drafts;
  late String customer,vehicle;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir=await Directory.systemTemp.createTemp('owner-offline-');
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/data.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    cache=LocalDocumentDetailCache(database:db);
    drafts=OfflineDocumentDraftService(database:db,cache:cache);
    final people=OfflineCustomerVehicleAdminService(database:db);
    customer=await people.queueCustomerCreate(business,name:'Synthetic test customer');
    vehicle=await people.queueVehicle(business,customer,make:'Test',model:'Car',year:2020);
    await db.customStatement("INSERT INTO local_documents (id,business_id,kind,document_number,total,sync_state) VALUES ('unrelated',?,'invoice','7300',400,'synced')",[business]);
  });
  tearDown(() async {
    LocalDocumentDetailCache.sqliteWritesEnabled=false;
    await db.close(); await dir.delete(recursive:true);
  });
  Future<String> create()=>drafts.createQuickInvoice(business,customerId:customer,
    customerName:'Synthetic test customer',vehicleId:vehicle,vehicleLabel:'Test Car');
  Future<void> purge(String invoice) async {
    final detail=(await cache.load(business,invoice))!;
    final grant=await authority().authorizeLocal(business);
    final engine=LocalJobGraphDelete.ownerDirected(db,ownerGrant:grant);
    final rows=await engine.preview(businessId:business,jobId:detail['job_id'],actorId:identity.actorId);
    await engine.confirm(businessId:business,jobId:detail['job_id'],actorId:identity.actorId,reviewed:rows);
  }

  test('complete offline chain, payment, deletion, restart and latest number reuse',() async {
    final invoice=await create();
    await drafts.addLine(business,invoice,name:'Labor',quantity:2,unitPrice:100,taxRate:0,lineKind:'labor');
    await drafts.addLine(business,invoice,name:'Part',quantity:1,unitPrice:50,taxRate:0,lineKind:'item');
    final detail=(await cache.load(business,invoice))!;
    expect(detail['document_number'],'7301');
    expect(detail['total_amount'],250);
    await OfflineInvoicePaymentLedger(database:db).recordReceivedPayment(business,invoice,
      amount:250,remainingBeforePaymentCents:25000,methodId:'cash',methodName:'Cash');
    await db.customStatement('INSERT INTO local_financial_cache (business_id,cache_key,payload_json) VALUES (?,?,?)',
      [business,'audit',jsonEncode([{'job_id':detail['job_id'],'invoice_id':invoice,'amount':250},{'job_id':'another-job','amount':42}])]);
    // A pre-existing recovered invoice and its original payment are unrelated.
    await RecoveryCommitStore.ensure(db);
    final recovered={'id':'unrelated','document_number':'7300','job_id':'original-job',
      'total_amount':400,'payments':[{'id':'original-payment','amount':400}]};
    final recoveryRaw=jsonEncode(recovered);
    await db.customStatement('INSERT INTO recovery_document_cache VALUES (?,?,?)',[business,'unrelated',recoveryRaw]);
    await db.customStatement('INSERT INTO recovery_commits (business_id,local_invoice_id,server_invoice_id,identities_json,original_json,proof_json) VALUES (?,?,?,?,?,?)',
      [business,'original-alias','unrelated','{}',recoveryRaw,'{}']);
    final originalRows=(await db.customSelect('SELECT * FROM recovery_commits').get()).map((r)=>r.data).toList();
    await purge(invoice);
    expect(await cache.load(business,'unrelated'),recovered);
    expect((await db.customSelect('SELECT * FROM recovery_commits').get()).map((r)=>r.data).toList(),originalRows);
    expect(await LocalJobRetirement.isDocumentBlocked(db,business,invoice),isTrue);
    expect(await cache.load(business,invoice),isNull);
    expect((await db.customSelect('SELECT * FROM local_jobs').get()),isEmpty);
    expect((await db.customSelect('SELECT * FROM local_job_visits').get()),isEmpty);
    expect((await db.customSelect('SELECT * FROM local_documents').get()).single.data['id'],'unrelated');
    expect((await db.customSelect("SELECT * FROM sync_outbox WHERE entity_type IN ('invoice_payment_received','document_draft_create')").get()),isEmpty);
    expect((await db.customSelect('SELECT * FROM local_customers').get()).length,1);
    expect((await db.customSelect('SELECT * FROM local_vehicles').get()).length,1);
    expect(jsonDecode((await db.customSelect("SELECT payload_json FROM local_financial_cache WHERE cache_key='audit'").getSingle()).read<String>('payload_json')),[{'job_id':'another-job','amount':42}]);
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/data.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    cache=LocalDocumentDetailCache(database:db);
    drafts=OfflineDocumentDraftService(database:db,cache:cache);
    expect(await cache.load(business,invoice),isNull);
    final next=await create();
    final replacement=(await cache.load(business,next))!;
    expect(replacement['document_number'],'7301');
    expect(replacement['job_number'],detail['job_number']);
    await cache.save(business,invoice,detail);
    expect(await cache.load(business,invoice),isNull);
  });

  test('regular Job creation adds an invoice to the same Job and deletes the full paid chain',() async {
    final job=await OfflineJobAdminService(database:db).queueJobCreate(business,
      customerId:customer,customerName:'Test customer',vehicleId:vehicle,title:'Test labor');
    final invoice=await drafts.createQuickInvoice(business,existingJobId:job,
      customerId:customer,customerName:'Test customer',vehicleId:vehicle,
      initialLines:[{'name':'Labor','quantity':1,'unit_price':25,'tax_rate':0,'line_kind':'labor'}]);
    expect((await db.customSelect('SELECT * FROM local_jobs').get()).length,1);
    expect((await cache.load(business,invoice))!['job_id'],job);
    await OfflineInvoicePaymentLedger(database:db).recordReceivedPayment(business,invoice,
      amount:25,remainingBeforePaymentCents:2500,methodId:'cash',methodName:'Cash');
    await purge(invoice);
    expect((await db.customSelect('SELECT * FROM local_jobs').get()),isEmpty);
    expect((await db.customSelect("SELECT * FROM sync_outbox WHERE entity_type IN ('job_create','document_draft_create','invoice_payment_received')").get()),isEmpty);
    expect(await LocalNumberAllocator(db).nextNumber(business,'job'),1);
  });

  test('sequential paid deletions retain shared totals and tolerate old immutable cache markers',() async {
    final first=await create();
    final firstJob=(await cache.load(business,first))!['job_id'] as String;
    final second=await create();
    final keep=await create();
    final ledger=OfflineInvoicePaymentLedger(database:db);
    for(final invoice in [first,second,keep]) {
      await ledger.recordReceivedPayment(business,invoice,amount:25,
        remainingBeforePaymentCents:2500,methodId:'cash',methodName:'Cash');
    }
    const key='financial_totals_local_delta_v1';
    Future<Map<String,dynamic>> journal() async => Map<String,dynamic>.from(jsonDecode(
      (await db.customSelect("SELECT payload_json FROM local_financial_cache WHERE cache_key='financial_totals_local_delta_v1'").getSingle()).read<String>('payload_json')) as Map);
    final before=await journal();
    final retained=before.entries.where((e)=>jsonEncode(e.value).contains(keep)).single;
    await purge(first);
    expect((await db.customSelect("SELECT * FROM local_offline_job_purge_entities WHERE entity_kind='financial_cache'").get()),isEmpty);
    // Reproduce the immutable marker left by an older installed version.
    await db.customStatement('INSERT INTO local_offline_job_purge_entities VALUES (?,?,?,?,?)',
      [business,firstJob,'old-delete','financial_cache',key]);
    await db.customStatement("CREATE TRIGGER old_cancel_no_replace BEFORE INSERT ON local_offline_job_purge_entities WHEN EXISTS(SELECT 1 FROM local_offline_job_purge_entities e WHERE e.business_id=NEW.business_id AND e.entity_kind=NEW.entity_kind AND e.entity_id=NEW.entity_id AND (e.job_id<>NEW.job_id OR e.operation_id<>NEW.operation_id)) BEGIN SELECT RAISE(ABORT,'Canceled identities cannot be replaced'); END");
    final markers=(await db.customSelect("SELECT * FROM local_offline_job_purge_entities WHERE entity_kind='financial_cache'").get()).map((r)=>r.data).toList();
    await purge(second);
    expect(await cache.load(business,second),isNull);
    expect((await journal())[retained.key],retained.value);
    expect(await cache.load(business,keep),isNotNull);
    expect((await db.customSelect("SELECT * FROM local_offline_job_purge_entities WHERE entity_kind='financial_cache'").get()).map((r)=>r.data).toList(),markers);
    await expectLater(db.customStatement('INSERT INTO local_offline_job_purge_entities VALUES (?,?,?,?,?)',
      [business,'another-job','another-delete','financial_cache',key]),throwsA(anything));
    // The same shared container remains writable after both deletions.
    await ledger.recordReceivedPayment(business,keep,amount:5,
      remainingBeforePaymentCents:500,methodId:'cash',methodName:'Cash');
    expect((await journal())[retained.key],retained.value);
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/data.sqlite')));
    await LocalDocumentDetailCache.initialize(db);
    cache=LocalDocumentDetailCache(database:db);
    drafts=OfflineDocumentDraftService(database:db,cache:cache);
    expect(await cache.load(business,second),isNull);
    expect(await cache.load(business,keep),isNotNull);
    await purge(keep);
    expect(await cache.load(business,keep),isNull);
    final replacement=await create();
    expect((await cache.load(business,replacement))!['document_number'],'7301');
  });

  test('older number stays manual; duplicates reject and old reservation rolls back',() async {
    final first=await create();
    final second=await create();
    await purge(first);
    final third=await create();
    expect((await cache.load(business,third))!['document_number'],'7303');
    final grant=await authority().authorizeLocal(business);
    final service=LocalInvoiceNumberService(db);
    await service.assign(business,third,7301,grant);
    expect((await cache.load(business,third))!['document_number'],'7301');
    await expectLater(service.assign(business,third,7302,grant),throwsStateError);
    expect((await cache.load(business,third))!['document_number'],'7301');
    expect((await cache.load(business,second))!['document_number'],'7302');
  });

  test('concurrent allocations cannot receive the same number',() async {
    final numbers=LocalNumberAllocator(db);
    final values=await Future.wait(List.generate(10,(i)=>numbers.allocate(business,'invoice','item-$i')));
    expect(values.toSet().length,10);
  });

  test('rollback retains details, payment, number reservation and all graph rows',() async {
    final invoice=await create();
    await OfflineInvoicePaymentLedger(database:db).recordReceivedPayment(business,invoice,
      amount:10,remainingBeforePaymentCents:1000,methodId:'cash',methodName:'Cash');
    await db.customStatement("CREATE TRIGGER fail_job_delete BEFORE DELETE ON local_jobs BEGIN SELECT RAISE(ABORT,'injected failure'); END");
    await expectLater(purge(invoice),throwsA(anything));
    expect(await cache.load(business,invoice),isNotNull);
    expect((await db.customSelect("SELECT * FROM sync_outbox WHERE entity_type='invoice_payment_received'").get()).length,1);
    expect((await db.customSelect('SELECT * FROM local_offline_job_purge_entities').get()),isEmpty);
    expect((await db.customSelect("SELECT * FROM local_number_reservations WHERE kind='invoice' AND active=1").get()).length,1);
  });

  test('Owner may delete paid synchronized rows; cancelling device unlock grants nothing',() async {
    await expectLater(authority(unlock:false).authorizeLocal(business),throwsStateError);
    final invoice=await create();
    final detail=(await cache.load(business,invoice))!;
    await db.customStatement("UPDATE local_documents SET sync_state='synced',status='paid',closed_at=1 WHERE id=?",[invoice]);
    await db.customStatement("UPDATE local_jobs SET sync_state='synced',payment_state='paid' WHERE id=?",[detail['job_id']]);
    await purge(invoice);
    expect(await cache.load(business,invoice),isNull);
  });

  test('invoice changes after preview require a new confirmation',() async {
    final invoice=await create();
    final detail=(await cache.load(business,invoice))!;
    final grant=await authority().authorizeLocal(business);
    final deletion=LocalJobGraphDelete.ownerDirected(db,ownerGrant:grant);
    final reviewed=await deletion.preview(businessId:business,jobId:detail['job_id'],actorId:identity.actorId);
    await drafts.addLine(business,invoice,name:'Extra work',quantity:1,unitPrice:50,taxRate:0,lineKind:'labor');
    await expectLater(deletion.confirm(businessId:business,jobId:detail['job_id'],actorId:identity.actorId,reviewed:reviewed),throwsStateError);
    expect(await cache.load(business,invoice),isNotNull);
  });
}
