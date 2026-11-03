import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/local_job_quarantine.dart';
import 'package:briskers_app/services/local_job_repository.dart';

Future<void> _job(BriskersLocalDatabase db, String id, {String business = 'shop'}) =>
    db.customStatement("INSERT INTO local_jobs "
      "(id,business_id,access_scope,title,status,vehicle_id) VALUES (?,?,'full',?,'open','vehicle')",
      [id, business, 'Private $id']);

Future<int> _queue(BriskersLocalDatabase db, String entity, Object payload,
    {String type = 'work', String business = 'shop'}) async {
  await db.customStatement('INSERT INTO sync_outbox '
    '(business_id,entity_type,entity_id,operation,payload_json) VALUES (?,?,?,\'upsert\',?)',
    [business, type, entity, payload is String ? payload : jsonEncode(payload)]);
  return (await db.customSelect('SELECT MAX(id) AS id FROM sync_outbox').getSingle()).read<int>('id');
}

Future<List<Map<String, dynamic>>> _recovery(BriskersLocalDatabase db) async =>
    (await db.customSelect('SELECT * FROM local_job_recovery_rows ORDER BY id').get())
        .map((row) => row.data).toList();

void main() {
  test('revocation atomically hides records and preserves immutable work and file bytes across restart', () async {
    final temp = await Directory.systemTemp.createTemp('briskers-quarantine-');
    final file = File('${temp.path}/pending.jpg');
    await file.writeAsBytes([1, 2, 3]);
    final databaseFile = File('${temp.path}/cache.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(databaseFile));
    try {
      await _job(db, 'job');
      await db.customStatement("INSERT INTO local_customers (id,business_id,display_name) VALUES ('customer','shop','Keep')");
      await db.customStatement("INSERT INTO local_vehicles (id,business_id) VALUES ('vehicle','shop')");
      await db.customStatement("INSERT INTO local_documents (id,business_id,job_id,kind) VALUES ('invoice','shop','job','invoice')");
      await db.customStatement("INSERT INTO local_job_visits (id,business_id,job_id,visit_number,work_summary,sync_state) VALUES ('visit','shop','job',1,'Unsent work','pending')");
      await db.customStatement("INSERT INTO local_pre_inspections (id,business_id,job_id,notes,sync_state) VALUES ('inspection','shop','job','Unsent note','pending')");
      await db.customStatement("INSERT INTO local_pre_inspection_photos (id,business_id,inspection_id,attachment_id,local_file_path,upload_state) VALUES ('photo','shop','inspection','photo',?,'pending')", [file.path]);
      final queued = await _queue(db, 'visit', {'nested': {'job_id': 'job'}});
      await _queue(db, 'opaque', '{broken');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      final original = await _recovery(db);
      expect(original.map((row) => row['table_name']), containsAll([
        'local_jobs', 'local_job_visits', 'local_pre_inspections', 'local_pre_inspection_photos', 'sync_outbox',
      ]));
      expect(await LocalJobRepository(database: db).jobDetail('shop', 'job'), isNull);
      expect(await LocalJobRepository(database: db).listJobs('shop'), isEmpty);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      expect(await file.readAsBytes(), [1, 2, 3]);
      for (final table in ['local_customers', 'local_vehicles', 'local_documents']) {
        expect(await db.customSelect('SELECT * FROM $table').get(), hasLength(1));
      }
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(databaseFile));
      expect(await LocalJobRepository(database: db).jobDetail('shop', 'job'), isNull);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'shop', 'job'), isTrue);
      await expectLater(LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: queued),
        throwsA(isA<LocalJobQuarantineException>()));
      await expectLater(_job(db, 'job'), throwsA(anything));
      await expectLater(db.customStatement("INSERT INTO local_pre_inspection_photos (id,business_id,inspection_id,attachment_id) VALUES ('late','shop','inspection','late')"), throwsA(anything));
      await expectLater(_queue(db, 'late', {'nested': [{'job_id': 'job'}]}), throwsA(anything));
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      expect(await _recovery(db), original);
      expect(await file.readAsBytes(), [1, 2, 3]);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('verified classification resumes unrelated pushes without replaying archived operations', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await _job(db, 'revoked');
      await _job(db, 'cleanup');
      final retired = await _queue(db, 'revoked', {'job_id': 'revoked'});
      final active = await _queue(db, 'unrelated', {'customer_id': 'other'});
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked', 'cleanup']);
      await expectLater(LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: active),
        throwsA(isA<LocalJobQuarantineException>()));
      await LocalJobQuarantine.classifyJobs(db, 'shop', ['revoked', 'cleanup'], cleanupJobIds: {'cleanup'});
      await LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: active);
      await expectLater(LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: retired),
        throwsA(isA<LocalJobQuarantineException>()));
      final states = await db.customSelect('SELECT job_id,state FROM local_job_quarantines ORDER BY job_id').get();
      expect(states.map((row) => row.read<String>('state')), ['cleanup_deleted', 'permission_revoked']);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'shop', 'cleanup'), isTrue);
      expect(await LocalJobQuarantine.isJobBlocked(db, 'shop', 'revoked'), isTrue);
      await _job(db, 'other-tenant', business: 'other');
      final other = await _queue(db, 'revoked', {'job_id': 'revoked'}, business: 'other');
      await LocalJobQuarantine.assertReplayAllowed(db, 'other', outboxId: other);
    } finally { await db.close(); }
  });

  test('only post-revocation authorization can rebuild display and a second observation invalidates earlier requests', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await _job(db, 'job');
      final retired = await _queue(db, 'job', {'job_id': 'job'});
      final stale = await LocalJobQuarantine.captureGeneration(db, 'shop');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      expect(await LocalJobQuarantine.authorizeFreshJob(db, 'shop', 'job', requestGeneration: stale), isFalse);
      final first = await LocalJobQuarantine.captureGeneration(db, 'shop');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      expect(await LocalJobQuarantine.authorizeFreshJob(db, 'shop', 'job', requestGeneration: first), isFalse);
      final current = await LocalJobQuarantine.captureGeneration(db, 'shop');
      expect(current, greaterThan(first));
      expect(await LocalJobQuarantine.authorizeFreshJob(db, 'shop', 'job', requestGeneration: current), isTrue);
      await _job(db, 'job');
      expect(await LocalJobRepository(database: db).jobDetail('shop', 'job'), isNotNull);
      expect(await LocalJobQuarantine.hasRecovery(db, 'shop'), isTrue);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      await expectLater(LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: retired),
        throwsA(isA<LocalJobQuarantineException>()));
    } finally { await db.close(); }
  });

  test('late mutation receipt survives quarantine and successful receipt survives later archive', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await _job(db, 'job');
      final queued = await _queue(db, 'job', {'job_id': 'job'});
      await expectLater(LocalJobQuarantine.guardReplay(db, 'shop', () async {
        await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
        return {'payment_id': 'acknowledged-payment'};
      }, outboxId: queued), throwsA(isA<LocalJobQuarantineException>()));
      final receipt = await db.customSelect('SELECT response_json FROM local_job_recovery_receipts').getSingle();
      expect(jsonDecode(receipt.read<String>('response_json')), {'payment_id': 'acknowledged-payment'});
      await LocalJobQuarantine.classifyJobs(db, 'shop', ['job'], cleanupJobIds: {});
      final other = await _queue(db, 'other', {'customer_id': 'customer'});
      expect(await LocalJobQuarantine.guardReplay(db, 'shop', () async => 'second-ack', outboxId: other), 'second-ack');
      expect(await db.customSelect('SELECT * FROM local_job_recovery_receipts').get(), hasLength(2));
    } finally { await db.close(); }
  });

  for (final afterResponse in [false, true]) {
    test('unrelated acknowledged operation cannot replay after quarantine ${afterResponse ? 'during later acknowledgement' : 'during response'}', () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      try {
        await _job(db, 'revoked');
        final queued = await _queue(db, 'unrelated-document', {'document_id': 'unrelated-document'});
        var sends = 0;
        Future<String> send() async {
          sends++;
          if (!afterResponse) {
            await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
          }
          return 'non-idempotent-ack';
        }
        if (afterResponse) {
          await LocalJobQuarantine.guardReplay(db, 'shop', send, outboxId: queued);
          await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
          // A caller-side acknowledgement transaction aborts, so its original
          // queue row must still be blocked durably outside this transaction.
          await expectLater(db.transaction(() => LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: queued)),
            throwsA(isA<LocalJobQuarantineException>()));
        } else {
          await expectLater(LocalJobQuarantine.guardReplay(db, 'shop', send, outboxId: queued),
            throwsA(isA<LocalJobQuarantineException>()));
        }
        expect(await db.customSelect('SELECT * FROM sync_outbox').get(), hasLength(1));
        await LocalJobQuarantine.classifyJobs(db, 'shop', ['revoked'], cleanupJobIds: {});
        await expectLater(LocalJobQuarantine.guardReplay(db, 'shop', send, outboxId: queued),
          throwsA(isA<LocalJobQuarantineException>()));
        expect(sends, 1);
        final fresh = await _queue(db, 'new-unrelated', {'customer_id': 'customer'});
        await LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: fresh);
      } finally { await db.close(); }
    });
  }

  test('interrupted receipt barrier survives restart and fresh display authorization', () async {
    final temp = await Directory.systemTemp.createTemp('briskers-receipt-restart-');
    final file = File('${temp.path}/cache.sqlite');
    var db = BriskersLocalDatabase(NativeDatabase(file));
    try {
      await _job(db, 'revoked');
      final queued = await _queue(db, 'unrelated', {'document_id': 'unrelated'});
      await LocalJobQuarantine.guardReplay(db, 'shop', () async => {'line_id': 'sent-once'}, outboxId: queued);
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['revoked']);
      await LocalJobQuarantine.classifyJobs(db, 'shop', ['revoked'], cleanupJobIds: {});
      final generation = await LocalJobQuarantine.captureGeneration(db, 'shop');
      await LocalJobQuarantine.authorizeFreshJob(db, 'shop', 'revoked', requestGeneration: generation);
      await db.close();
      db = BriskersLocalDatabase(NativeDatabase(file));
      var sends = 0;
      await expectLater(LocalJobQuarantine.guardReplay(db, 'shop', () async {
        sends++;
        return 'duplicate';
      }, outboxId: queued), throwsA(isA<LocalJobQuarantineException>()));
      expect(sends, 0);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), hasLength(1));
      expect(await db.customSelect('SELECT * FROM local_job_recovery_receipts').get(), hasLength(1));
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('a feed started before a newer revocation cannot classify that unknown observation', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await _job(db, 'job');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      final observed = await LocalJobQuarantine.captureGeneration(db, 'shop');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      await LocalJobQuarantine.classifyJobs(db, 'shop', ['job'], cleanupJobIds: {}, observedGeneration: observed);
      expect(await LocalJobQuarantine.unclassifiedJobIds(db, 'shop'), {'job'});
      await expectLater(LocalJobQuarantine.assertReplayAllowed(db, 'shop'), throwsA(isA<LocalJobQuarantineException>()));
      final fresh = await LocalJobQuarantine.captureGeneration(db, 'shop');
      await LocalJobQuarantine.classifyJobs(db, 'shop', ['job'], cleanupJobIds: {}, observedGeneration: fresh);
      await LocalJobQuarantine.assertReplayAllowed(db, 'shop');
    } finally { await db.close(); }
  });

  test('partial schema from an interrupted install is repaired before replay', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await db.customStatement('CREATE TABLE local_job_quarantines ('
        'business_id TEXT NOT NULL,job_id TEXT NOT NULL,generation INTEGER NOT NULL,'
        'state TEXT NOT NULL,created_at INTEGER NOT NULL,PRIMARY KEY(business_id,job_id))');
      final queued = await _queue(db, 'unrelated', {'document_id': 'unrelated'});
      await LocalJobQuarantine.assertReplayAllowed(db, 'shop', outboxId: queued);
      expect(await LocalJobQuarantine.guardReplay(db, 'shop', () async => 'ack', outboxId: queued), 'ack');
      expect(await db.customSelect('SELECT * FROM local_job_recovery_receipts').get(), hasLength(1));
      final triggers = await db.customSelect("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='trigger' AND name LIKE 'quarantine_%'").getSingle();
      expect(triggers.read<int>('n'), 16);
    } finally { await db.close(); }
  });

  test('vehicle findings stay active only with another authorized Job; receipt queue closure uses cached transaction identities', () async {
    final db = BriskersLocalDatabase(NativeDatabase.memory());
    try {
      await _job(db, 'job');
      await _job(db, 'other-job');
      await db.customStatement("INSERT INTO local_findings (id,business_id,vehicle_id,found_job_id,body,status,sync_state) VALUES ('other-finding','shop','vehicle','other-job','Keep','open','pending')");
      await db.customStatement("INSERT INTO local_financial_cache (business_id,cache_key,payload_json) VALUES ('shop','transactions_snapshot',?)", [jsonEncode([
        {'id': 'linked-transaction', 'job_id': 'job'},
        {'id': 'unrelated-transaction', 'job_id': 'other-job'},
      ])]);
      await _queue(db, 'linked-photo', {'transaction_id': 'linked-transaction'}, type: 'financial_photo');
      await _queue(db, 'unknown-photo', {'transaction_id': 'unknown-transaction'}, type: 'financial_photo');
      await _queue(db, 'unrelated-photo', {'transaction_id': 'unrelated-transaction'}, type: 'financial_photo');
      await LocalJobQuarantine.quarantineJobs(db, 'shop', ['job']);
      expect(await db.customSelect('SELECT * FROM local_findings').get(), hasLength(1));
      final remaining = await db.customSelect('SELECT entity_id FROM sync_outbox').getSingle();
      expect(remaining.read<String>('entity_id'), 'unrelated-photo');
      final archived = await _recovery(db);
      expect(archived.where((row) => row['table_name'] == 'sync_outbox'), hasLength(2));
      await expectLater(_queue(db, 'later-photo', {'transaction_id': 'linked-transaction'}, type: 'financial_photo'), throwsA(anything));
    } finally { await db.close(); }
  });
}
