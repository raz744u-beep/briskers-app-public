import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/customer_document_summary_service.dart';
import 'package:briskers_app/services/job_summary_visibility.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/local_job_access_history.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_job_retirement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late LocalJobRepository jobs;
  late LocalDocumentRepository documents;
  late LocalDocumentDetailCache cache;

  Future<void> seed() async {
    for (final id in ['retiring-job', 'unrelated-job']) {
      await db.customStatement(
        'INSERT INTO local_jobs(id,business_id,access_scope,job_number,title,'
        'status,customer_id,customer_name,vehicle_id,is_unassigned,created_at) '
        "VALUES (?,'synthetic-shop','all',?,'Synthetic repair','open',"
        "'customer','Synthetic customer','shared-vehicle',1,?)",
        [
          id,
          id == 'retiring-job' ? 'J-9002' : 'J-9001',
          id == 'retiring-job' ? 200 : 100,
        ],
      );
    }
    await db.customStatement(
      'INSERT INTO local_findings(id,business_id,vehicle_id,found_job_id,body,status) '
      "VALUES ('shared-finding','synthetic-shop','shared-vehicle','retiring-job',"
      "'Keep this finding','open')",
    );
    for (final row in [
      ['retiring-invoice', 'retiring-job', 'invoice'],
      ['preserved-estimate', 'retiring-job', 'estimate'],
      ['unrelated-invoice', 'unrelated-job', 'invoice'],
    ]) {
      await db.customStatement(
        'INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,'
        'document_number,status,display_status_code,total,created_at) '
        "VALUES (?,'synthetic-shop',?,'customer',?,?,'draft','pending_close',42,100)",
        [row[0], row[1], row[2], row[0]],
      );
      await cache.save('synthetic-shop', row[0], {
        'id': row[0],
        'job_id': row[1],
        'kind': row[2],
        'row_version': 1,
        'memo': 'Original saved content',
      });
    }
  }

  Future<void> block({
    String state = 'pending',
    String business = 'synthetic-shop',
  }) async {
    await LocalJobRetirement.ensureSchema(db);
    await db.transaction(() async {
      for (final row in [
        ['job', 'retiring-job'],
        ['invoice', 'retiring-invoice'],
      ]) {
        await LocalJobRetirement.recordEntity(
          db,
          businessId: business,
          jobId: 'retiring-job',
          entityKind: row[0],
          entityId: row[1],
          operationId: 'synthetic-operation',
          state: state,
        );
      }
    });
    LocalJobRetirement.notify(db, business, {'retiring-job'});
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    jobs = LocalJobRepository(database: db);
    documents = LocalDocumentRepository(database: db);
    cache = LocalDocumentDetailCache(database: db);
    await seed();
  });
  tearDown(() => db.close());

  for (final state in ['pending', 'accepted', 'locally_cancelled']) {
    test(
      '$state retirement hides Jobs before paging and in all counts',
      () async {
        await block(state: state);
        expect(
          (await jobs.listJobs('synthetic-shop', limit: 1)).single['id'],
          'unrelated-job',
        );
        expect(await jobs.jobCount('synthetic-shop'), 1);
        expect(await jobs.watchJobCount('synthetic-shop').first, 1);
        expect(await jobs.activeJobCount('synthetic-shop'), 1);
        expect(await jobs.watchActiveJobCount('synthetic-shop').first, 1);
        expect(await jobs.unassignedOpenJobCount('synthetic-shop'), 1);
        expect(
          (await jobs.unassignedOpenJobs('synthetic-shop')).single['id'],
          'unrelated-job',
        );
        expect(await jobs.jobStatusCounts('synthetic-shop'), {'open': 1});
        expect(await jobs.jobDetail('synthetic-shop', 'retiring-job'), isNull);
        expect(
          await jobs.jobNumberForJob('synthetic-shop', 'retiring-job'),
          isNull,
        );
        expect(await jobs.listJobs('synthetic-shop', search: '9002'), isEmpty);
        expect(
          await db.customSelect('SELECT * FROM local_jobs').get(),
          hasLength(2),
        );
        final detail = await jobs.jobDetail('synthetic-shop', 'unrelated-job');
        expect(detail!.findings.single['id'], 'shared-finding');
      },
    );

    test(
      '$state retirement hides invoices but preserves estimates and raw rows',
      () async {
        await block(state: state);
        expect(
          (await documents.listByKind(
            'synthetic-shop',
            kind: 'invoice',
          )).single['id'],
          'unrelated-invoice',
        );
        expect(
          (await documents.listByKind(
            'synthetic-shop',
            kind: 'estimate',
          )).single['id'],
          'preserved-estimate',
        );
        expect(
          (await documents.listByJob(
            'synthetic-shop',
            'retiring-job',
          )).single['id'],
          'preserved-estimate',
        );
        expect(
          await documents.search('synthetic-shop', 'retiring-invoice'),
          isEmpty,
        );
        expect(
          await documents.createdAtForDocument(
            'synthetic-shop',
            'retiring-invoice',
          ),
          isNull,
        );
        // Both surviving invoices are flagged pending_close (already fully covered).
        // The new dock Open count means a remaining customer balance only.
        expect(await documents.openInvoiceCount('synthetic-shop'), 0);
        expect(
          await documents.watchOpenInvoiceCount('synthetic-shop').first,
          0,
        );
        expect(
          (await documents.pendingCloseAttention('synthetic-shop'))['count'],
          1,
        );
        expect(await documents.openEstimateCount('synthetic-shop'), 1);
        final summaries = await CustomerDocumentSummaryService(database: db)
            .forCustomer('synthetic-shop', 'customer', includeClosed: true);
        expect(summaries.map((row) => row['id']).toSet(), {
          'preserved-estimate',
          'unrelated-invoice',
        });
        expect(await cache.load('synthetic-shop', 'retiring-invoice'), isNull);
        expect(
          await db.customSelect('SELECT * FROM local_documents').get(),
          hasLength(3),
        );
      },
    );
  }

  test(
    'late replacement/upsert/cache response cannot overwrite retained invoice',
    () async {
      await block();
      final stale = <String, dynamic>{
        'id': 'retiring-invoice',
        'kind': 'invoice',
        'job_id': 'unrelated-job',
        'document_number': 'STALE',
        'total': 999,
        'memo': 'Late server response',
      };
      await documents.replaceFromServer('synthetic-shop', [
        stale,
      ], kind: 'invoice');
      await documents.upsertFromServer('synthetic-shop', [stale]);
      await cache.save('synthetic-shop', 'retiring-invoice', stale);
      await cache.remove('synthetic-shop', 'retiring-invoice');
      expect(
        await cache.removeIfUnchanged(
          'synthetic-shop',
          'retiring-invoice',
          null,
        ),
        false,
      );
      final row = await db
          .customSelect(
            "SELECT * FROM local_documents WHERE id='retiring-invoice'",
          )
          .getSingle();
      expect(row.read<String>('document_number'), 'retiring-invoice');
      expect(row.read<double>('total'), 42);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonDecode(
        prefs.getString(
          'briskers_document_detail_synthetic-shop_retiring-invoice',
        )!,
      ) as Map;
      expect(raw['memo'], 'Original saved content');
      await block(state: 'rejected');
      expect(
        (await cache.load('synthetic-shop', 'retiring-invoice'))!['memo'],
        'Original saved content',
      );
      expect(
        (await documents.listByKind(
          'synthetic-shop',
          kind: 'invoice',
        )).single['document_number'],
        'retiring-invoice',
      );
    },
  );

  test(
    'rejected request reveals retained data and other businesses stay isolated',
    () async {
      await block(business: 'other-shop');
      expect(await jobs.jobCount('synthetic-shop'), 2);
      expect(await cache.load('synthetic-shop', 'retiring-invoice'), isNotNull);
      await block();
      await block(state: 'rejected');
      expect(await jobs.jobCount('synthetic-shop'), 2);
      expect(await documents.openInvoiceCount('synthetic-shop'), 0);
      expect(await cache.load('synthetic-shop', 'retiring-invoice'), isNotNull);
    },
  );

  test(
    'in-flight Job summaries invalidate while shared findings remain visible',
    () async {
      var invalidations = 0;
      final visibility = JobSummaryVisibility(
        businessId: 'synthetic-shop',
        database: db,
        onQuarantine: (_) => invalidations++,
      );
      addTearDown(visibility.dispose);
      final generation = visibility.beginLoad();
      await block();
      expect(visibility.isCurrent(generation), false);
      expect(invalidations, 1);
      expect(
        await visibility.filter([
          {'id': 'retiring-job'},
        ]),
        isEmpty,
      );
      expect(
        await visibility.filterFindings([
          {'id': 'shared-finding', 'found_job_id': 'retiring-job'},
        ]),
        hasLength(1),
      );
    },
  );

  test('retirement notifies existing reactive count subscribers', () async {
    final values = <int>[];
    final first = Completer<void>();
    final hidden = Completer<void>();
    final subscription = jobs.watchJobCount('synthetic-shop').listen((count) {
      values.add(count);
      if (count == 2 && !first.isCompleted) first.complete();
      if (count == 1 && !hidden.isCompleted) hidden.complete();
    });
    addTearDown(subscription.cancel);
    await first.future.timeout(const Duration(seconds: 5));
    await block();
    await hidden.future.timeout(const Duration(seconds: 5));
    expect(values, [2, 1]);
  });

  test('retired canonical identities cannot consume provisional Job or access history', () async {
    await db.customStatement(
      'INSERT INTO local_jobs(id,business_id,access_scope,title,status) '
      "VALUES ('local-job','synthetic-shop','all','Unsent repair','open')",
    );
    final history = LocalJobAccessHistory(database: db);
    await history.recordAccess('synthetic-shop', 'local-job', userId: 'owner');
    await block();
    await expectLater(
      jobs.remapProvisionalJob('synthetic-shop', 'local-job', 'retiring-job'),
      throwsStateError,
    );
    await history.remapJob('synthetic-shop', 'local-job', 'retiring-job');
    await history.recordAccess(
      'synthetic-shop',
      'retiring-job',
      userId: 'owner',
    );
    final rows = await db
        .customSelect('SELECT job_id FROM local_job_accesses')
        .get();
    expect(rows.single.read<String>('job_id'), 'local-job');
    expect(await jobs.jobDetail('synthetic-shop', 'local-job'), isNotNull);
  });

  test(
    'exact retired conversion is projected without rewriting saved estimate',
    () async {
      await db.customStatement(
        "UPDATE local_documents SET converted=1,status='accepted' "
        "WHERE id='preserved-estimate'",
      );
      final original = <String, dynamic>{
        'id': 'preserved-estimate',
        'kind': 'estimate',
        'job_id': 'retiring-job',
        'converted': true,
        'converted_invoice_id': 'retiring-invoice',
        'status': 'accepted',
      };
      await cache.save('synthetic-shop', 'preserved-estimate', original);
      await block(state: 'accepted');
      final projected = await cache.load(
        'synthetic-shop',
        'preserved-estimate',
      );
      expect(projected!['converted'], false);
      expect(projected['converted_invoice_id'], isNull);
      expect(projected['status'], 'accepted');
      expect(
        (await documents.listByKind(
          'synthetic-shop',
          kind: 'estimate',
        )).single['converted'],
        false,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(
            'briskers_document_detail_synthetic-shop_preserved-estimate',
          )!,
        ),
        original,
      );
    },
  );

  test(
    'open-estimate counts use visible conversion while keeping saved columns',
    () async {
      await db.customStatement(
        "UPDATE local_documents SET converted=1 "
        "WHERE id='preserved-estimate'",
      );
      await cache.save('synthetic-shop', 'preserved-estimate', {
        'id': 'preserved-estimate',
        'kind': 'estimate',
        'converted': true,
        'converted_invoice_id': 'retiring-invoice',
        'status': 'draft',
      });
      expect(await documents.openEstimateCount('synthetic-shop'), 0);
      await block(state: 'accepted');
      expect(await documents.openEstimateCount('synthetic-shop'), 1);
      expect(await documents.watchOpenEstimateCount('synthetic-shop').first, 1);
      final stored = await db
          .customSelect(
            "SELECT converted FROM local_documents "
            "WHERE id='preserved-estimate'",
          )
          .getSingle();
      expect(stored.read<int>('converted'), 1);
    },
  );

  test(
    'newer estimate conversion is not overwritten by retired stale cache',
    () async {
      await cache.save('synthetic-shop', 'preserved-estimate', {
        'id': 'preserved-estimate',
        'kind': 'estimate',
        'row_version': 1,
        'converted': true,
        'converted_invoice_id': 'retiring-invoice',
      });
      await block(state: 'accepted');
      final summary = await CustomerDocumentSummaryService(database: db)
          .hydrate('synthetic-shop', {
            'id': 'preserved-estimate',
            'kind': 'estimate',
            'row_version': 2,
            'converted': true,
            'converted_invoice_id': 'unrelated-invoice',
          });
      expect(summary['converted'], true);
      expect(summary['converted_invoice_id'], 'unrelated-invoice');
    },
  );

  test(
    'cache alias to retired canonical invoice is hidden and cannot be saved',
    () async {
      await cache.save('synthetic-shop', 'local-alias', {
        'id': 'local-alias',
        'kind': 'invoice',
        '_server_document_id': 'retiring-invoice',
      });
      await block(state: 'accepted');
      expect(await cache.load('synthetic-shop', 'local-alias'), isNull);
      await cache.save('synthetic-shop', 'local-alias', {
        'id': 'local-alias',
        'memo': 'Stale response omitted its canonical ID',
      });
      await cache.remove('synthetic-shop', 'local-alias');
      expect(await cache.load('synthetic-shop', 'local-alias'), isNull);
      final prefs = await SharedPreferences.getInstance();
      final retained = jsonDecode(
        prefs.getString('briskers_document_detail_synthetic-shop_local-alias')!,
      ) as Map;
      expect(retained['_server_document_id'], 'retiring-invoice');
      await cache.save('synthetic-shop', 'new-alias', {
        'id': 'new-alias',
        'kind': 'invoice',
        '_server_document_id': 'retiring-invoice',
      });
      expect(await cache.load('synthetic-shop', 'new-alias'), isNull);
    },
  );

  test('nested cache transaction and concurrent writer complete without lock inversion', () async {
    await Future.wait([
      db.transaction(() => cache.load('synthetic-shop', 'retiring-invoice')),
      cache.save('synthetic-shop', 'retiring-invoice', {
        'id': 'retiring-invoice',
        'memo': 'New',
      }),
    ]).timeout(const Duration(seconds: 5));
    expect(
      (await cache.load('synthetic-shop', 'retiring-invoice'))!['memo'],
      'New',
    );
  });

  test('accepted tombstone survives a fresh database connection', () async {
    final directory = await Directory.systemTemp.createTemp('retirement-read-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/synthetic.sqlite');
    final first = BriskersLocalDatabase(NativeDatabase(file));
    await first.customStatement(
      'INSERT INTO local_jobs(id,business_id,access_scope,title,status) '
      "VALUES ('persistent-job','synthetic-shop','all','Retained','open')",
    );
    await LocalJobRetirement.ensureSchema(first);
    await LocalJobRetirement.recordEntity(
      first,
      businessId: 'synthetic-shop',
      jobId: 'persistent-job',
      entityKind: 'job',
      entityId: 'persistent-job',
      operationId: 'persistent-operation',
      state: 'accepted',
    );
    await first.close();
    final reopened = BriskersLocalDatabase(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(
      await LocalJobRepository(database: reopened).jobCount('synthetic-shop'),
      0,
    );
    expect(
      await reopened.customSelect('SELECT * FROM local_jobs').get(),
      hasLength(1),
    );
  });
}
