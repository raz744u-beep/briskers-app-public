import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/local_job_repository.dart';
import 'package:briskers_app/services/local_job_retirement.dart';
import 'package:briskers_app/services/local_sync_status_repository.dart';
import 'package:briskers_app/services/offline_job_admin_service.dart';
import 'package:briskers_app/services/owner_job_retirement_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const visibilityScope =
    '1111111111111111111111111111111111111111111111111111111111111111';
const nextVisibilityScope =
    '2222222222222222222222222222222222222222222222222222222222222222';
const business = '00000000-0000-4000-8000-000000000001';
const job = '00000000-0000-4000-8000-000000000002';
const actor = '00000000-0000-4000-8000-000000000003';
const invoice = '00000000-0000-4000-8000-000000000004';
const estimate = '00000000-0000-4000-8000-000000000005';
const operation = '00000000-0000-4000-8000-000000000006';
const other = '00000000-0000-4000-8000-000000000007';

Map<String, dynamic> snapshot() => {
  'schema_version': 2,
  'protocol_version': ownerRetirementProtocol,
  'business_id': business,
  'job_id': job,
  'actor_id': actor,
  'inventory_complete': true,
  'write_fences_verified': true,
  'can_retire': true,
  'blocked_reasons': <dynamic>[],
  'job_number': 'TEST-1',
  'invoices': [
    {
      'id': invoice,
      'business_id': business,
      'job_id': job,
      'kind': 'invoice',
      'origin': 'native',
      'status': 'draft',
      'has_financial_history': false,
      'has_pending_operations': false,
      'has_protected_history': false,
    },
  ],
  'estimates_preserved': [
    {'id': estimate, 'kind': 'estimate'},
  ],
};
Map<String, dynamic> tombstone(String kind, String id, int cursor) => {
  'business_id': business,
  'entity_kind': kind,
  'entity_id': id,
  'job_id': job,
  'operation_id': operation,
  'cursor': cursor,
};

Map<String, dynamic> feedPage(
  int cursor,
  List<Map<String, dynamic>> rows, {
  String scope = visibilityScope,
  String reader = 'staff',
  String readerActor = actor,
  bool more = false,
}) => {
  'schema_version': 2,
  'business_id': business,
  'cursor': cursor,
  'has_more': more,
  'actor_id': readerActor,
  'reader_scope': reader,
  'visibility_scope': scope,
  'tombstones': rows,
};

class Gateway extends OwnerJobRetirementGateway {
  String? signedInActor = actor;
  Map<String, dynamic> plan = snapshot();
  PostgrestException? previewError;
  final calls = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(
    String operationId,
    Map<String, dynamic> snapshot,
  )?
  onExecute;
  Future<Map<String, dynamic>> Function(int cursor)? onTombstones;
  @override
  void assertActor(String expected) {
    if (signedInActor != expected) throw StateError('Session changed');
  }

  @override
  Future<Map<String, dynamic>> preview(String businessId, String jobId) async {
    if (previewError != null) throw previewError!;
    return Map<String, dynamic>.from(jsonDecode(jsonEncode(plan)) as Map);
  }

  @override
  Future<Map<String, dynamic>> execute(
    String businessId,
    String jobId,
    String operationId,
    Map<String, dynamic> snapshot,
  ) async {
    calls.add({
      'business_id': businessId,
      'job_id': jobId,
      'operation_id': operationId,
      'snapshot': snapshot,
    });
    if (onExecute != null) return onExecute!(operationId, snapshot);
    return receipt(operationId, snapshot);
  }

  Map<String, dynamic> receipt(
    String operationId,
    Map<String, dynamic> snapshot,
  ) => {
    'schema_version': 2,
    'protocol_version': ownerRetirementProtocol,
    'business_id': business,
    'job_id': job,
    'operation_id': operationId,
    'retired_invoice_ids': [invoice],
    'estimates_preserved': snapshot['estimates_preserved'],
  };
  @override
  Future<Map<String, dynamic>> tombstones(
    String businessId, {
    required int afterCursor,
    int limit = 200,
  }) async => onTombstones != null
      ? onTombstones!(afterCursor)
      : {
          'schema_version': 2,
          'business_id': businessId,
          'cursor': afterCursor,
          'has_more': false,
          'actor_id': actor,
          'reader_scope': 'staff',
          'visibility_scope': visibilityScope,
          'tombstones': <dynamic>[],
        };
}

