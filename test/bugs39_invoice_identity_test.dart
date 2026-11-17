import 'package:briskers_app/services/customer_document_summary_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_identity.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_document_sql_store.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_invoice_delete.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';

class _Store implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const business = LocalDocumentIdentity.gloriaBusiness;
  const original = LocalDocumentIdentity.gloriaLocal;
  const remote = LocalDocumentIdentity.gloriaServer;
  const job = 'local-job-${LocalDocumentIdentity.gloriaOperation}';
  late Directory dir;
  late BriskersLocalDatabase db;
  const payments = [{'id':'cash-1','amount':3000.0},{'id':'cash-2','amount':4882.11}];
  late String saved;
  final server = <String,dynamic>{'id':remote,'kind':'invoice','document_number':'6359',
    'status':'issued','customer_id':'remote-customer','total_amount':7882.11,'job_id':'c6a23164-c09a-490d-8b00-c3e84e7282fb'};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('invoice-identity');
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_name,vehicle_label) VALUES (?,?,'owner','Repair','closed','J-40','Gloria Johnson','2016 Audi A8L')",[job,business]);
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number,status,display_status_code,total,sync_state) VALUES (?,?,?,'invoice','6359','closed','closed',7882.11,'synced')",[original,business,job]);
    await db.customStatement("UPDATE local_documents SET customer_id='original-customer' WHERE id=?",[original]);
    await LocalDocumentDetailCache.initialize(db);
    saved = jsonEncode({'id':original,'kind':'invoice','status':'closed','closed_at':'2026-11-16',
      'total_amount':7882.11,'paid_amount':7882.11,'payments':payments,
      'lines':[{'id':'labor','description':'Repair engine','quantity':24.6}]});
    await LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key(business,original),saved);
    await LocalDocumentRepository(database:db).upsertFromServer(business,[server]);
  });
  tearDown(() async { await db.close(); await dir.delete(recursive:true); LocalDocumentDetailCache.sqliteWritesEnabled=false; });

  Future<LocalOwnerGrant> grant() async {
    const identity = OwnerSessionIdentity('owner','session');
    final auth = LocalOwnerAuthorization(store:_Store(),currentIdentity:()=>identity,
      verifyOwner:(_) async => throw StateError('Network must not be used'),
      verifyLocalOwner:(b) async => VerifiedOwnerEnrollment(identity,b),authenticateDevice:() async=>true);
    return auth.authorizeSession(business);
  }

  test('proven alias merges only listings, retaining original Closed record and payments across restart and download',() async {
    var repo = LocalDocumentRepository(database:db);
    var rows = await repo.listByKind(business,kind:'invoice');
    expect(rows.map((r)=>r['id']),[original]);
    expect(rows.single['display_status'],'Closed');
    expect(rows.single['vehicle'],'2016 Audi A8L');
    expect(await LocalDocumentIdentity(db).canonicalId(business,remote),original);
    final projected = await LocalDocumentIdentity(db).projectRows(business,[server],rows);
    expect(projected.single['id'],original);
    expect(projected.single['display_status'],'Closed');
    await repo.replaceFromServer(business,[server],kind:'invoice');
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    repo = LocalDocumentRepository(database:db);
    await repo.upsertFromServer(business,[server]);
    rows = await repo.listByKind(business,kind:'invoice');
    expect(rows.map((r)=>r['id']),[original]);
    expect(rows.single['display_status'],'Closed');
    expect(await LocalDocumentSqlStore.read(db,LocalDocumentDetailCache.key(business,original)),saved);
    expect((jsonDecode(saved) as Map)['payments'],payments);
    expect((await db.customSelect('SELECT * FROM local_documents').get()).length,2);
  });

  test('equal public numbers on separate IDs remain separate; selected-only deletion survives restart and replay',() async {
    final separate = {...server,'id':'separate-record'};
    var repo=LocalDocumentRepository(database:db);
    await repo.upsertFromServer(business,[separate]);
    expect((await repo.listByKind(business,kind:'invoice')).length,2);
    await LocalInvoiceDelete(db).remove(businessId:business,invoiceId:'separate-record',ownerGrant:await grant());
    expect(await LocalJobRetirement.isDocumentBlocked(db,business,'separate-record'),isTrue);
    await db.close();
    db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    repo=LocalDocumentRepository(database:db);
    await repo.replaceFromServer(business,[server,separate],kind:'invoice');
    expect((await repo.listByKind(business,kind:'invoice')).map((r)=>r['id']),[original]);
    expect((await db.customSelect('SELECT * FROM local_jobs').get()).length,1);
    expect((await db.customSelect('SELECT * FROM local_invoice_delete_audit').get()).length,1);
    expect(await LocalDocumentSqlStore.read(db,LocalDocumentDetailCache.key(business,original)),saved);
    await expectLater(LocalDocumentSqlStore.write(db,LocalDocumentDetailCache.key(business,'separate-record'),'{}'),throwsA(anything));
  });

  test('customer history resolves both local and server customer IDs to the complete Closed invoice',() async {
    final summaries=CustomerDocumentSummaryService(database:db);
    for (final customer in ['original-customer','remote-customer']) {
      final rows=await summaries.forCustomer(business,customer,includeClosed:true);
      expect(rows.map((row)=>row['id']),[original]);
      expect(rows.single['status'],'closed');
      expect(rows.single['payments'],payments);
    }
    final detail=await summaries.hydrate(business,server);
    expect(detail['id'],original);
    expect(detail['payments'],payments);
  });

  test('stale alias deletion is refused, preserving canonical invoice',() async {
    await expectLater(LocalInvoiceDelete(db).remove(businessId:business,invoiceId:remote,ownerGrant:await grant()),throwsStateError);
    expect(await LocalDocumentSqlStore.read(db,LocalDocumentDetailCache.key(business,original)),saved);
  });

  test('known alias is not applied when canonical invoice verification fails',() async {
    await db.customStatement('DELETE FROM local_document_identity_aliases');
    await db.customStatement("UPDATE local_documents SET document_number='9999' WHERE id=?",[original]);
    expect(await LocalDocumentIdentity(db).canonicalId(business,remote),remote);
    expect((await LocalDocumentRepository(database:db).listByKind(business,kind:'invoice')).length,2);
  });
}
