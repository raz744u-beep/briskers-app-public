import 'dart:io';

import 'package:briskers_app/core/connection_mode.dart';
import 'package:briskers_app/local/briskers_local_database.dart'
    show BriskersLocalDatabase;
import 'package:briskers_app/services/briskers_api.dart';
import 'package:briskers_app/services/local_expense_subtotal.dart';
import 'package:briskers_app/services/local_financial_cache.dart';
import 'package:briskers_app/services/local_owner_authorization.dart';
import 'package:briskers_app/services/local_payroll_expense_recovery.dart';
import 'package:briskers_app/services/local_payroll_expense_review.dart';
import 'package:briskers_app/services/local_payroll_repository.dart';
import 'package:briskers_app/services/offline_financial_write_service.dart';
import 'package:briskers_app/services/payroll_expense_identity.dart';
import 'package:briskers_app/services/payroll_expense_link_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Enrollment implements OwnerEnrollmentStore {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

class _Sync extends BriskersApi {
  final sent = <String, String>{};
  @override
  Future<Map<String, dynamic>> syncCreateManualTransaction(
    String businessId, {
    required String operationId,
    required String direction,
    required String accountId,
    required String categoryId,
    required num amount,
    required DateTime date,
    String? jobId,
    String? documentId,
    String? counterpartyId,
    String? counterpartyName,
    String? remarks,
  }) async {
    expect(accountId, 'checking');
    expect(categoryId, 'payroll');
    expect(remarks, contains('Zelle'));
    final id = sent.putIfAbsent(operationId, () => 'server-${sent.length + 1}');
    return {'transaction_id': id};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late BriskersLocalDatabase db;
  late LocalFinancialCache cache;
  late LocalPayrollExpenseRecovery service;
  late LocalOwnerAuthorization authority;
  late LocalOwnerGrant grant;
  final mode = BriskersConnectionModeController.instance;
  const week = '2026-11-09';
  const unrelated = {
    'id': 'original',
    'transaction_date': '2026-11-13',
    'direction': 'expense',
    'category': 'Supplies',
    'amount': 25.50,
    'counterparty': 'Vendor',
  };
  final sync = _Sync();

  void open() {
    db = BriskersLocalDatabase(
      NativeDatabase(File('${directory.path}/shop.sqlite')),
    );
    cache = LocalFinancialCache(database: db);
    service = LocalPayrollExpenseRecovery(
      db,
      writer: OfflineFinancialWriteService(database: db, api: sync),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await mode.setMode(BriskersConnectionMode.offline);
    sync.sent.clear();
    directory = await Directory.systemTemp.createTemp(
      'payroll-expense-recovery',
    );
    open();
    const identity = OwnerSessionIdentity('owner', 'saved-session');
    authority = LocalOwnerAuthorization(
      store: _Enrollment(),
      currentIdentity: () => identity,
      verifyOwner: (_) async => throw StateError('Network unavailable'),
      authenticateDevice: () async =>
          throw StateError('Device challenge unnecessary'),
      verifyLocalOwner: (business) async =>
          VerifiedOwnerEnrollment(identity, business),
    );
    grant = await authority.authorizeSession('shop');
    await LocalPayrollRepository(db, business: 'shop', owner: true).prepare();
    for (final (id, name) in [
      ('chris', 'Chris Rideaux'),
      ('kam', 'Kamerron Smith'),
    ]) {
      await db.customStatement(
        'INSERT INTO regular_payroll_employees VALUES(?,?,?,?,?)',
        ['shop', id, name, 4000, 0],
      );
    }
    for (final (op, employee, date, cents) in [
      ('receipt-a', 'chris', '2026-11-13', 55000),
      ('receipt-b', 'chris', '2026-11-15', 32000),
      ('receipt-c', 'kam', '2026-11-13', 56000),
    ]) {
      await db.customStatement(
        'INSERT INTO regular_payroll_payments VALUES(?,?,?,?,?,?,?,?,?,?)',
        ['shop', op, employee, week, '{}', cents, 0, cents, 'Zelle', date],
      );
    }
    await cache.saveOptions('shop', {
      'accounts': [
        {'id': 'checking', 'name': 'Business Checking – 9858', 'active': true},
      ],
      'categories': [
        {'id': 'payroll', 'name': 'Payroll', 'active': true},
      ],
    });
    await cache.saveTransactions('shop', [unrelated]);
    await cache.saveTransactionDetail('shop', 'original', {
      ...unrelated,
      'attachments': [
        {'id': 'original-photo'},
      ],
    });
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
    await mode.setMode(BriskersConnectionMode.auto);
  });

  test(
    'adds the three payouts once in Force Offline across restart and sync',
    () async {
      final before =
          (await db
                  .customSelect(
                    'SELECT * FROM regular_payroll_payments ORDER BY operation_id',
                  )
                  .get())
              .map((r) => r.data)
              .toList();
      final preview = await service.preview('shop', week);
      expect(
        preview.payouts.map((p) => (p.employee, p.date, p.cents, p.method)),
        [
          ('Chris Rideaux', '2026-11-13', 55000, 'Zelle'),
          ('Chris Rideaux', '2026-11-15', 32000, 'Zelle'),
          ('Kamerron Smith', '2026-11-13', 56000, 'Zelle'),
        ],
      );
      expect(preview.accountId, 'checking');
      expect(preview.categoryId, 'payroll');
      expect(preview.totalCents, 143000);
      expect(await service.reconcile(preview, grant), 3);
      expect(await service.reconcile(preview, grant), 0);
      expect((await service.preview('shop', week)).payouts, isEmpty);
      await OfflineFinancialWriteService(database: db, api: sync).flush('shop');
      expect(sync.sent, isEmpty);
      await db.close();
      open();
      expect(mode.forceOffline, isTrue);

      final rows = await cache.loadTransactions('shop');
      expect(rows, hasLength(4));
      expect(rows.singleWhere((r) => r['id'] == 'original'), unrelated);
      expect(
        (await cache.loadTransactionDetail('shop', 'original'))?['attachments'],
        [
          {'id': 'original-photo'},
        ],
      );
      expect((await LocalExpenseSubtotal.calculate(rows))?.expenses, 1455.50);
      for (final payout in preview.payouts) {
        final id = PayrollExpenseIdentity.transactionId(
          'shop',
          payout.reference,
        );
        expect(
          await PayrollExpenseLinkStore(
            db,
          ).transactionId('shop', payout.reference),
          id,
        );
        final row = rows.singleWhere((row) => row['id'] == id);
        expect(row['transaction_date'], payout.date);
        expect(row['amount'], payout.cents / 100);
        expect(row['counterparty'], payout.employee);
        expect(row['payment_method'], 'Zelle');
        expect(row['account_id'], 'checking');
        expect(row['category_id'], 'payroll');
      }
      expect(await service.reconcile(preview, grant), 0);
      expect(
        (await db
                .customSelect(
                  'SELECT * FROM regular_payroll_payments ORDER BY operation_id',
                )
                .get())
            .map((r) => r.data),
        before,
      );
      expect(
        await db.customSelect('SELECT * FROM sync_outbox').get(),
        hasLength(3),
      );

      await mode.setMode(BriskersConnectionMode.auto);
      final writer = OfflineFinancialWriteService(database: db, api: sync);
      await writer.flush('shop');
      await writer.flush('shop');
      expect(sync.sent, hasLength(3));
      final canonical = (await cache.loadTransactions(
        'shop',
      )).where((row) => row['id'].toString().startsWith('server-')).toList();
      expect(canonical, hasLength(3));
      await cache.mergeServerTransactions('shop', [
        for (final row in canonical)
          {...row, 'payroll_operation_id': null, 'payment_method': null},
      ]);
      final review = await LocalPayrollExpenseReview(db).forWeek('shop', week);
      expect(review.map((row) => row['status']), everyElement('In Expenses'));
      expect(await service.reconcile(preview, grant), 0);
      expect(
        (await cache.loadTransactions(
          'shop',
        )).where((r) => r['payment_method'] == 'Zelle'),
        hasLength(3),
      );
    },
  );

  test(
    'a possible matching saved detail blocks stale confirmation without a partial write',
    () async {
      final preview = await service.preview('shop', week);
      await cache.saveTransactionDetail('shop', 'detail-only', {
        'id': 'detail-only',
        'direction': 'expense',
        'date': '2026-11-13',
        'amount': 550,
        'counterparty': 'Chris',
      });
      await expectLater(service.reconcile(preview, grant), throwsStateError);
      expect(await db.customSelect('SELECT * FROM sync_outbox').get(), isEmpty);
      expect(await cache.loadTransactions('shop'), [unrelated]);
      expect(
        (await service.preview('shop', week)).payouts.map((p) => p.cents),
        [32000, 56000],
      );
      authority.lock();
      await expectLater(service.reconcile(preview, grant), throwsStateError);
    },
  );
}
