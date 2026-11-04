import 'dart:convert';

import 'package:briskers_app/local/briskers_local_database.dart';
import 'package:briskers_app/services/expenses_period_totals.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_financial_totals_journal.dart';
import 'package:briskers_app/services/offline_recurring_repository.dart';
import 'package:briskers_app/services/recurring_financial_projection.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const baseRule = <String, dynamic>{
  'id': 'weekly', 'business_id': 'shop', 'direction': 'expense',
  'account_id': 'checking', 'category_id': 'supplies', 'vendor_id': 'vendor',
  'amount_minor': 10000, 'frequency': 'weekly', 'interval_count': 1,
  'next_date': '2026-11-04', 'is_repeating': true,
};

void main() {
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;
  late LocalFinancialTotalsJournal journal;
  late OfflineRecurringRepository repo;
  const baseline = ExpensesPeriodTotals(income: 0, expenses: 0,
    transactions: 0, feesUnverified: false);
  setUp(() {
    db = BriskersLocalDatabase(NativeDatabase.memory());
    cache = LocalFinancialCache(database: db);
    journal = LocalFinancialTotalsJournal(database: db);
    repo = OfflineRecurringRepository(database: db, businessId: 'shop',
      userId: 'owner', currentUserId: () => 'owner', canRead: () => true,
      canWrite: () => true,
      projectOccurrence: const RecurringFinancialProjection('shop').call);
  });
  tearDown(() => db.close());

  test('generation and corrections project once into expenses and totals', () async {
    await cache.saveTransactions('shop', [
      {'id': 'unrelated', 'amount': 25, 'sync_state': 'pending'},
    ]);
    await repo.saveRule(baseRule);
    await repo.generateThrough('2026-11-04');
    await repo.generateThrough('2026-11-04');
    expect(await cache.loadTransactions('shop'), hasLength(2));
    expect((await journal.apply('shop', baseline)).expenses, 100);
    await repo.correctAmount('weekly', '2026-11-04', 12000);
    expect((await journal.apply('shop', baseline)).expenses, 120);
    await cache.mergeServerTransactions('shop', []);
    expect(await cache.loadTransactions('shop'), hasLength(2));
    expect((await cache.loadTransactions('shop'))
      .singleWhere((r) => r['recurring_engine_owned'] == true)['amount'], 120);
  });

  test('canonical remap preserves receipt files, metadata, queue and one delta', () async {
    await repo.saveRule(baseRule);
    await repo.generateThrough('2026-11-04');
    final occurrence = (await repo.occurrences()).single;
    final localId = occurrence['id'] as String;
    final detail = (await cache.loadTransactionDetail('shop', localId))!;
    await cache.saveTransactionDetail('shop', localId, {
      ...detail,
      'attachments': [{'id': 'photo', 'local_file_path': '/original.jpg'}],
      'receipt_details': {'transaction_id': localId, 'vendor_invoice_number': '123'},
      'receipt_items': [{'transaction_id': localId, 'description': 'Uniforms'}],
    });
    await db.customStatement('''
      INSERT INTO sync_outbox(business_id,entity_type,entity_id,operation,payload_json)
      VALUES ('shop','financial_receipt_extraction',?,'apply',?)
    ''', [localId, jsonEncode({'transaction_id': localId, 'extraction': {'review_confirmed': true}})]);
    final canonical = {...occurrence, 'id': 'server-id', 'row_version': 1};
    expect(await repo.acknowledge(rule: false, key: occurrence['_key'] as String,
      revision: occurrence['_revision'] as int, canonical: canonical), isTrue);
    expect(await cache.loadTransactionDetail('shop', localId), isNull);
    final saved = (await cache.loadTransactionDetail('shop', 'server-id'))!;
    expect((saved['attachments'] as List).single['local_file_path'], '/original.jpg');
    expect(saved['receipt_details']['transaction_id'], 'server-id');
    expect(saved['receipt_items'][0]['transaction_id'], 'server-id');
    final queued = await db.customSelect('SELECT * FROM sync_outbox').getSingle();
    expect(queued.read<String>('entity_id'), 'server-id');
    expect(jsonDecode(queued.read<String>('payload_json'))['transaction_id'], 'server-id');
    expect(await cache.loadTransactions('shop'), hasLength(1));
    expect((await journal.apply('shop', baseline)).expenses, 100);
    await cache.mergeServerTransactions('shop', []);
    expect(await cache.loadTransactions('shop'), hasLength(1));
    await journal.reconcileAndSaveBaseline('shop', 'scope',
      const ExpensesPeriodTotals(income: 0, expenses: 100,
        transactions: 1, feesUnverified: false), DateTime.now(),
      await cache.loadTransactions('shop'));
    expect(await journal.pendingCount('shop'), 0);
  });

  test('recovery does not add server amount on top of verified totals', () async {
    await repo.importSnapshot(rules: [{...baseRule, 'row_version': 1}], occurrences: [{
      ...baseRule, 'id': 'server-id', 'recurring_rule_id': 'weekly',
      'recurring_occurrence_date': '2026-11-04', 'date': '2026-11-04', 'row_version': 2,
    }]);
    expect(await journal.pendingCount('shop'), 0);
    expect(await cache.loadTransactions('shop'), hasLength(1));
  });

  test('pending ordinary expense edit rejects recovery and rolls back rules', () async {
    await cache.saveTransactionDetail('shop', 'server-id', {
      'id': 'server-id', 'business_id': 'shop', 'amount': 150, 'sync_state': 'pending',
    });
    await expectLater(repo.importSnapshot(rules: [{...baseRule, 'row_version': 1}],
      occurrences: [{...baseRule, 'id': 'server-id', 'recurring_rule_id': 'weekly',
        'recurring_occurrence_date': '2026-11-04', 'date': '2026-11-04', 'row_version': 2,
      }]), throwsStateError);
    expect(await repo.rules(), isEmpty);
    expect((await cache.loadTransactionDetail('shop', 'server-id'))!['amount'], 150);
  });
}