Future<void> seed(BriskersLocalDatabase db) async {
  await db.customStatement(
    "INSERT INTO local_jobs (id,business_id,access_scope,title,status,job_number) VALUES (?,?,'full','Synthetic Job','open','TEST-1')",
    [job, business],
  );
  await db.customStatement(
    "INSERT INTO local_documents (id,business_id,job_id,kind,status) VALUES (?,?,?,'invoice','draft')",
    [invoice, business, job],
  );
  await db.customStatement(
    "INSERT INTO local_documents (id,business_id,job_id,kind,status) VALUES (?,?,?,'estimate','accepted')",
    [estimate, business, job],
  );
  await db.customStatement(
    "INSERT INTO local_customers (id,business_id,display_name) VALUES ('shared-customer',?,'Keep me')",
    [business],
  );
  await db.customStatement(
    "INSERT INTO local_vehicles (id,business_id) VALUES ('shared-vehicle',?)",
    [business],
  );
}

Future<OwnerJobRetirementPreview> preview(
  OwnerJobRetirementService service, {
  bool online = true,
}) => service.preview(
  business,
  job,
  actorId: actor,
  isOwner: true,
  online: online,
);
Future<OwnerJobRetirementResult> queue(
  OwnerJobRetirementService service,
  OwnerJobRetirementPreview plan, {
  bool online = false,
}) =>
    service.queueConfirmed(plan, actorId: actor, isOwner: true, online: online);

