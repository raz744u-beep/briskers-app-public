import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_payroll_expense_review.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/payroll_expense_link_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Enrollment implements OwnerEnrollmentStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'exports actual separate settlements and flags possible unlinked expenses',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalPayrollRepository(db, business: 'shop', owner: true);
      await repo.prepare();
      for (final (id, name) in [('chris', 'Chris'), ('kam', 'Kam')]) {
        await db.customStatement(
          'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?)',
          ['shop', id, name, 4000, 0],
        );
      }
      for (final (op, person, net, date) in [
        ('a', 'chris', 32000, '2026-11-15'),
        ('b', 'chris', 55000, '2026-11-13'),
        ('c', 'kam', 56000, '2026-11-13'),
      ]) {
        await db.customStatement(
          'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
          ['shop', op, person, '2026-11-09', '{}', net, 0, net, 'Zelle', date],
        );
      }
      final cache = LocalFinancialCache(database: db);
      final rows = [
        {
          'id': 'confirmed',
          'direction': 'expense',
          'amount': 320,
          'transaction_date': '2026-11-15',
          'category': 'Payroll',
          'counterparty': 'Chris',
          'payroll_operation_id': 'a',
        },
        {
          'id': 'possible',
          'direction': 'expense',
          'amount': 550,
          'transaction_date': '2026-11-13',
          'category': 'Payroll',
          'counterparty': 'Chris',
        },
      ];
      await cache.saveTransactions('shop', rows);
      await PayrollExpenseLinkStore(db).markPending('shop', 'c');

      final review = LocalPayrollExpenseReview(db);
      final report = await review.forWeek('shop', '2026-11-09');
      expect(report.map((row) => row['net_cents']), [55000, 32000, 56000]);
      expect(report.map((row) => row['status']), [
        'Verified payment with no linked expense',
        'In Expenses',
        'Waiting for saved payroll account or category',
      ]);
      expect(
        (report.first['possible_expenses'] as List)
            .single['same_saved_reference'],
        false,
      );
      expect(
        await review.forWeek('shop', '2026-11-09', employeeId: 'kam'),
        hasLength(1),
      );
      expect(await review.forWeek('shop', '2026-11-16'), isEmpty);
      expect(await review.forWeek('other', '2026-11-09'), isEmpty);
      expect(await cache.loadTransactions('shop'), rows);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
    },
  );

  test(
    'Adam account editor resolves saved list-only expenses without guessing category',
    () async {
      final db = BriskersLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final cache = LocalFinancialCache(database: db);
      await cache.saveOptions('shop', {
        'accounts': [
          {'id': 'saved-account', 'name': 'Old checking'},
          {'id': 'business-checking', 'name': 'Business Checking - 9858'},
        ],
      });
      await cache.saveTransactions('shop', [
        {
          'id': 'adam-september',
          'kind': 'payroll',
          'account': 'Old checking',
          'amount': '-400.00',
          'transaction_date': '2026-09-17',
          'counterparty': 'Adam',
        },
        {
          'id': 'adam-october',
          'category': 'Payroll',
          'account_id': 'saved-account',
          'amount': 600,
          'transaction_date': '2026-10-02',
          'counterparty': 'Adam',
        },
      ]);
      await cache.saveTransactionDetail('shop', 'adam-october', {
        'id': 'adam-october',
        'account_id': '',
        'attachments': [
          {'id': 'original-photo'},
        ],
      });
      final september = await cache.loadPayrollExpenseForAccountEdit(
        'shop',
        'adam-september',
      );
      final october = await cache.loadPayrollExpenseForAccountEdit(
        'shop',
        'adam-october',
      );
      expect(september?['amount'], 400);
      expect(september?['account_id'], 'saved-account');
      expect(september?['category_id'], isNull);
      expect(october?['amount'], 600);
      expect(october?['account_id'], 'saved-account');
      expect(october?['attachments'], [
        {'id': 'original-photo'},
      ]);
      const identity = OwnerSessionIdentity('test-owner', 'signed-in');
      final grant = await LocalOwnerAuthorization(
        store: _Enrollment(),
        currentIdentity: () => identity,
        authenticateDevice: () async =>
            throw StateError('No new unlock required'),
        verifyOwner: (_) async => throw StateError('Network unavailable'),
        verifyLocalOwner: (business) async =>
            VerifiedOwnerEnrollment(identity, business),
      ).authorizeSession('shop');
      for (final id in ['adam-september', 'adam-october']) {
        await OfflineFinancialWriteService(
          database: db,
          cache: cache,
        ).updatePayrollExpenseAccount(
          'shop',
          id,
          expectedAccountId: 'saved-account',
          accountId: 'business-checking',
          grant: grant,
        );
      }
      final saved = await cache.loadTransactions('shop');
      expect(
        saved.map((row) => row['account_id']),
        everyElement('business-checking'),
      );
      expect(
        (await cache.loadTransactionDetail(
          'shop',
          'adam-october',
        ))?['attachments'],
        [
          {'id': 'original-photo'},
        ],
      );

      expect(
        await cache.loadPayrollExpenseForAccountEdit('other', 'adam-september'),
        isNull,
      );
    },
  );
}
