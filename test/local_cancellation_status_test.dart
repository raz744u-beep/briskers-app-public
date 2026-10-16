import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_sync_status_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db=BriskersLocalDatabase(NativeDatabase.memory());
    await db.customStatement('CREATE TABLE local_offline_job_purge_requests(business_id TEXT,actor_id TEXT,registration_state TEXT,cleanup_state TEXT)');
    await db.customStatement("INSERT INTO local_offline_job_purge_requests VALUES ('business','owner','pending','cleanup_pending'),('business','other','pending','cleanup_pending')");
  });
  tearDown(() => db.close());
  test('local cancellation status counts only the authenticated author', () async {
    final snapshot=await LocalSyncStatusRepository(database:db,currentActorId:()=> 'owner').load('business');
    expect(snapshot.pendingUploads,1);
    expect(snapshot.issues,contains('1 local Job cancellation(s) await server registration'));
    expect(snapshot.issues,contains('1 local Job cancellation cleanup(s) require completion or review'));
    final unknown=await LocalSyncStatusRepository(database:db,currentActorId:()=> null).load('business');
    expect(unknown.pendingUploads,0);
    expect(unknown.issues.any((issue)=>issue.contains('local Job cancellation')),isFalse);
  });
  test('actor change during status load returns no previous actor counts', () async {
    var calls=0;
    final snapshot=await LocalSyncStatusRepository(database:db,currentActorId:()=>calls++==0?'owner':'other').load('business');
    expect(snapshot.pendingUploads,0);
    expect(snapshot.issues,['Account changed; refresh synchronization status.']);
  });
}
