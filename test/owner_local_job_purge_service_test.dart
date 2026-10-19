import 'dart:convert';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_deletion_v3.dart';
import 'package:briskers_app/services/offline_job_purge.dart';
import 'package:briskers_app/services/owner_local_job_purge_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const business = '10000000-0000-4000-8000-000000000001';
const job = '10000000-0000-4000-8000-000000000002';
const actor = '10000000-0000-4000-8000-000000000003';
const operation = '10000000-0000-4000-8000-000000000004';
class Gateway extends LocalPurgeRegistrationGateway {
  bool allowed = true;
  bool fail = false;
  bool malformed = false;
  final operations = <String>[];
  @override
  void assertActor(String value) { if (!allowed || value != actor) throw StateError('Account changed'); }
  @override
  Future<Map<String,dynamic>> register(String business, String job, String operation, Map<String,dynamic> confirmation) async {
    operations.add(operation);
    if (fail) throw StateError('Lost response');
    return {'schema_version':3,'protocol_version':'owner-deletion-3.0',
      'business_id':business,'job_id':job,'actor_id':actor,'operation_id':operation,
      'graph_hash': malformed ? 'wrong' : confirmation['graph_hash'],
      'deleted_entities':confirmation['deleted_entities'],'status':'deleted',
      'storage_cleanup':'not_required','status_version':1,
      'committed_at':'2026-10-16T00:00:00Z','cleanup_completed_at':'2026-10-16T00:00:00Z'};
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late Gateway gateway;
  late OwnerLocalJobPurgeService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    LocalJobDeletionV3.currentActorIdProvider = null;
    db = BriskersLocalDatabase(NativeDatabase.memory());
    gateway = Gateway(); service = OwnerLocalJobPurgeService(database:db,gateway:gateway);
    await OfflineJobPurge.ensureSchema(db);
    await OfflineJobPurge.recordNewIntent(db,business,[job,'job-create-$job']);
    await db.customStatement("INSERT INTO local_jobs(id,business_id,access_scope,title,status,sync_state) VALUES (?,?,'full','Draft repair','open','pending')",[job,business]);
    await db.customStatement("INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'job_create',?,'create',?)",[business,job,jsonEncode({'job_id':job,'operation_id':'job-create-$job'})]);
  });
  tearDown(() async { await db.close(); LocalJobDeletionV3.currentActorIdProvider = null; });
  Future<void> prepare() async {
    final preview = await service.eligiblePreview(business,job,actorId:actor,isOwner:true);
    expect(preview,isNotNull);
    await OfflineJobPurge.confirm(db,preview!,operationId:operation,actorId:actor,isOwner:true);
  }
  test('verified matching registration acknowledges only minimal queued cancellation',() async {
    await prepare();
    await service.flushRegistrations(business,actorId:actor,isOwner:true);
    expect(gateway.operations,[operation]);
    expect(await OfflineJobPurge.pendingRegistrations(db,business,actor),isEmpty);
    expect(await LocalJobDeletionV3.blockedJobIds(db,business),contains(job));
  });
  test('lost response and invalid receipt retain same operation for retry',() async {
    await prepare(); gateway.fail = true;
    await service.flushRegistrations(business,actorId:actor,isOwner:true);
    gateway.fail = false; gateway.malformed = true;
    await service.flushRegistrations(business,actorId:actor,isOwner:true);
    expect((await OfflineJobPurge.pendingRegistrations(db,business,actor)).single['operation_id'],operation);
    gateway.malformed = false;
    await service.flushRegistrations(business,actorId:actor,isOwner:true);
    expect(gateway.operations,[operation,operation,operation]);
    expect(await OfflineJobPurge.pendingRegistrations(db,business,actor),isEmpty);
  });
  test('nonowner or changed actor never sends registration',() async {
    await prepare();
    await service.flushRegistrations(business,actorId:actor,isOwner:false);
    expect(gateway.operations,isEmpty);
    gateway.allowed = false;
    await expectLater(service.flushRegistrations(business,actorId:actor,isOwner:true),throwsStateError);
    expect(gateway.operations,isEmpty);
    expect(await OfflineJobPurge.pendingRegistrations(db,business,actor),hasLength(1));
  });
  test('successful shared flush completes and allows later invocation',() async {
    await prepare();
    await Future.wait([service.flushRegistrations(business,actorId:actor,isOwner:true),service.flushRegistrations(business,actorId:actor,isOwner:true)]);
    await service.flushRegistrations(business,actorId:actor,isOwner:true);
    expect(gateway.operations,[operation]);
  });
}
