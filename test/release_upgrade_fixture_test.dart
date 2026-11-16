import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_lan_identity.dart';
import 'package:briskers_app/services/payroll_owner_lease.dart';

class _Enrollment implements OwnerEnrollmentStore {
  @override Future<String?> read() async => null;
  @override Future<void> write(String value) async {}
  @override Future<void> clear() async {}
}

// This file also runs against the exact b2568 source during packaging. It uses
// only APIs present in that baseline, and never enrolls a real Owner/device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['BRISKERS_UPGRADE_FIXTURE'];
  test('export representative b2568 upgrade records through production APIs', () async {
    SharedPreferences.setMockInitialValues({});
    final file = File(output!);
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();
    final db = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(() async { await db.close(); LocalDocumentDetailCache.sqliteWritesEnabled = false; });
    const who = OwnerSessionIdentity('synthetic-owner', 'upgrade-test');
    final auth = LocalOwnerAuthorization(store: _Enrollment(), currentIdentity: () => who,
      verifyOwner: (_) async => throw StateError('Offline fixture'), authenticateDevice: () async => true,
      verifyLocalOwner: (shop) async => VerifiedOwnerEnrollment(who, shop));
    final grant = await auth.authorizeLocal('upgrade-shop');
    final identity = await PayrollLanIdentity.fromSeed(List.filled(32, 9));
    final secure = <String, String>{};
    final lease = PayrollOwnerLease(identity: identity, business: 'upgrade-shop', anchor: identity.deviceId,
      read: (key) async => secure[key], write: (key, value) async { secure[key] = value; });
    await lease.migrate(grant);
    final repo = LocalPayrollRepository(db, business: 'upgrade-shop', owner: true,
      deviceId: identity.deviceId, ownerProof: await lease.proof(grant));
    await LocalDocumentDetailCache.initialize(db);
    await repo.prepare();
    await db.customStatement("INSERT INTO local_customers(id,business_id,display_name) VALUES('customer','upgrade-shop','Synthetic Upgrade Customer')");
    await db.customStatement("INSERT INTO local_vehicles(id,business_id,year,make,model) VALUES('vehicle','upgrade-shop',2021,'Synthetic','SUV')");
    await db.customStatement("INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES('upgrade-shop','customer','vehicle')");
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_id,vehicle_id) VALUES('job','upgrade-shop','owner','Synthetic repair','open','J-UPGRADE','customer','vehicle')");
    await db.customStatement("INSERT INTO local_documents(id,business_id,job_id,kind,document_number) VALUES('invoice','upgrade-shop','job','invoice','UPGRADE-1')");
    await db.customStatement("INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES('assignment','upgrade-shop','job','mechanic','Synthetic Mechanic')");
    await LocalDocumentDetailCache(database: db).save('upgrade-shop', 'invoice', {
      'id':'invoice','kind':'invoice','job_id':'job','total_amount':100,
      'lines':[{'id':'labor','line_kind':'labor','description':'Synthetic repair','quantity':1,'unit_price':100}]
    });
    await repo.registerAssignedLabor(jobId:'job',invoiceId:'invoice',lineId:'labor',
      employeeId:'mechanic',employeeName:'Synthetic Mechanic',rateCents:4000);
    final work = (await repo.work(employee:'mechanic')).single;
    await repo.updateWork(work['id'] as String,'In Progress',0,'2026-11-05');
    await repo.updateWork(work['id'] as String,'Done',100,'2026-11-05');
    final earned = (await repo.work(employee:'mechanic')).single;
    expect(await repo.verify(operation:'upgrade-payment',employee:'mechanic',week:'2026-11-02',
      date:'2026-11-05',method:'Cash',selected:[earned],base:0,hourlyAdjustment:0,
      adjustmentReason:'',repayment:0,confirmedNet:4000), isTrue);
    expect(await repo.history('mechanic'), hasLength(1));
    await repo.addShopTask('mechanic','Synthetic general task','General');
    await db.customStatement('INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES(?,?,?)',
      ['upgrade-shop','transactions_snapshot',jsonEncode([{'id':'expense','business_id':'upgrade-shop','direction':'expense','amount':105.29,'payee':'Synthetic Vendor','transaction_date':'2026-11-05'}])]);
    for (final state in ['pending','conflict']) {
      await db.customStatement('INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,last_error) VALUES(?,?,?,?,?,?,?)',
        ['upgrade-shop','invoice','synthetic-$state','update','{"synthetic":true}',state,state == 'conflict' ? 'Invoice changed elsewhere' : null]);
    }
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('briskers_connection_mode','offline');
    await prefs.setString('upgrade_preference_marker','preserve-b2568');
    await prefs.setString('briskers_job_employees_upgrade-shop',jsonEncode([{'id':'mechanic','name':'Synthetic Mechanic','position':'Mechanic'}]));
    await File('$output.prefs.json').writeAsString(jsonEncode({for(final key in prefs.getKeys()) key:prefs.get(key)}));
  }, skip: output == null ? 'Release-only baseline fixture export' : false);
}
