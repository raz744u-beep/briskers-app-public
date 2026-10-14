import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/job_summary_visibility.dart';
import 'package:briskers_app/services/job_sync_service.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/test_job_cleanup_gateway.dart';

class _RevocationApi extends BriskersApi {
  bool authorize = false;

  @override
  Future<Map<String, dynamic>> syncPullJobs(
    String businessId, {int? afterCursor, int limit = 250}
  ) async => {
    'mode': 'incremental',
    'next_cursor': 11,
    'has_more': false,
    'revoked_job_ids': authorize ? <String>[] : ['revoked'],
    'bundles': authorize ? [
      {'job': {'id': 'revoked', 'title': 'Current server summary',
        'job_number': 'J-1', 'status': 'open', 'assignments': <dynamic>[],
        'visits': <dynamic>[], 'row_version': 2},
        'findings': <dynamic>[], 'pre_inspection': null},
    ] : <dynamic>[],
  };
}

class _FailingTombstones extends TestJobCleanupGateway {
  bool fail = true;
  void Function()? beforeFailure;

  @override
  Future<Map<String, dynamic>> tombstones(String businessId) async {
    beforeFailure?.call();
    if (fail) throw StateError('Cleanup classification unavailable');
    return {'schema_version': 1, 'business_id': businessId,
      'deleted_job_ids': <String>[], 'deleted_document_ids': <String>[]};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;

  setUp(() async {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    for (final id in ['revoked', 'unrelated']) {
      await db.customStatement(
        'INSERT INTO local_jobs(id,business_id,access_scope,title,status,vehicle_id) '
        "VALUES (?,'shop','full',?,'open','shared-vehicle')", [id, '$id title']);
    }
    await db.customStatement(
      'INSERT INTO local_sync_states(business_id,scope,last_server_cursor,bootstrapped) '
      "VALUES ('shop','jobs',10,1)");
  });
  tearDown(() => db.close());

  test('failed tombstones immediately prune retained cards and reject an old load', () async {
    final jobs = LocalJobRepository(database: db);
    var retained = await jobs.listJobs('shop');
    final staleRows = List<Map<String, dynamic>>.from(retained);
    final visibility = JobSummaryVisibility(
      businessId: 'shop', database: db,
      onQuarantine: (ids) {
        retained = JobSummaryVisibility.withoutJobs(retained, ids);
      },
    );
    addTearDown(visibility.dispose);
    final generation = visibility.beginLoad();
    final slowRead = Completer<List<Map<String, dynamic>>>();
    final pending = slowRead.future.then((rows) {
      if (visibility.isCurrent(generation)) retained = rows;
    });
    final gateway = _FailingTombstones()
      ..beforeFailure = () {
        // This runs before the failed lookup returns to the screen's catch.
        expect(retained.map((row) => row['id']), ['unrelated']);
        expect(visibility.isCurrent(generation), isFalse);
      };
    final sync = JobSyncService(database: db, api: _RevocationApi(),
        cleanupGateway: gateway);
    await expectLater(sync.pull('shop'), throwsStateError);
    slowRead.complete(staleRows);
    await pending;
    expect(retained.map((row) => row['id']), ['unrelated']);
    expect((await db.customSelect("SELECT last_server_cursor FROM local_sync_states "
      "WHERE business_id='shop' AND scope='jobs'").getSingle())
        .read<int>('last_server_cursor'), 10);
    expect((await visibility.filter(staleRows)).map((row) => row['id']), ['unrelated']);
  });

  test('business scoping and disposal preserve unrelated screens', () async {
    var events = 0;
    final visibility = JobSummaryVisibility(
      businessId: 'shop', database: db, onQuarantine: (_) => events++,
    );
    final generation = visibility.beginLoad();
    await LocalJobQuarantine.quarantineJobs(db, 'other', ['revoked']);
    expect(events, 0);
    expect(visibility.isCurrent(generation), isTrue);
    expect(await visibility.filter([{'id': 'revoked'}]), hasLength(1));
    visibility.dispose();
    await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
    expect(events, 0);
    expect(visibility.isCurrent(generation), isFalse);
  });

  test('linked appointments are hidden without dropping unlinked records', () async {
    final visibility = JobSummaryVisibility(
      businessId: 'shop', database: db, onQuarantine: (_) {},
    );
    addTearDown(visibility.dispose);
    await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
    final rows = [
      {'id': 'linked', 'job_id': 'revoked'},
      {'id': 'independent', 'job_id': 'unrelated'},
      <String, dynamic>{'id': 'unlinked'},
    ];
    expect((await visibility.filter(rows, jobIdKey: 'job_id'))
        .map((row) => row['id']), ['independent', 'unlinked']);
  });

  test('reopening after quarantine cannot revive old cached summaries after authorization', () async {
    final oldCache = [{'id': 'revoked', 'title': 'Old saved edit'}];
    final api = _RevocationApi();
    final gateway = _FailingTombstones();
    final sync = JobSyncService(database: db, api: api, cleanupGateway: gateway);
    await expectLater(sync.pull('shop'), throwsStateError);
    final visibility = JobSummaryVisibility(
      businessId: 'shop', database: db, onQuarantine: (_) {},
    );
    addTearDown(visibility.dispose);
    expect(await visibility.filter(oldCache, cached: true), isEmpty);
    final archiveBefore = await db.customSelect('SELECT * FROM local_job_recovery_rows').get();
    api.authorize = true;
    gateway.fail = false;
    await sync.pull('shop');
    // A new authorized server bundle restores current display, never old cache.
    expect(await visibility.filter(oldCache, cached: true), isEmpty);
    final current = (await LocalJobRepository(database: db).listJobs('shop'))
        .where((row) => row['id'] == 'revoked').toList();
    expect(current.single['title'], 'Current server summary');
    expect(await visibility.filter(current), hasLength(1));
    final refreshedCache = JobSummaryVisibility.stampSnapshot(
        current, await visibility.captureSnapshotGeneration());
    expect(await visibility.filter(refreshedCache, cached: true), hasLength(1));
    expect(await db.customSelect('SELECT * FROM local_job_recovery_rows').get(),
        hasLength(archiveBefore.length));
  });

  test('findings use exact archived identities and Job links, never just vehicle identity', () async {
    for (final entry in {'owned': 'revoked', 'other-finding': 'unrelated'}.entries) {
      await db.customStatement(
        'INSERT INTO local_findings(id,business_id,vehicle_id,found_job_id,body,status) '
        "VALUES (?,'shop','shared-vehicle',?,'Saved finding','open')",
        [entry.key, entry.value]);
    }
    final visibility = JobSummaryVisibility(
      businessId: 'shop', database: db, onQuarantine: (_) {},
    );
    addTearDown(visibility.dispose);
    await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
    final cached = <Map<String, dynamic>>[
      {'id': 'owned', 'vehicle_id': 'shared-vehicle'}, // Old API omitted Job IDs.
      {'id': 'other-finding', 'vehicle_id': 'shared-vehicle'},
      {'id': 'uncached-link', 'repair_job_id': 'revoked'},
      {'id': 'independent', 'vehicle_id': 'shared-vehicle'},
    ];
    expect((await visibility.filterFindings(cached, cached: true))
        .map((row) => row['id']), ['other-finding', 'independent']);
    final generation = await visibility.captureSnapshotGeneration();
    await LocalJobQuarantine.authorizeFreshJob(db, 'shop', 'revoked',
        requestGeneration: generation);
    expect((await visibility.filterFindings(cached, cached: true))
        .map((row) => row['id']), ['other-finding', 'independent']);
    final fresh = JobSummaryVisibility.stampSnapshot(cached, generation);
    expect(await visibility.filterFindings(fresh, cached: true), hasLength(4));
  });

  test('all retained summary surfaces bind lifetime and async results to visibility', () async {
    for (final path in [
      'lib/screens/jobs_screen.dart',
      'lib/screens/appointments_screen.dart',
      'lib/screens/customers/customer_detail_screen.dart',
      'lib/screens/customers/customer_service_history_section.dart',
      'lib/screens/customers/customer_vehicle_findings_section.dart',
    ]) {
      final source = await File(path).readAsString();
      expect(source, contains('JobSummaryVisibility('), reason: path);
      expect(source, contains('_jobVisibility.dispose()'), reason: path);
      expect(source, contains('visibility.isCurrent(generation)'), reason: path);
    }
    final customer = await File('lib/screens/customers/customer_detail_screen.dart').readAsString();
    expect(customer, contains("ValueKey(('customer-overview', _jobVisibility.epoch))"));
    expect(customer, contains("ValueKey(('offline-customer-sections', _jobVisibility.epoch))"));
    final findings = await File('lib/screens/customers/customer_vehicle_findings_section.dart').readAsString();
    expect(findings, contains("ValueKey(('vehicle-findings', _jobVisibility.epoch))"));
    expect(findings, contains('_guardModal(quarantine,'));
  });
}