void main() {
  test('retirement readers include staff and customers with separate Owner eligibility', () {
    for (final role in ['owner', 'manager', 'office', 'mechanic', 'porter']) {
      expect(OwnerJobRetirementService.isStaffRole(role), isTrue);
      expect(OwnerJobRetirementService.isTombstoneReaderRole(role), isTrue);
    }
    for (final role in ['customer', 'guest', 'employee', 'Owner', '']) {
      expect(OwnerJobRetirementService.isStaffRole(role), isFalse);
      expect(
        OwnerJobRetirementService.isTombstoneReaderRole(role),
        role == 'customer',
      );
    }
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  late BriskersLocalDatabase db;
  late Gateway gateway;
  late OwnerJobRetirementService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BriskersLocalDatabase(NativeDatabase.memory());
    gateway = Gateway();
    service = OwnerJobRetirementService(database: db, gateway: gateway);
    await seed(db);
  });
  tearDown(() async => db.close());

  test(
    'persists exact consent before send and accepts only verified receipt',
    () async {
      final plan = await preview(service);
      plan.snapshot['job_id'] = other; // defensive copy does not alter consent
      gateway.onExecute = (op, snap) async {
        final rows = await db
            .customSelect('SELECT * FROM local_job_retirement_requests')
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.read<String>('operation_id'), op);
        expect(jsonDecode(rows.single.read<String>('snapshot_json')), snap);
        expect(rows.single.read<int>('outcome_uncertain'), 1);
        return gateway.receipt(op, snap);
      };
      final result = await queue(service, plan, online: true);
      expect(result.status, OwnerJobRetirementStatus.accepted);
      expect(
        await LocalJobRepository(database: db).jobDetail(business, job),
        isNull,
      );
      expect(
        await db.customSelect('SELECT * FROM local_jobs').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM local_documents').get(),
        hasLength(2),
      );
      expect(
        await db.customSelect('SELECT * FROM local_customers').get(),
        hasLength(1),
      );
      expect(
        await db.customSelect('SELECT * FROM local_vehicles').get(),
        hasLength(1),
      );
    },
  );

  test('offline requires exact cached authoritative preview and keeps pending truthful', () async {
    await expectLater(preview(service, online: false), throwsStateError);
    await preview(service);
    final offline = await preview(service, online: false);
    final result = await queue(service, offline);
    expect(result.status, OwnerJobRetirementStatus.pending);
    expect(result.message, contains('confirmation is pending'));
    expect(gateway.calls, isEmpty);
    expect(
      (await LocalSyncStatusRepository(database: db).load(business))
          .pendingUploads,
      1,
    );
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
  });

  test('paid and malformed scope/version previews fail closed', () async {
    gateway.plan['invoices'][0]['has_financial_history'] = true;
    await expectLater(preview(service), throwsStateError);
    gateway.plan = snapshot()..['business_id'] = other;
    await expectLater(preview(service), throwsStateError);
    gateway.plan = snapshot()..['protocol_version'] = 'unverified';
    await expectLater(preview(service), throwsStateError);
    await expectLater(
      service.preview(business, 'TEST-1', actorId: actor, isOwner: true),
      throwsStateError,
    );
    await expectLater(
      service.preview(business, job, actorId: actor, isOwner: false),
      throwsStateError,
    );
    expect(gateway.calls, isEmpty);
  });

  test(
    'work arriving after preview blocks queue without hiding data',
    () async {
      final plan = await preview(service);
      await db.customStatement(
        "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'invoice_payment_received',?,'create','{}')",
        [business, invoice],
      );
      await expectLater(queue(service, plan), throwsStateError);
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(1),
      );
    },
  );

  test('pending tombstone rejects stale cache/outbox writes and identity moves', () async {
    await queue(service, await preview(service));
    for (final sql in [
      "UPDATE local_jobs SET title='Stale' WHERE id='$job'",
      "UPDATE local_jobs SET id='$other' WHERE id='$job'",
      "UPDATE local_documents SET job_id='$other' WHERE id='$invoice'",
      "DELETE FROM local_jobs WHERE id='$job'",
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES ('$business','job_admin','$job','update','{}')",
    ]) {
      await expectLater(db.customStatement(sql), throwsA(anything));
    }
    await db.customStatement(
      "UPDATE local_documents SET status='accepted' WHERE id=?",
      [estimate],
    );
    expect(await LocalJobRetirement.isJobBlocked(db, other, job), isFalse);
  });

  test(
    'known first rejection restores rows and requires fresh confirmation',
    () async {
      gateway.onExecute = (op, snap) async => throw const PostgrestException(
        message: 'Changed snapshot',
        code: 'P0001',
        details: 'retirement_snapshot_changed',
      );
      final result = await queue(service, await preview(service), online: true);
      expect(result.status, OwnerJobRetirementStatus.rejected);
      expect(
        await LocalJobRepository(database: db).jobDetail(business, job),
        isNotNull,
      );
      expect(
        await db.customSelect('SELECT * FROM local_documents').get(),
        hasLength(2),
      );
    },
  );

  test(
    'known rollback retry followed by conflict can restore without uncertainty',
    () async {
      gateway.onExecute = (op, snap) async =>
          throw const PostgrestException(message: 'deadlock', code: '40P01');
      final queued = await queue(service, await preview(service), online: true);
      expect(queued.status, OwnerJobRetirementStatus.pending);
      expect(
        (await db
                .customSelect(
                  'SELECT outcome_uncertain FROM local_job_retirement_requests',
                )
                .getSingle())
            .read<int>('outcome_uncertain'),
        0,
      );
      gateway.onExecute = (op, snap) async => throw const PostgrestException(
        message: 'Changed snapshot',
        code: 'P0001',
        details: 'retirement_snapshot_changed',
      );
      await service.flush(business, actorId: actor, isOwner: true);
      expect(
        (await service.status(business, job))!.status,
        OwnerJobRetirementStatus.rejected,
      );
      expect(gateway.calls.last['operation_id'], queued.operationId);
    },
  );

  test('lost response followed by revoked permission never restores a committed Job', () async {
    gateway.onExecute = (op, snap) async =>
        throw TimeoutException('response lost after commit');
    final queued = await queue(service, await preview(service), online: true);
    gateway.onExecute = (op, snap) async =>
        throw const PostgrestException(message: 'Owner revoked', code: '42501');
    await service.flush(business, actorId: actor, isOwner: true);
    expect(
      (await service.status(business, job))!.status,
      OwnerJobRetirementStatus.pending,
    );
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    expect(gateway.calls.last['operation_id'], queued.operationId);
    expect(gateway.calls.last['snapshot'], gateway.calls.first['snapshot']);
  });

  test('malformed receipt and session change keep request pending', () async {
    gateway.onExecute = (op, snap) async => gateway.receipt(other, snap);
    await queue(service, await preview(service), online: true);
    expect(
      (await service.status(business, job))!.status,
      OwnerJobRetirementStatus.pending,
    );
    gateway.signedInActor = other;
    await service.flush(business, actorId: actor, isOwner: true);
    expect(gateway.calls, hasLength(1));
    await service.flush(business, actorId: other, isOwner: true);
    expect(gateway.calls, hasLength(1));
  });

  test(
    'concurrent flushes use one request and retain one operation ID',
    () async {
      final waiting = Completer<void>();
      gateway.onExecute = (op, snap) async {
        await waiting.future;
        return gateway.receipt(op, snap);
      };
      await queue(service, await preview(service));
      final first = service.flush(business, actorId: actor, isOwner: true);
      final second = OwnerJobRetirementService(
        database: db,
        gateway: gateway,
      ).flush(business, actorId: actor, isOwner: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gateway.calls, hasLength(1));
      waiting.complete();
      await Future.wait([first, second]);
      expect(
        (await service.status(business, job))!.status,
        OwnerJobRetirementStatus.accepted,
      );
    },
  );

  test('concurrent feed readers share traversal and resume from committed cursor', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final cursors = <int>[];
    gateway.onTombstones = (cursor) async {
      cursors.add(cursor);
      if (!entered.isCompleted) entered.complete();
      await release.future;
      return cursor == 0
          ? feedPage(1, [tombstone('job', job, 1)])
          : feedPage(cursor, []);
    };
    final first = service.pullTombstones(business);
    await entered.future;
    final second = OwnerJobRetirementService(
      database: db,
      gateway: gateway,
    ).pullTombstones(business);
    // Drain queued database work while the first network response is held.
    await db.customSelect('SELECT 1').get();
    release.complete();
    await Future.wait([first, second]);
    expect(cursors, [0]);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    await service.pullTombstones(business);
    expect(cursors, [0, 1]);
  });

  test('failed shared feed releases its slot and allows safe retry', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    gateway.onTombstones = (cursor) async {
      calls++;
      if (!entered.isCompleted) entered.complete();
      await release.future;
      throw TimeoutException('Synthetic feed failure');
    };
    final first = expectLater(service.pullTombstones(business), throwsA(isA<TimeoutException>()));
    await entered.future;
    final second = expectLater(
      OwnerJobRetirementService(database: db, gateway: gateway).pullTombstones(business),
      throwsA(isA<TimeoutException>()),
    );
    release.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    gateway.onTombstones = (cursor) async {
      expect(cursor, 0);
      return feedPage(1, [tombstone('job', job, 1)]);
    };
    await service.pullTombstones(business);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
  });

  test('paginated cross-device tombstones atomically retain cursor, local work and shared data', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'invoice_payment_received',?,'create','{}')",
      [business, invoice],
    );
    gateway.onTombstones = (cursor) async => {
      'schema_version': 2,
      'business_id': business,
      'cursor': cursor == 0 ? 1 : 2,
      'has_more': cursor == 0,
      'actor_id': actor,
      'reader_scope': 'staff',
      'visibility_scope': visibilityScope,
      'tombstones': [
        cursor == 0
            ? tombstone('job', job, 1)
            : tombstone('invoice', invoice, 2),
      ],
    };
    await service.pullTombstones(business);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    expect(
      await LocalJobRetirement.isDocumentBlocked(db, business, invoice),
      isTrue,
    );
    expect(
      (await db.customSelect('SELECT state FROM sync_outbox').getSingle())
          .read<String>('state'),
      'retirement_quarantine',
    );
    expect(
      await db
          .customSelect('SELECT * FROM local_job_retirement_recovery')
          .get(),
      hasLength(1),
    );
    expect(
      (await db
              .customSelect(
                "SELECT last_server_cursor FROM local_sync_states WHERE scope='job_retirements_v2'",
              )
              .getSingle())
          .read<int>('last_server_cursor'),
      2,
    );
    await expectLater(
      db.customStatement(
        "UPDATE local_job_retirement_entities SET state='rejected'",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('DELETE FROM local_job_retirement_entities'),
      throwsA(anything),
    );
    expect(
      await db.customSelect('SELECT * FROM local_vehicles').get(),
      hasLength(1),
    );
  });

  test('invalid tombstone page and request failure do not advance cursor and surface diagnostics', () async {
    await service.pullTombstones(business);
    gateway.onTombstones = (cursor) async => {
      'schema_version': 2,
      'business_id': other,
      'cursor': 1,
      'has_more': false,
      'actor_id': actor,
      'reader_scope': 'staff',
      'visibility_scope': visibilityScope,
      'tombstones': [tombstone('job', job, 1)],
    };
    await expectLater(service.pullTombstones(business), throwsStateError);
    final state = await db
        .customSelect(
          "SELECT * FROM local_sync_states WHERE scope='job_retirements_v2'",
        )
        .getSingle();
    expect(state.read<int>('last_server_cursor'), 0);
    expect(state.read<String>('last_error'), contains('paused'));
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
  });

  for (final change in ['actor', 'promotion', 'customer linkage']) {
    test('$change changes reset persisted scope before applying a page', () async {
      gateway.onTombstones = (_) async =>
          feedPage(2, [tombstone('job', job, 2)], reader: 'customer');
      await service.pullTombstones(business);
      final nextActor = change == 'actor' ? other : actor;
      gateway.signedInActor = nextActor;
      final reader = change == 'promotion' ? 'staff' : 'customer';
      final oldRecord = change == 'promotion'
          ? tombstone('invoice', invoice, 1)
          : {...tombstone('job', other, 1), 'job_id': other};
      final cursors = <int>[];
      gateway.onTombstones = (cursor) async {
        cursors.add(cursor);
        if (cursor == 2) {
          return feedPage(
            2,
            [],
            scope: nextVisibilityScope,
            reader: reader,
            readerActor: nextActor,
          );
        }
        expect(cursor, 0);
        return feedPage(
          2,
          [oldRecord, tombstone('job', job, 2)],
          scope: nextVisibilityScope,
          reader: reader,
          readerActor: nextActor,
        );
      };
      // A new service proves the cursor context survived service restart.
      await OwnerJobRetirementService(
        database: db,
        gateway: gateway,
      ).pullTombstones(business);
      expect(cursors, [2, 0]);
      final entities = await db
          .customSelect(
            "SELECT entity_id FROM local_job_retirement_entities WHERE entity_kind='${change == 'promotion' ? 'invoice' : 'job'}'",
          )
          .get();
      expect(
        entities.map((row) => row.read<String>('entity_id')),
        contains(change == 'promotion' ? invoice : other),
      );
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
      expect(
        (await db
                .customSelect(
                  'SELECT visibility_scope FROM local_job_retirement_feed_context',
                )
                .getSingle())
            .read<String>('visibility_scope'),
        nextVisibilityScope,
      );
    });
  }

  test('scope changes mid-pagination discard that page and replay without clearing fences', () async {
    final cursors = <int>[];
    gateway.onTombstones = (cursor) async {
      cursors.add(cursor);
      if (cursors.length == 1) {
        return feedPage(
          2,
          [tombstone('job', job, 2)],
          reader: 'customer',
          more: true,
        );
      }
      if (cursors.length == 2) {
        expect(cursor, 2);
        return feedPage(3, [
          {...tombstone('job', other, 3), 'job_id': other},
        ], scope: nextVisibilityScope);
      }
      expect(cursor, 0);
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
      expect(
        await LocalJobRetirement.isJobBlocked(db, business, other),
        isFalse,
      );
      expect(
        (await db
                .customSelect(
                  "SELECT last_server_cursor FROM local_sync_states WHERE scope='job_retirements_v2'",
                )
                .getSingle())
            .read<int>('last_server_cursor'),
        2,
      );
      return feedPage(3, [
        tombstone('invoice', invoice, 1),
        tombstone('job', job, 2),
        {...tombstone('job', other, 3), 'job_id': other},
      ], scope: nextVisibilityScope);
    };
    await service.pullTombstones(business);
    expect(cursors, [0, 2, 0]);
    expect(await LocalJobRetirement.isJobBlocked(db, business, other), isTrue);
    expect(
      await LocalJobRetirement.isDocumentBlocked(db, business, invoice),
      isTrue,
    );
  });

  test(
    'failed scope replay retains committed cursor, scope and permanent fences',
    () async {
      gateway.onTombstones = (_) async =>
          feedPage(2, [tombstone('job', job, 2)]);
      await service.pullTombstones(business);
      final cursors = <int>[];
      gateway.onTombstones = (cursor) async {
        cursors.add(cursor);
        if (cursor == 2) {
          return feedPage(2, [], scope: nextVisibilityScope);
        }
        throw TimeoutException('Synthetic replay interruption');
      };
      await expectLater(
        service.pullTombstones(business),
        throwsA(isA<TimeoutException>()),
      );
      expect(cursors, [2, 0]);
      expect(
        (await db
                .customSelect(
                  "SELECT last_server_cursor FROM local_sync_states WHERE scope='job_retirements_v2'",
                )
                .getSingle())
            .read<int>('last_server_cursor'),
        2,
      );
      expect(
        (await db
                .customSelect(
                  'SELECT visibility_scope FROM local_job_retirement_feed_context',
                )
                .getSingle())
            .read<String>('visibility_scope'),
        visibilityScope,
      );
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    },
  );

  for (final invalid in [
    'missing scope',
    'bad scope',
    'bad actor',
    'bad reader',
    'changed session',
  ]) {
    test('$invalid fails closed before applying tombstones', () async {
      final page = feedPage(1, [tombstone('job', job, 1)]);
      if (invalid == 'missing scope') {
        page.remove('visibility_scope');
      }
      if (invalid == 'bad scope') {
        page['visibility_scope'] = 'unbound';
      }
      if (invalid == 'bad actor') {
        page['actor_id'] = 'invalid';
      }
      if (invalid == 'bad reader') {
        page['reader_scope'] = 'guest';
      }
      gateway.onTombstones = (_) async {
        if (invalid == 'changed session') {
          gateway.signedInActor = other;
        }
        return page;
      };
      await expectLater(service.pullTombstones(business), throwsStateError);
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
      expect(
        await db
            .customSelect('SELECT * FROM local_job_retirement_feed_context')
            .get(),
        isEmpty,
      );
      expect(
        (await db
                .customSelect(
                  "SELECT last_server_cursor FROM local_sync_states WHERE scope='job_retirements_v2'",
                )
                .getSingle())
            .readNullable<int>('last_server_cursor'),
        isNull,
      );
    });
  }

  test(
    'missing preview deployment is actionable without hiding unrelated errors',
    () async {
      for (final code in ['PGRST202', '42883']) {
        gateway.previewError = PostgrestException(
          message: 'Missing briskers_job_retirement_preview_v2',
          code: code,
        );
        await expectLater(
          preview(service),
          throwsA(
            isA<OwnerJobDeletionUnavailable>().having(
              (error) => error.message,
              'message',
              'Job deletion is temporarily unavailable. Nothing has been deleted.',
            ),
          ),
        );
      }
      expect(
        ownerJobDeletionFailureMessage(OwnerJobDeletionUnavailable()),
        'Job deletion is temporarily unavailable. Nothing has been deleted.',
      );
      expect(gateway.calls, isEmpty);
      expect(await service.status(business, job), isNull);
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
      final screen = File('lib/screens/jobs/job_detail_screen.dart').readAsStringSync();
      expect(screen, contains('Text(ownerJobDeletionFailureMessage(error))'));
      for (final error in [
        const PostgrestException(message: 'Owner required', code: '42501'),
        const PostgrestException(
          message: 'Missing unrelated function',
          code: 'PGRST202',
        ),
      ]) {
        gateway.previewError = error;
        await expectLater(preview(service), throwsA(same(error)));
      }
      expect(
        await db
            .customSelect('SELECT * FROM local_job_retirement_previews')
            .get(),
        isEmpty,
      );
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isFalse);
    },
  );

  test('missing deployment permits only never-used read compatibility, never deletion', () async {
    gateway.onTombstones = (cursor) async => throw const PostgrestException(
      message: 'Missing briskers_job_retirement_tombstones_v2',
      code: 'PGRST202',
    );
    await service.pullTombstones(business);
    await preview(service);
    await expectLater(
      service.pullTombstones(business),
      throwsA(isA<PostgrestException>()),
    );
    gateway.onExecute = (op, snap) async => throw const PostgrestException(
      message: 'Missing briskers_job_retirement_execute_v2',
      code: 'PGRST202',
    );
    final result = await queue(service, await preview(service), online: true);
    expect(result.status, OwnerJobRetirementStatus.rejected);
    expect(result.message, contains('not deployed'));
  });

  test('local unsent creation cancels durably; an attempted create is never treated unsent', () async {
    final create = OfflineJobAdminService(database: db);
    final id = await create.queueJobCreate(
      business,
      customerId: other,
      customerName: 'Synthetic',
      title: 'Never sent',
    );
    final plan = await service.preview(
      business,
      id,
      actorId: actor,
      isOwner: true,
      online: false,
    );
    final result = await queue(service, plan);
    expect(result.status, OwnerJobRetirementStatus.locallyCancelled);
    expect(
      (await db
              .customSelect(
                "SELECT state FROM sync_outbox WHERE entity_type='job_create'",
              )
              .getSingle())
          .read<String>('state'),
      'cancelled',
    );
    final ambiguous = await create.queueJobCreate(
      business,
      customerId: other,
      customerName: 'Synthetic',
      title: 'May exist',
    );
    await db.customStatement(
      "UPDATE sync_outbox SET attempt_count=1 WHERE entity_id=?",
      [ambiguous],
    );
    await expectLater(
      service.preview(
        business,
        ambiguous,
        actorId: actor,
        isOwner: true,
        online: false,
      ),
      throwsStateError,
    );
  });

  test(
    'late replay acknowledgement is preserved after a remote retirement',
    () async {
      await db.customStatement(
        "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'job_admin',?,'update','{}')",
        [business, job],
      );
      final id =
          (await db.customSelect('SELECT id FROM sync_outbox').getSingle())
              .read<int>('id');
      gateway.onTombstones = (cursor) async => {
        'schema_version': 2,
        'business_id': business,
        'cursor': 1,
        'has_more': false,
        'actor_id': actor,
        'reader_scope': 'staff',
        'visibility_scope': visibilityScope,
        'tombstones': [tombstone('job', job, 1)],
      };
      await expectLater(
        LocalJobQuarantine.guardReplay(db, business, () async {
          await service.pullTombstones(business);
          return {'server_receipt': 'keep'};
        }, outboxId: id),
        throwsA(isA<LocalJobQuarantineException>()),
      );
      expect(
        await db
            .customSelect('SELECT * FROM local_job_recovery_receipts')
            .get(),
        hasLength(1),
      );
      expect(
        await db
            .customSelect('SELECT * FROM local_job_retirement_recovery')
            .get(),
        hasLength(1),
      );
    },
  );

  test('already retired elsewhere reconciles before reporting accepted or restoring visibility', () async {
    gateway.onExecute = (op, snap) async => throw const PostgrestException(
      message: 'Job already retired; reconcile tombstones',
      code: '55000',
    );
    gateway.onTombstones = (cursor) async => throw TimeoutException('offline');
    final first = await queue(service, await preview(service), online: true);
    expect(first.status, OwnerJobRetirementStatus.pending);
    expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    gateway.onExecute = (op, snap) async =>
        throw const PostgrestException(message: 'Owner revoked', code: '42501');
    await service.flush(business, actorId: actor, isOwner: true);
    expect(
      (await service.status(business, job))!.status,
      OwnerJobRetirementStatus.pending,
    );
    gateway.onExecute = (op, snap) async => throw const PostgrestException(
      message: 'Job already retired; reconcile tombstones',
      code: '55000',
    );
    gateway.onTombstones = (cursor) async => {
      'schema_version': 2,
      'business_id': business,
      'cursor': 1,
      'has_more': false,
      'actor_id': actor,
      'reader_scope': 'staff',
      'visibility_scope': visibilityScope,
      'tombstones': [tombstone('job', job, 1)],
    };
    await service.flush(business, actorId: actor, isOwner: true);
    expect(
      (await service.status(business, job))!.status,
      OwnerJobRetirementStatus.accepted,
    );
  });

  test('uncertain linked expense receipt is quarantined with original file reference', () async {
    await db.customStatement(
      "INSERT INTO sync_outbox (business_id,entity_type,entity_id,operation,payload_json) VALUES (?,'financial_photo','expense-photo','upload',?)",
      [
        business,
        jsonEncode({
          'transaction_id': 'unknown-expense',
          'local_file_path': '/synthetic/keep-photo.jpg',
        }),
      ],
    );
    gateway.onTombstones = (cursor) async => {
      'schema_version': 2,
      'business_id': business,
      'cursor': 1,
      'has_more': false,
      'actor_id': actor,
      'reader_scope': 'staff',
      'visibility_scope': visibilityScope,
      'tombstones': [tombstone('job', job, 1)],
    };
    await service.pullTombstones(business);
    final row = await db.customSelect('SELECT * FROM sync_outbox').getSingle();
    expect(row.read<String>('state'), 'retirement_quarantine');
    expect(
      row.read<String>('payload_json'),
      contains('/synthetic/keep-photo.jpg'),
    );
    final recovery = await db
        .customSelect('SELECT original_json FROM local_job_retirement_recovery')
        .getSingle();
    expect(
      recovery.read<String>('original_json'),
      contains('/synthetic/keep-photo.jpg'),
    );
  });

  test(
    'Force Offline is proven no-send even immediately before production RPC',
    () async {
      final mode = BriskersConnectionModeController.instance;
      final before = mode.mode;
      try {
        await mode.setMode(BriskersConnectionMode.offline);
        await expectLater(
          const OwnerJobRetirementGateway().execute(
            business,
            job,
            operation,
            snapshot(),
          ),
          throwsA(isA<OwnerJobRetirementNotSent>()),
        );
      } finally {
        await mode.setMode(before);
      }
    },
  );

  test('proven no-send permits later conflict rejection without manufacturing uncertainty', () async {
    gateway.onExecute = (op, snap) async =>
        throw OwnerJobRetirementNotSent('Force Offline');
    final result = await queue(service, await preview(service), online: true);
    expect(result.status, OwnerJobRetirementStatus.pending);
    expect(
      (await db
              .customSelect(
                'SELECT outcome_uncertain FROM local_job_retirement_requests',
              )
              .getSingle())
          .read<int>('outcome_uncertain'),
      0,
    );
    gateway.onExecute = (op, snap) async => throw const PostgrestException(
      message: 'Changed snapshot',
      code: 'P0001',
      details: 'retirement_snapshot_changed',
    );
    await service.flush(business, actorId: actor, isOwner: true);
    expect(
      (await service.status(business, job))!.status,
      OwnerJobRetirementStatus.rejected,
    );
  });

  test(
    'proven no-send retry never clears a previously ambiguous outcome',
    () async {
      gateway.onExecute = (op, snap) async =>
          throw TimeoutException('lost response');
      await queue(service, await preview(service), online: true);
      gateway.onExecute = (op, snap) async =>
          throw OwnerJobRetirementNotSent('Force Offline');
      await service.flush(business, actorId: actor, isOwner: true);
      expect(
        (await db
                .customSelect(
                  'SELECT outcome_uncertain FROM local_job_retirement_requests',
                )
                .getSingle())
            .read<int>('outcome_uncertain'),
        1,
      );
      gateway.onExecute = (op, snap) async => throw const PostgrestException(
        message: 'Changed snapshot',
        code: 'P0001',
        details: 'retirement_snapshot_changed',
      );
      await service.flush(business, actorId: actor, isOwner: true);
      expect(
        (await service.status(business, job))!.status,
        OwnerJobRetirementStatus.pending,
      );
      expect(await LocalJobRetirement.isJobBlocked(db, business, job), isTrue);
    },
  );

  test(
    'response loss survives process restart with same consent and UUID',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'owner-retirement-restart-',
      );
      final file = File('${directory.path}/cache.sqlite');
      var persisted = BriskersLocalDatabase(NativeDatabase(file));
      try {
        await seed(persisted);
        gateway.onExecute = (op, snap) async => throw TimeoutException('lost');
        var persistentService = OwnerJobRetirementService(
          database: persisted,
          gateway: gateway,
        );
        final result = await queue(
          persistentService,
          await preview(persistentService),
          online: true,
        );
        await persisted.close();
        persisted = BriskersLocalDatabase(NativeDatabase(file));
        persistentService = OwnerJobRetirementService(
          database: persisted,
          gateway: gateway,
        );
        expect(
          await LocalJobRetirement.isJobBlocked(persisted, business, job),
          isTrue,
        );
        gateway.onExecute = null;
        await persistentService.flush(business, actorId: actor, isOwner: true);
        expect(
          (await persistentService.status(business, job))!.status,
          OwnerJobRetirementStatus.accepted,
        );
        expect(gateway.calls.last['operation_id'], result.operationId);
        expect(gateway.calls.last['snapshot'], gateway.calls.first['snapshot']);
      } finally {
        await persisted.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
