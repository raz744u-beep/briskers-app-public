import 'dart:io';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/offline_recurring_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRow rule({String id = 'weekly', String next = '2026-11-04',
    String frequency = 'weekly', int amount = 10529}) => {
  'id': id, 'business_id': 'shop', 'direction': 'expense',
  'account_id': 'checking', 'category_id': 'supplies',
  'vendor_id': 'vendor', 'amount_minor': amount, 'frequency': frequency,
  'interval_count': 1, 'next_date': next, 'is_repeating': true,
  'row_version': 10,
};

RecurringRow posted({String date = '2026-11-04', int amount = 10529}) => {
  'id': 'server-$date', 'business_id': 'shop', 'direction': 'expense',
  'account_id': 'checking', 'category_id': 'supplies', 'vendor_id': 'vendor',
  'amount_minor': amount, 'date': date, 'recurring_rule_id': 'weekly',
  'recurring_occurrence_date': date, 'row_version': 20,
};

void main() {
  late Directory directory;
  late File file;
  late BriskersLocalDatabase db;
  late OfflineRecurringRepository repo;
  String? actor;
  var writable = true;
  var failProjection = false;
  var revokeDuringProjection = false;

  OfflineRecurringRepository create({String user = 'owner'}) =>
      OfflineRecurringRepository(
    database: db, businessId: 'shop', userId: user,
    currentUserId: () => actor, canRead: () => true,
    canWrite: () => writable,
    projectOccurrence: (database, before, after) async {
      // Actual SQL side effect proves rollback across the integration seam.
      await database.customStatement('''
        CREATE TABLE IF NOT EXISTS recurring_test_projection
          (id TEXT PRIMARY KEY, amount INTEGER NOT NULL)
      ''');
      if (before != null && before['id'] != after['id']) {
        await database.customStatement(
          'DELETE FROM recurring_test_projection WHERE id = ?', [before['id']]);
      }
      await database.customStatement('''
        INSERT INTO recurring_test_projection(id,amount) VALUES (?,?)
        ON CONFLICT(id) DO UPDATE SET amount=excluded.amount
      ''', [after['id'], after['amount_minor']]);
      if (revokeDuringProjection) writable = false;
      if (failProjection) throw StateError('Projection failure');
    },
  );

  setUp(() async {
    actor = 'owner';
    writable = true;
    failProjection = false;
    revokeDuringProjection = false;
    directory = await Directory.systemTemp.createTemp('recurring-engine-');
    file = File('${directory.path}/test.sqlite');
    db = BriskersLocalDatabase(NativeDatabase(file));
    repo = create();
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('recovery, restart, catch-up and repeated reconnect keep one occurrence',
      () async {
    await repo.importSnapshot(rules: [rule()], occurrences: [posted()]);
    await db.close();
    db = BriskersLocalDatabase(NativeDatabase(file));
    repo = create();
    expect(await repo.generateThrough('2026-11-18'), 2);
    expect(await repo.generateThrough('2026-11-18'), 0);
    expect((await repo.rules()).single['next_date'], '2026-11-25');
    expect(await repo.occurrences(), hasLength(3));
    for (final row in await repo.pending()) {
      if (row['_kind'] != 'occurrence') continue;
      final date = row['recurring_occurrence_date'] as String;
      expect(await repo.acknowledge(rule: false, key: row['_key'] as String,
        revision: row['_revision'] as int, canonical: posted(date: date)), isTrue);
    }
    final rows = [posted(), posted(date: '2026-11-11'), posted(date: '2026-11-18')];
    await repo.importSnapshot(rules: [], occurrences: rows);
    await repo.importSnapshot(rules: [], occurrences: rows);
    expect(await repo.occurrences(), hasLength(3));
    final projections = await db.customSelect(
      'SELECT * FROM recurring_test_projection').get();
    expect(projections, hasLength(3));
    expect(projections.every((r) => r.read<String>('id').startsWith('server-')), isTrue);
    // The ordinary expense flusher must not upload generated entries as manual expenses.
    expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
  });

  test('corrected amount propagates without copying invoice or attachments', () async {
    await repo.importSnapshot(rules: [rule(next: '2026-11-11')], occurrences: [
      {...posted(), 'attachments': [{'id': 'original'}], 'invoice_number': 'OLD'},
    ]);
    await repo.correctAmount('weekly', '2026-11-04', 11000);
    expect(await repo.generateThrough('2026-11-11'), 1);
    final next = (await repo.occurrences())
        .singleWhere((r) => r['recurring_occurrence_date'] == '2026-11-11');
    expect(next['amount_minor'], 11000);
    expect(next['attachments'], isEmpty);
    expect(next.containsKey('invoice_number'), isFalse);
    final first = (await repo.occurrences())
        .singleWhere((r) => r['recurring_occurrence_date'] == '2026-11-04');
    expect(first['attachments'], hasLength(1));
  });

  test('failed projection rolls back occurrence and cursor, retry succeeds', () async {
    await repo.importSnapshot(rules: [rule()], occurrences: []);
    failProjection = true;
    await expectLater(repo.generateThrough('2026-11-04'), throwsStateError);
    expect(await repo.occurrences(), isEmpty);
    expect((await repo.rules()).single['next_date'], '2026-11-04');
    failProjection = false;
    expect(await repo.generateThrough('2026-11-04'), 1);
  });

  test('permissions rechecked before commit, user switch blocks read', () async {
    await repo.importSnapshot(rules: [rule()], occurrences: []);
    revokeDuringProjection = true;
    await expectLater(repo.generateThrough('2026-11-04'), throwsStateError);
    expect(await repo.occurrences(), isEmpty);
    writable = true;
    actor = 'other';
    await expectLater(repo.rules(), throwsStateError);
    expect(await create(user: 'other').rules(), isEmpty);
  });

  test('pending edit survives download and stale acknowledgement', () async {
    await repo.importSnapshot(rules: [rule()], occurrences: []);
    await repo.saveRule({...rule(), 'is_repeating': false});
    final pending = (await repo.rules()).single;
    await repo.saveRule({...pending, 'remarks': 'changed again'});
    expect(await repo.acknowledge(rule: true, key: 'weekly',
      revision: pending['_revision'] as int, canonical: rule()), isFalse);
    await repo.importSnapshot(rules: [rule()], occurrences: []);
    expect((await repo.rules()).single['is_repeating'], isFalse);
    expect(await repo.generateThrough('2026-12-01'), 0);
    await repo.importSnapshot(rules: [
      {...rule(), 'row_version': 11},
    ], occurrences: []);
    expect((await repo.rules()).single['_state'], 'conflict');
    expect((await repo.rules()).single['remarks'], 'changed again');
  });

  test('server duplicate with different amount preserves local correction', () async {
    await repo.saveRule(rule());
    await repo.generateThrough('2026-11-04');
    await repo.correctAmount('weekly', '2026-11-04', 12000);
    await repo.importSnapshot(rules: [], occurrences: [posted()]);
    final row = (await repo.occurrences()).single;
    expect(row['amount_minor'], 12000);
    expect(row['_state'], 'conflict');
    expect((row['_server'] as Map)['id'], 'server-2026-11-04');
    expect(await repo.generateThrough('2026-11-11'), 0);
  });

  test('malformed or cross-business recovery rolls back whole batch', () async {
    await expectLater(repo.importSnapshot(rules: [rule()], occurrences: [
      posted(), {...posted(date: '2026-11-11'), 'business_id': 'other'},
    ]), throwsArgumentError);
    expect(await repo.rules(), isEmpty);
    expect(await repo.occurrences(), isEmpty);
    await expectLater(repo.importSnapshot(rules: [rule()], occurrences: [
      posted(), {...posted(), 'id': 'duplicate'},
    ]), throwsStateError);
    expect(await repo.rules(), isEmpty);
  });

  test('bounded catch-up advances only processed dates; inclusive end stops', () async {
    await repo.saveRule({...rule(), 'end_date': '2026-11-18'});
    expect(await repo.generateThrough('2026-12-30', limit: 2), 2);
    expect((await repo.rules()).single['next_date'], '2026-11-18');
    expect(await repo.generateThrough('2026-12-30', limit: 2), 1);
    expect((await repo.rules()).single['is_repeating'], isFalse);
    expect(await repo.generateThrough('2026-12-30'), 0);
  });

  test('paused schedule and stale server versions cannot create surprises', () async {
    await repo.importSnapshot(rules: [
      {...rule(), 'paused_reason': 'Account is inactive'},
    ], occurrences: [posted(amount: 12000)]);
    await repo.importSnapshot(rules: [], occurrences: [
      {...posted(), 'row_version': 19},
    ]);
    expect((await repo.occurrences()).single['amount_minor'], 12000);
    expect(await repo.generateThrough('2026-12-01'), 0);
  });

  test('calendar arithmetic matches server clamping, leap years, and intervals', () {
    expect(OfflineRecurringRepository.nextDate('2026-01-31', 'monthly', 1), '2026-02-28');
    expect(OfflineRecurringRepository.nextDate('2026-02-28', 'monthly', 1), '2026-03-28');
    expect(OfflineRecurringRepository.nextDate('2024-02-29', 'yearly', 1), '2025-02-28');
    expect(OfflineRecurringRepository.nextDate('2026-10-28', 'weekly', 2), '2026-11-11');
    expect(() => OfflineRecurringRepository.day('2026-02-30'), throwsFormatException);
    expect(() => OfflineRecurringRepository.nextDate('2026-11-04', 'weekly', 0), throwsArgumentError);
  });
}
