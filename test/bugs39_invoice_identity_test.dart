import 'support/empty_retirement_gateway.dart';

import 'package:briskers_app/core/job_list_options.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_job_identity.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_job_graph_delete.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/local_payroll_task_identity.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';
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

class _EmptyCleanup extends TestJobCleanupGateway {
  @override
  Future<Map<String, dynamic>> tombstones(String businessId) async => {
    'schema_version': 1,
    'business_id': businessId,
    'deleted_job_ids': <String>[],
    'deleted_document_ids': <String>[],
  };
}

class _GloriaJobsApi extends BriskersApi {
  @override
  Future<Map<String, dynamic>> syncPullJobsBootstrap(
    String businessId, {
    String? afterJobId,
    int limit = 25,
  }) async => {
    'mode': 'bootstrap',
    'bootstrap_cursor': 10,
    'has_more': false,
    'next_job_id': 'c6a23164-c09a-490d-8b00-c3e84e7282fb',
    'bundles': [
      {
        'job': {
          'id': 'c6a23164-c09a-490d-8b00-c3e84e7282fb',
          'business_id': businessId,
          'job_number': 'J-40',
          'title': 'Repair',
          'status': 'open',
          'customer_id': 'remote-customer',
          'customer_name': 'Gloria Johnson',
          'vehicle': '2016 Audi A8L',
          'created_at': '2026-11-03T12:00:00Z',
          'updated_at': '2026-11-03T12:00:00Z',
          'row_version': 1,
        },
        'findings': <dynamic>[],
      },
    ],
  };
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
  Future<void> seedExtraJob() async {
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_id,customer_name,vehicle_label) VALUES (?,?,'owner','Repair','open','J-40','remote-customer','Gloria Johnson','2016 Audi A8L')",
      [server['job_id'], business],
    );
    await db.customStatement(
      "UPDATE local_jobs SET customer_id='original-customer',payment_state='closed' WHERE id=?",
      [job],
    );
  }

  test('Gloria J-40 has one Closed listing, correct counts and customer links; physical records survive restart', () async {
    await seedExtraJob();
    await LocalPayrollRepository(db, business: business, owner: true).prepare();
    await db.customStatement(
      "INSERT INTO regular_payroll_tasks(business_id,id,job_id,labor_id,description,planned) VALUES (?,'task-extra',?,'labor-extra','Saved labor',360)",
      [business, server['job_id']],
    );
    await db.customStatement(
      "INSERT INTO local_job_assignments(assignment_id,business_id,job_id,employee_id,employee_name) VALUES ('payroll-main',?,?,'chris','Chris')",
      [business, server['job_id']],
    );
    await db.customStatement(
      "INSERT INTO local_financial_cache(business_id,cache_key,payload_json) VALUES (?,'transactions_snapshot',?)",
      [
        business,
        jsonEncode([
          {'id': 'income-gloria-1', 'amount': 3000.0, 'document_id': original},
          {'id': 'income-gloria-2', 'amount': 4882.11, 'document_id': original},
        ]),
      ],
    );
    Future<Map<String, List<Map<String, dynamic>>>> retained() async => {
      for (final table in [
        'local_jobs',
        'local_documents',
        'local_document_details',
        'regular_payroll_tasks',
        'local_job_assignments',
        'local_financial_cache',
      ])
        table: [
          for (final row in await db.customSelect('SELECT * FROM $table').get())
            row.data,
        ],
    };
    final before = await retained();
    var jobs = LocalJobRepository(database: db);
    expect((await jobs.listJobs(business)).map((r) => r['id']), [job]);
    expect(await jobs.activeJobCount(business), 0);
    expect(await jobs.jobCount(business, view: JobListView.active), 0);
    expect(await jobs.watchActiveJobCount(business).first, 0);
    expect(await jobs.jobStatusCounts(business), {'closed': 1});
    for (final customer in ['original-customer', 'remote-customer']) {
      expect((await jobs.forCustomer(business, customer)).map((r) => r['id']), [
        job,
      ]);
    }
    final detail = await jobs.jobDetail(business, server['job_id'] as String);
    expect(detail!.job['id'], job);
    expect(detail.job['status'], 'closed');
    expect(await retained(), before);
    expect(
      await jobs.remapProvisionalJob(
        business,
        job,
        server['job_id'] as String,
        jobNumber: 'J-40',
      ),
      'J-40',
    );
    expect(await retained(), before);
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    jobs = LocalJobRepository(database: db);
    expect((await jobs.listJobs(business)).map((r) => r['id']), [job]);
    expect(await retained(), before);
    expect(
      await JobSyncService(database: db)
          .pruneObsoleteCache(business, {server['job_id'] as String}),
      0,
    );
    expect(await retained(), before);
    final deletion = LocalJobGraphDelete.ownerDirected(
      db,
      ownerGrant: await grant(),
    );
    await expectLater(
      deletion.preview(
        businessId: business,
        jobId: server['job_id'] as String,
        actorId: 'owner',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('extra listing'),
        ),
      ),
    );
    expect(await retained(), before);
  });

  test('Gloria job identity survives a full future synchronization without posting Income', () async {
    await seedExtraJob();
    final identity = LocalJobIdentity(db);
    expect(
      await identity.canonicalId(business, server['job_id'] as String),
      job,
    );
    final sync = JobSyncService(
      database: db,
      api: _GloriaJobsApi(),
      cleanupGateway: _EmptyCleanup(),
      retirementGateway: const EmptyRetirementGateway(),
    );
    await sync.pull(business);
    expect(
      (await LocalJobRepository(database: db).listJobs(business))
          .map((r) => r['id']),
      [job],
    );
    expect(
      (await LocalJobRepository(
        database: db,
      ).jobDetail(business, job))!.job['status'],
      'closed',
    );
    expect(
      await LocalDocumentSqlStore.read(
        db,
        LocalDocumentDetailCache.key(business, original),
      ),
      saved,
    );
    expect((await db.customSelect('SELECT * FROM local_jobs').get()).length, 2);
    expect((await db.customSelect('SELECT * FROM sync_outbox').get()), isEmpty);
    await LocalDocumentRepository(database: db)
        .upsertFromServer(business, [server]);
    expect(
      (await LocalJobRepository(database: db).listJobs(business)).length,
      1,
    );
  });

  test(
    'equal Job numbers without invoice creation proof remain visible',
    () async {
      await seedExtraJob();
      await db.customStatement('DELETE FROM local_document_identity_aliases');
      await db.customStatement(
        "UPDATE local_documents SET total=1 WHERE id=?",
        [original],
      );
      expect(
        (await LocalJobRepository(database: db).listJobs(business)).length,
        2,
      );
      expect(
        await LocalJobIdentity(db)
            .canonicalId(business, server['job_id'] as String),
        server['job_id'],
      );
    },
  );

  test(
    'extra linked document prevents collapsing a Job with separate work',
    () async {
      await seedExtraJob();
      await db.customStatement(
        "INSERT INTO local_documents(id,business_id,job_id,kind,status) VALUES ('other',?,?,'estimate','draft')",
        [business, server['job_id']],
      );
      expect(
        (await LocalJobRepository(database: db).listJobs(business)).length,
        2,
      );
    },
  );
  test('verified invoice aliases project duplicate labor without rewriting work or payments', () async {
    await seedExtraJob();
    final payroll = LocalPayrollRepository(db, business: business, owner: true);
    await payroll.prepare();
    for (final (task, document, jobId) in [
      ('original-struts',original,job), ('extra-struts',remote,server['job_id'] as String),
    ]) {
      await db.customStatement("INSERT INTO regular_payroll_tasks VALUES(?,?,?,?,?,?)",
        [business,task,jobId,'labor-$task','Replace front air struts',360]);
      await db.customStatement("INSERT INTO regular_payroll_task_sources VALUES(?,?,?,?,'invoice',1)",
        [business,task,document,'line-$task']);
      await db.customStatement("INSERT INTO regular_payroll_task_order VALUES(?,?,0)",[business,task]);
      await db.customStatement("INSERT INTO regular_payroll_portions(business_id,id,task_id,employee_id,state) VALUES(?,?,?,'chris','Done')",
        [business,'portion-$task',task]);
      await db.customStatement("INSERT INTO regular_payroll_estimates VALUES(?,?,'chris',216)",[business,task]);
    }
    await db.customStatement("INSERT INTO regular_payroll_payments VALUES(?,'paid-struts','chris','2026-11-09','{}',14400,0,14400,'Cash','2026-11-15')",[business]);
    await db.customStatement("INSERT INTO regular_payroll_work_coverage VALUES(?,'portion-original-struts','paid-struts',216,14400,?)",
      [business,jsonEncode({'id':'portion-original-struts','employee_id':'chris','task_id':'original-struts','minutes':216,'rate':4000})]);
    Future<Map<String, dynamic>> evidence() async => {
      for(final table in ['regular_payroll_tasks','regular_payroll_task_sources','regular_payroll_portions','regular_payroll_estimates','regular_payroll_payments','regular_payroll_work_coverage'])
        table:(await db.customSelect('SELECT * FROM $table').get()).map((r)=>r.data).toList(),
      'invoice':await LocalDocumentSqlStore.read(db,LocalDocumentDetailCache.key(business,original)),
    };
    final before = await evidence();
    for (var pass=0;pass<2;pass++) {
      final aliases=await LocalPayrollTaskIdentity(db).aliases(business);
      expect(aliases,{'extra-struts':'original-struts'});
      final tasks=await LocalPayrollRepository(db,business:business,owner:true).tasks();
      expect(tasks.singleWhere((r)=>r['id']=='original-struts')['source_active'],1);
      expect(tasks.singleWhere((r)=>r['id']=='extra-struts')['duplicate_of_task_id'],'original-struts');
      expect(tasks.singleWhere((r)=>r['id']=='extra-struts')['source_active'],0);
      expect(await evidence(),before);
      if(pass==0) {await db.close();db=BriskersLocalDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));}
    }
    await db.customStatement("UPDATE regular_payroll_estimates SET minutes=300 WHERE task_id='extra-struts'");
    expect(await LocalPayrollTaskIdentity(db).aliases(business),isEmpty);
    await db.customStatement("UPDATE regular_payroll_estimates SET minutes=216 WHERE task_id='extra-struts'");
    await db.customStatement("UPDATE regular_payroll_task_order SET line_position=1 WHERE task_id='extra-struts'");
    expect(await LocalPayrollTaskIdentity(db).aliases(business),isEmpty);
    await db.customStatement("UPDATE regular_payroll_task_order SET line_position=0 WHERE task_id='extra-struts'");
    await db.customStatement('DELETE FROM local_document_identity_aliases');
    await db.customStatement("UPDATE local_documents SET total=1 WHERE id=?",[original]);
    expect(await LocalPayrollTaskIdentity(db).aliases(business),isEmpty);
  });

  test('stale Job deletion keeps the selected identity after read redirection', () {
    final source=File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
    final start=source.indexOf('Future<void> _deleteUnusedJob()');
    final end=source.indexOf('Future<void> _showNewMenu()',start);
    expect(source.substring(start,end),contains('jobId:widget.jobId'));
  });

}
