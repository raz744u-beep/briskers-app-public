import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_sync_status_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BriskersLocalDatabase db;
  late LocalSyncStatusRepository repository;
  final base = DateTime.utc(2026, 10, 14, 10);
  final seconds = base.millisecondsSinceEpoch ~/ 1000;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    repository = LocalSyncStatusRepository(database: db);
  });
  tearDown(() => db.close());

  Future<void> scope(String name, int at, {
    String business = 'shop', String? error, bool complete = true,
  }) => db.customStatement(
    'INSERT OR REPLACE INTO local_sync_states '
    '(business_id,scope,last_pull_at,last_error,bootstrapped) VALUES (?,?,?,?,?)',
    [business, name, at, error, complete ? 1 : 0],
  );

  test('latest successful scope matches Settings downloads, never another shop', () async {
    await scope('customers_vehicles', seconds + 60);
    await scope('jobs', seconds + 120);
    await scope('documents', seconds + 180);
    await scope('documents', seconds + 600, business: 'other-shop');
    await db.customStatement(
      "INSERT INTO local_sync_states (business_id,scope,last_server_cursor,bootstrapped) "
      "VALUES ('shop','customer_notification_baseline',123,1)",
    );
    final status = await repository.load('shop');
    expect(status.lastSuccessfulPull, base.add(const Duration(minutes: 3)));
    expect(status.issues, isEmpty);
    expect(status.pendingUploads, 0);
  });

  test('a newer failed attempt or partial bootstrap cannot masquerade as success', () async {
    await scope('customers_vehicles', seconds + 60);
    await scope('jobs', seconds + 120, error: 'Synthetic network failure');
    await scope('documents', seconds + 180, complete: false);
    final status = await repository.load('shop');
    expect(status.lastSuccessfulPull, base.add(const Duration(minutes: 1)));
    expect(status.issues, contains('jobs: last attempt failed'));
    expect(status.issues, contains('documents: download incomplete'));
    // Recovery is read from persisted truth, rather than stale widget state.
    await scope('jobs', seconds + 240);
    await scope('documents', seconds + 300);
    final recovered = await repository.load('shop');
    expect(recovered.lastSuccessfulPull, base.add(const Duration(minutes: 5)));
    expect(recovered.issues, isEmpty);
  });

  test('pending uploads and conflicts remain visible alongside a successful pull', () async {
    await scope('jobs', seconds);
    await db.customStatement(
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json,state,last_error) VALUES "
      "('shop','job_admin','a','update','{}','pending',NULL),"
      "('shop','job_admin','b','update','{}','conflict','Synthetic conflict'),"
      "('shop','job_admin','c','update','{}','pending','Synthetic retry failure'),"
      "('shop','document_draft_create','f','create','{}','inflight','Synthetic interrupted draft'),"
      "('shop','document_draft_create','g','create','{}','inflight',NULL),"
      "('shop','job_admin','d','update','{}','done',NULL),"
      "('other-shop','job_admin','e','update','{}','failed','Other shop')",
    );
    final before = await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get();
    final status = await repository.load('shop');
    expect(status.pendingUploads, 5);
    expect(status.issues, ['3 upload(s) need attention']);
    expect(status.lastSuccessfulPull, base);
    final after = await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get();
    expect(after.map((row) => row.data).toList(), before.map((row) => row.data).toList());
  });

  test('Settings failures without a scope row persist until a successful full retry', () async {
    SharedPreferences.setMockInitialValues({
      'sync-header:manual-refresh-failures:manual-shop': <String>['Tax settings'],
    });
    expect((await repository.load('manual-shop')).issues.single, contains('Tax settings'));
    final next = LocalSyncStatusRepository.refreshEvents.first;
    await LocalSyncStatusRepository.recordManualRefreshResult('manual-shop', ['Invoice status styles']);
    expect(await next, 'manual-shop');
    final status = await repository.load('manual-shop');
    expect(status.lastSuccessfulPull, isNull);
    expect(status.issues.single, contains('Invoice status styles'));
    expect((await repository.load('other-shop')).issues, isEmpty);
    await LocalSyncStatusRepository.recordManualRefreshResult('manual-shop', []);
    expect((await repository.load('manual-shop')).issues, isEmpty);
    expect((await SharedPreferences.getInstance()).getStringList(
      'sync-header:manual-refresh-failures:manual-shop'), isEmpty);
  });

  test('a bootstrapped scope without a download timestamp is unverified', () async {
    await scope('jobs', seconds);
    await db.customStatement(
      "INSERT INTO local_sync_states (business_id,scope,bootstrapped) "
      "VALUES ('shop','documents',1)",
    );
    final status = await repository.load('shop');
    expect(status.lastSuccessfulPull, base);
    expect(status.issues, ['documents: no successful download recorded']);
  });

  test('empty database never claims a completed refresh', () async {
    final status = await repository.load('shop');
    expect(status.lastSuccessfulPull, isNull);
    expect(status.issues, isEmpty);
    expect(status.pendingUploads, 0);
  });
}
