import 'package:briskers_app/local/briskers_local_database.dart' show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/offline_recurring_repository.dart';
import 'package:briskers_app/services/recurring_financial_projection.dart';
import 'package:briskers_app/services/recurring_recovery_service.dart';
import 'package:briskers_app/services/recurring_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const rule = <String,dynamic>{
  'id':'weekly','business_id':'shop','direction':'expense',
  'account_id':'account','category_id':'category','vendor_id':'vendor',
  'amount_minor':10000,'frequency':'weekly','interval_count':1,
  'next_date':'2026-11-04','is_repeating':true,'row_version':1,
};

void main() {
  late BriskersLocalDatabase db;
  late OfflineRecurringRepository repo;
  String? actor;
  setUp(() {
    actor = 'owner';
    db = BriskersLocalDatabase(NativeDatabase.memory());
    repo = OfflineRecurringRepository(database:db,businessId:'shop',userId:'owner',
      currentUserId:()=>actor,canRead:()=>true,canWrite:()=>true,
      projectOccurrence:const RecurringFinancialProjection('shop').call);
  });
  tearDown(()=>db.close());
  Map<String,dynamic> snapshot() => {
    'schema_version':1,'business_id':'shop','complete':true,
    'rule_count':1,'occurrence_count':0,'rules':[rule],'occurrences':[],
    'options':{'accounts':[{'id':'account','business_id':'shop','name':'Server name'}]},
  };
  RecurringRecoveryService recovery(RecurringSnapshotReader read) =>
    RecurringRecoveryService(repository:repo,database:db,readSnapshot:read,
      currentUserId:()=>actor,canRead:()=>true);

  test('explicit recovery keeps pending options and does not generate or upload', () async {
    final cache = LocalFinancialCache(database:db);
    await cache.saveOptions('shop', {'accounts':[
      {'id':'account','name':'Local edited name','sync_state':'pending'},
    ]});
    final counts = await recovery((_) async=>snapshot()).download();
    expect(counts.schedules,1);
    expect(await repo.occurrences(),isEmpty);
    expect(await repo.pending(),isEmpty);
    expect((await cache.loadOptions('shop'))['accounts'][0]['name'],'Local edited name');
  });

  test('partial response and identity change cannot import any data', () async {
    await expectLater(recovery((_) async=>{...snapshot(),'rule_count':2}).download(),throwsStateError);
    expect(await repo.rules(),isEmpty);
    await expectLater(recovery((_) async {actor='other';return snapshot();}).download(),throwsStateError);
    actor='owner';
    expect(await repo.rules(),isEmpty);
  });

  test('Force Offline prevents write calls before any network activity', () async {
    await repo.saveRule(rule);
    var calls=0;
    final sync=RecurringSyncService(database:db,repository:repo,synchronizationAllowed:()=>false,
      writeBundle:(b,id,r,rows) async {calls++;return {};});
    await expectLater(sync.flush(),throwsStateError);
    expect(calls,0);
    expect(await repo.pending(),hasLength(1));
  });

  test('atomic bundle acknowledgement remaps real expense and survives retry', () async {
    await repo.saveRule(rule);
    await repo.generateThrough('2026-11-04');
    var calls=0;
    final sync=RecurringSyncService(database:db,repository:repo,synchronizationAllowed:()=>true,
      writeBundle:(b,id,r,rows) async {
        calls++;
        expect(rows,hasLength(1));
        expect(rows.single.keys.any((k)=>k.startsWith('_')),isFalse);
        return {'business_id':b,'rule':{...r,'row_version':2},
          'occurrences':[for(final row in rows) {...row,'id':'server-id','row_version':1}]};
      });
    expect(await sync.flush(),1);
    expect(await sync.flush(),0);
    expect(calls,1);
    expect(await repo.pending(),isEmpty);
    expect((await LocalFinancialCache(database:db).loadTransactions('shop')).single['id'],'server-id');
  });

  test('local correction during upload is not acknowledged by older response', () async {
    await repo.saveRule(rule);
    await repo.generateThrough('2026-11-04');
    final sync=RecurringSyncService(database:db,repository:repo,synchronizationAllowed:()=>true,
      writeBundle:(b,id,r,rows) async {
        await repo.correctAmount('weekly','2026-11-04',12000);
        return {'business_id':b,'rule':{...r,'row_version':2},
          'occurrences':[for(final row in rows) {...row,'id':'server-id','row_version':1}]};
      });
    expect(await sync.flush(),0);
    final occurrence=(await repo.occurrences()).single;
    expect(occurrence['amount_minor'],12000);
    expect(occurrence['_state'],'pending');
  });

  test('server response missing an occurrence does not acknowledge cursor', () async {
    await repo.saveRule(rule);
    await repo.generateThrough('2026-11-04');
    final sync=RecurringSyncService(database:db,repository:repo,synchronizationAllowed:()=>true,
      writeBundle:(b,id,r,rows) async=>{'business_id':b,'rule':{...r,'row_version':2},'occurrences':[]});
    await expectLater(sync.flush(),throwsStateError);
    expect(await repo.pending(),hasLength(2));
  });
}
