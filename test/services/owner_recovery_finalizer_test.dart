import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_document_detail_cache.dart';
import 'package:briskers_app/services/local_job_work_date.dart';
import 'package:briskers_app/services/local_document_repository.dart';
import 'package:briskers_app/services/offline_invoice_payment_ledger.dart';
import 'package:briskers_app/services/owner_recovery_finalizer.dart';
import 'package:briskers_app/services/recovery_commit_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late Directory temp;
  late File file;
  final mode = BriskersConnectionModeController.instance;
  const b = 'synthetic-business',
      li = 'local-invoice-test',
      lj = 'local-job-test';
  const lc = 'local-customer-test', lv = 'local-vehicle-test';
  final line = {
    'id': 'local-line-test',
    'name': 'Synthetic service',
    'description': 'Work',
    'line_kind': 'labor',
    'quantity': 1,
    'unit_price': 100,
    'tax_rate': 0,
    'position': 1,
  };
  Map<String, dynamic> snapshot() => {
    'id': li,
    'kind': 'invoice',
    'job_id': lj,
    'customer_id': lc,
    'vehicle_id': lv,
    'status': 'issued',
    'document_number': 'T-100',
    'job_number': 'J-T100',
    'document_date': '2026-01-02',
    'memo': 'Synthetic note',
    'net_amount': 100,
    'tax_amount': 0,
    'total_amount': 100,
    'lines': [line],
    '_local_snapshot': true,
    '_local_draft': true,
  };
  Map<String, dynamic> proof() => {
    ...snapshot(),
    'id': 'server-invoice',
    'customer_id': 'server-customer',
    'vehicle_id': 'server-vehicle',
    'job_id': 'server-job',
    '_local_snapshot': false,
    '_local_draft': false,
    'business_id': b,
    'offline_operation_id': 'invoice-op',
    'customer_operation_id': 'customer-op',
    'local_vehicle_id': lv,
    'line_count': 1,
    'initial_visit': {
      'id': 'server-visit',
      'job_id': 'server-job',
      'visit_number': 1,
      'work_summary': null,
      'closed_at': null,
    },
    'lines': [
      {...line, 'id': 'server-line'},
    ],
    'payments': [
      {
        'id': 'server-payment',
        'invoice_id': 'server-invoice',
        'operation_id': 'payment-op',
        'amount': 30,
        'method_id': 'card',
        'payment_method_id': 'card',
        'payment_date': '2026-01-01',
        'state': 'pending',
      },
    ],
    'paid_amount': 0,
    'pending_payment': 30,
  };
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mode.setMode(BriskersConnectionMode.offline);
    temp = await Directory.systemTemp.createTemp('recovery-test-');
    file = File('${temp.path}/local.sqlite');
    db = BriskersLocalDatabase(NativeDatabase(file));
    await db.customStatement(
      "INSERT INTO local_customers(id,business_id,display_name,sync_state) VALUES(?,?,'Synthetic','pending')",
      [lc, b],
    );
    await db.customStatement(
      "INSERT INTO local_vehicles(id,business_id,make,sync_state) VALUES(?,?,'Synthetic','pending')",
      [lv, b],
    );
    await db.customStatement(
      'INSERT INTO local_customer_vehicles(business_id,customer_id,vehicle_id) VALUES(?,?,?)',
      [b, lc, lv],
    );
    await db.customStatement(
      "INSERT INTO local_jobs(id,business_id,access_scope,title,status,job_number,customer_id,vehicle_id,sync_state) VALUES(?,?,'full','Synthetic','open','J-T100',?,?,'pending')",
      [lj, b, lc, lv],
    );
    await db.customStatement(
      "INSERT INTO local_documents(id,business_id,job_id,customer_id,kind,status,document_number,total,sync_state) VALUES(?,?,?,?,'invoice','issued','T-100',100,'pending')",
      [li, b, lj, lc],
    );
    await db.customStatement(
      "INSERT INTO local_job_visits(id,business_id,job_id,visit_number,reason,sync_state) VALUES('local-visit-test',?,?,1,'Initial visit','pending')",
      [b, lj],
    );
    final ops = {
      'customer_create': {'operation_id': 'customer-op'},
      'vehicle_create': {'idempotent_v1': true, 'customer_id': lc},
      'document_draft_create': {
        'operation_id': 'invoice-op',
        'customer_id': lc,
        'vehicle_id': lv,
        'kind': 'invoice',
      },
      'invoice_payment_received': {
        'operation_id': 'payment-op',
        'invoice_id': li,
        'amount_cents': 3000,
        'method_id': 'card',
        'payment_date': '2026-01-01',
        'local_edit_history': [
          {'amount_cents': 3000, 'reason': 'Original record'},
        ],
      },
    };
    final holds = {
      'customer_create': 'Owner local recovery is authoritative; sync disabled',
      'vehicle_create': 'Owner local recovery is authoritative; sync disabled',
      'document_draft_create':
          'Owner assigned authoritative local number; sync disabled',
      'invoice_payment_received':
          'Owner recovery payment preserved; sync disabled',
    };
    for (final e in ops.entries) {
      await db.customStatement(
        "INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json,state,created_at,last_error) VALUES(?,?,?,'create',?,'conflict',123,?)",
        [
          b,
          e.key,
          e.key == 'customer_create'
              ? lc
              : e.key == 'vehicle_create'
              ? lv
              : li,
          jsonEncode(e.value),
          holds[e.key],
        ],
      );
    }
    await LocalDocumentDetailCache(database: db).save(b, li, snapshot());
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<String> run({
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? lookup,
    bool owner = true,
  }) => OwnerRecoveryFinalizer(
    database: db,
    lookup: lookup ?? (_) async => proof(),
  ).reconcile(isOwner: owner, businessId: b, localInvoiceId: li);
  Future<void> unchanged() async {
    expect(
      (await db
              .customSelect(
                "SELECT id FROM local_documents WHERE id='local-invoice-test'",
              )
              .get())
          .length,
      1,
    );
    expect(
      (await db
              .customSelect("SELECT * FROM sync_outbox WHERE state='conflict'")
              .get())
          .length,
      4,
    );
    expect(
      (await db.customSelect('SELECT * FROM recovery_commits').get()),
      isEmpty,
    );
    expect(
      await LocalDocumentDetailCache(database: db).load(b, li),
      snapshot(),
    );
  }

  test(
    'commits identities and snapshot, preserves all original operation bytes and audit',
    () async {
      await LocalJobWorkDate(db).save(b, lj, DateTime(2026, 1, 2));
      final before =
          (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
              .map((r) => r.data)
              .toList();
      expect(await run(), 'server-invoice');
      expect(await LocalJobWorkDate(db).read(b, 'server-job'), DateTime(2026, 1, 2));
      expect(await LocalJobWorkDate(db).read(b, lj), isNull);
      final after =
          (await db.customSelect('SELECT * FROM sync_outbox ORDER BY id').get())
              .map((r) => r.data)
              .toList();
      expect(after, [
        for (final r in before) {...r, 'state': 'reconciled'},
      ]);
      final journal = await db
          .customSelect('SELECT * FROM recovery_commits')
          .getSingle();
      expect(
        jsonDecode(journal.read<String>('original_json'))['snapshot'],
        snapshot(),
      );
      final cache = LocalDocumentDetailCache(database: db);
      expect(await cache.load(b, li), isNull);
      final active = await cache.load(b, 'server-invoice');
      expect(active!['total_amount'], 100);
      expect((active['payments'] as List).single['amount'], 30);
      expect((await cache.loadAll(b)).length, 1);
      expect(mode.forceOffline, isTrue);
      expect(
        (await db
                .customSelect('SELECT id,sync_state FROM local_documents')
                .getSingle())
            .data,
        {'id': 'server-invoice', 'sync_state': 'synced'},
      );
      var uploads = 0;
      await mode.setMode(BriskersConnectionMode.auto);
      await OfflineInvoicePaymentLedger(database: db).flush(
        b,
        submitPayment: (_, a, c, d, e) async {
          uploads++;
          return 'unreachable';
        },
      );
      expect(uploads, 0);
    },
  );
  test(
    'restart and repeated reconciliation use durable commit without lookup',
    () async {
      await run();
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      expect(
        await run(lookup: (_) async => throw StateError('must not call')),
        'server-invoice',
      );
      expect(
        (await LocalDocumentDetailCache(database: db).loadAll(b)).length,
        1,
      );
      expect(
        (await db.customSelect('SELECT * FROM recovery_commits').get()).length,
        1,
      );
    },
  );
  test('simultaneous attempts commit once', () async {
    expect(await Future.wait([run(), run()]), [
      'server-invoice',
      'server-invoice',
    ]);
    expect(
      (await db.customSelect('SELECT * FROM recovery_commits').get()).length,
      1,
    );
  });
  test(
    'late SQL failure rolls back every identity, state and durable snapshot',
    () async {
      await RecoveryCommitStore.ensure(db);
      await db.customStatement(
        "CREATE TRIGGER reject_commit BEFORE INSERT ON recovery_commits BEGIN SELECT RAISE(ABORT,'simulated power-loss boundary'); END",
      );
      await expectLater(run(), throwsA(anything));
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      await unchanged();
      expect(
        await db.customSelect('SELECT * FROM recovery_document_cache').get(),
        isEmpty,
      );
      await db.customStatement('DROP TRIGGER reject_commit');
      expect(await run(), 'server-invoice');
    },
  );
  test('lookup failure leaves original data available', () async {
    await expectLater(
      run(lookup: (_) async => throw StateError('network unavailable')),
      throwsStateError,
    );
    await unchanged();
  });
  test(
    'offline-auto-offline during proof rejects even after mode returns',
    () async {
      await expectLater(
        run(
          lookup: (_) async {
            await mode.setMode(BriskersConnectionMode.auto);
            await mode.setMode(BriskersConnectionMode.offline);
            return proof();
          },
        ),
        throwsStateError,
      );
      await unchanged();
    },
  );
  test(
    'changed local snapshot during network lookup is not overwritten',
    () async {
      await expectLater(
        run(
          lookup: (_) async {
            await LocalDocumentDetailCache(
              database: db,
            ).save(b, li, {...snapshot(), 'memo': 'New note'});
            return proof();
          },
        ),
        throwsStateError,
      );
      expect(
        (await LocalDocumentDetailCache(database: db).load(b, li))!['memo'],
        'New note',
      );
      expect(
        await db.customSelect('SELECT * FROM recovery_commits').get(),
        isEmpty,
      );
    },
  );
  for (final field in [
    'business_id',
    'offline_operation_id',
    'customer_operation_id',
    'local_vehicle_id',
    'document_number',
    'job_number',
  ]) {
    test('rejects mismatched $field', () async {
      await expectLater(
        run(lookup: (_) async => {...proof(), field: 'wrong'}),
        throwsStateError,
      );
      await unchanged();
    });
  }
  test('rejects different line despite same total and count', () async {
    await expectLater(
      run(
        lookup: (_) async => {
          ...proof(),
          'lines': [
            {...line, 'name': 'different'},
          ],
        },
      ),
      throwsStateError,
    );
    await unchanged();
  });
  test('rejects duplicate payment', () async {
    final p = proof();
    p['payments'] = [...(p['payments'] as List), ...(p['payments'] as List)];
    await expectLater(run(lookup: (_) async => p), throwsStateError);
    await unchanged();
  });
  test('Owner and Force Offline required before lookup', () async {
    await expectLater(run(owner: false), throwsStateError);
    await mode.setMode(BriskersConnectionMode.auto);
    await expectLater(run(), throwsStateError);
  });
  test(
    'database uniqueness collision rolls back instead of merging or deleting',
    () async {
      await db.customStatement(
        "INSERT INTO local_customers(id,business_id,display_name) VALUES('server-customer',?,'Existing cached customer')",
        [b],
      );
      await expectLater(run(), throwsA(anything));
      await unchanged();
    },
  );
  test('unrelated local records remain unchanged', () async {
    await db.customStatement(
      "INSERT INTO local_customers(id,business_id,display_name) VALUES('unrelated','other-business','Other')",
    );
    await run();
    expect(
      (await db
              .customSelect(
                "SELECT display_name FROM local_customers WHERE id='unrelated'",
              )
              .getSingle())
          .data['display_name'],
      'Other',
    );
  });
  test('legacy alias does not hide adopted canonical invoice', () async {
    await LocalDocumentRepository(database: db).replaceFromServer('empty', []);
    await db.customStatement(
      "INSERT INTO owner_recovery_aliases(business_id,local_invoice_id,server_invoice_id,server_job_id,payment_operation_id,invoice_number,job_number,total_cents,payment_cents) VALUES(?,?,'server-invoice','server-job','payment-op','T-100','J-T100',10000,3000)",
      [b, li],
    );
    await run();
    // Only one active document exists, and the original alias is retained.
    expect(
      (await db.customSelect('SELECT * FROM local_documents').get()).length,
      1,
    );
    expect(
      (await db.customSelect('SELECT * FROM owner_recovery_aliases').get())
          .length,
      1,
    );
  });
  test('retired operations cannot return to the upload queue', () async {
    await run();
    await expectLater(
      db.customStatement(
        "UPDATE sync_outbox SET state='pending' WHERE business_id=?",
        [b],
      ),
      throwsA(anything),
    );
    expect(
      (await db
              .customSelect(
                "SELECT * FROM sync_outbox WHERE state='reconciled'",
              )
              .get())
          .length,
      4,
    );
  });
  test(
    'durable cache updates and removals never resurrect preference originals',
    () async {
      await run();
      final cache = LocalDocumentDetailCache(database: db);
      await cache.save(b, 'server-invoice', {
        ...proof(),
        'memo': 'Updated note',
      });
      expect((await cache.load(b, 'server-invoice'))!['memo'], 'Updated note');
      await cache.remove(b, 'server-invoice');
      expect(await cache.load(b, 'server-invoice'), isNull);
      expect(await cache.loadAll(b), isEmpty);
    },
  );
}
